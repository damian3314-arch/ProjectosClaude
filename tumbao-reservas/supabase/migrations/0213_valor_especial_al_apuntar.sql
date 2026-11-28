-- 0213 · Valor especial al apuntar a mano (21 nov, pedido de Damián)
--
-- Pasó que entraron personas que pagaron $12.000 por clase (tarifa especial) y la caja solo sabía apuntar el precio
-- de la clase suelta. Ahora, al apuntar a alguien con clase suelta, recepción puede poner otro valor.
--
-- · Solo clase suelta. Entre $1.000 y $100.000. Si el valor es el normal, no queda como especial.
-- · Si es distinto del normal, el MOTIVO es obligatorio (mismo criterio que liberar/anular).
-- · Lo que se cobra (efectivo, o lo que se cobra al llegar) y lo que cuenta el cierre y las ventas es ese valor
--   (valor_reserva ya es el punto único; aquí lo hacemos mirar la columna nueva).
-- · No es promo: no se mezcla con la promo 2×$24.000 y SÍ se puede reprogramar.
-- · Queda en la auditoría de caja: valor, precio normal, motivo y quién lo apuntó.
-- Aditiva: una columna nueva y funciones reemplazadas. No borra nada.

alter table public.reservas
  add column if not exists valor_especial int check (valor_especial is null or valor_especial between 1000 and 100000),
  add column if not exists valor_especial_motivo text;

-- ── 1 · valor_reserva: lo especial manda ───────────────────────────────────────────────────────────
create or replace function public.valor_reserva(p_id uuid)
returns integer language sql stable security definer set search_path to 'public', 'pg_temp' as $$
  select coalesce(
    (select r.valor_especial from reservas r where r.id = p_id),
    (select (precio_del_grupo(r.id) /
             greatest(1, (select count(*) from reservas x
                           where coalesce(x.grupo_id, x.id) = coalesce(r.grupo_id, r.id)
                             and x.estado not in ('rechazada','expirada'))))::int
       from reservas r where r.id = p_id),
    (select c.precio_cop from reservas r join clases c on c.id = r.clase_id where r.id = p_id), 0)
$$;

-- ── 2 · apuntar a mano con valor especial ──────────────────────────────────────────────────────────
create or replace function public.admin_crear_reserva(p_token text, p_clase_id uuid, p_nombre text, p_telefono text,
                                                       p_tipo text default 'suelta', p_nota text default null,
                                                       p_medio text default null, p_valor integer default null,
                                                       p_motivo_valor text default null)
returns jsonb language plpgsql security definer set search_path to 'public','extensions','pg_temp' as $$
declare
  v_admin  uuid;
  v_tel    text;
  v_r      jsonb;
  v_cod    text;
  v_medio  text;
  v_precio int;
  v_normal int;
  v_esp    int := null;
  v_caja   jsonb;
  v_ef_ok  boolean := null;
  v_ef_msg text := null;
  v_puerta boolean := false;
  v_comp   text := null;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  if length(btrim(coalesce(p_nombre, ''))) < 2 then
    return jsonb_build_object('ok', false, 'error', 'NOMBRE_CORTO',
      'mensaje', 'Escribe el nombre de la persona.');
  end if;

  v_tel := regexp_replace(coalesce(p_telefono, ''), '\D', '', 'g');
  if length(v_tel) = 12 and left(v_tel, 2) = '57' then
    v_tel := substr(v_tel, 3);
  end if;
  if length(v_tel) <> 10 then
    return jsonb_build_object('ok', false, 'error', 'CELULAR_INVALIDO',
      'mensaje', 'El celular debe tener 10 dígitos.');
  end if;

  v_medio := nullif(btrim(lower(coalesce(p_medio, ''))), '');
  if v_medio is not null and v_medio not in ('efectivo', 'transferencia', 'en_puerta', 'plan_manual') then
    return jsonb_build_object('ok', false, 'error', 'MEDIO_INVALIDO',
      'mensaje', 'El pago tiene que ser efectivo, transferencia o al llegar.');
  end if;

  if p_tipo <> 'miembro' and v_medio is null then
    return jsonb_build_object('ok', false, 'error', 'MEDIO_OBLIGATORIO',
      'mensaje', 'Di cómo pagó: efectivo, paga al llegar o transferencia con el número del comprobante.');
  end if;

  -- Valor especial: solo clase suelta, dentro de un rango razonable, y con motivo si no es el precio normal.
  if p_valor is not null then
    if p_tipo = 'miembro' then
      return jsonb_build_object('ok', false, 'error', 'VALOR_SOLO_SUELTA',
        'mensaje', 'El valor especial solo aplica a clase suelta.');
    end if;
    if p_valor < 1000 or p_valor > 100000 then
      return jsonb_build_object('ok', false, 'error', 'VALOR_INVALIDO',
        'mensaje', 'El valor tiene que estar entre $1.000 y $100.000.');
    end if;
    select c.precio_cop into v_normal from clases c where c.id = p_clase_id;
    if v_normal is null then
      return jsonb_build_object('ok', false, 'error', 'CLASE_NO_EXISTE');
    end if;
    if p_valor <> v_normal then
      if length(btrim(coalesce(p_motivo_valor, ''))) < 3 then
        return jsonb_build_object('ok', false, 'error', 'MOTIVO_VALOR_OBLIGATORIO',
          'mensaje', 'Di por qué es ese valor (ej: tarifa especial, convenio, cortesía de Damián).');
      end if;
      v_esp := p_valor;
    end if;
  end if;

  if v_medio = 'transferencia' and p_tipo <> 'miembro' then
    v_comp := upper(regexp_replace(coalesce(p_nota, ''), '\s+', '', 'g'));
    if length(v_comp) < 4 then
      return jsonb_build_object('ok', false, 'error', 'COMPROBANTE_OBLIGATORIO',
        'mensaje', 'Escribe el número del comprobante de la transferencia (mínimo 4 caracteres).');
    end if;
    if exists (select 1 from reservas x
                where upper(regexp_replace(coalesce(x.referencia_pago, ''), '\s+', '', 'g')) = v_comp
                  and x.estado not in ('rechazada', 'expirada'))
       or exists (select 1 from pagos pg
                   where upper(regexp_replace(coalesce(pg.referencia, ''), '\s+', '', 'g')) = v_comp
                     and pg.consumido) then
      return jsonb_build_object('ok', false, 'error', 'REFERENCIA_REPETIDA',
        'mensaje', 'Ese comprobante ya se usó en otra reserva. Revisa que no sea el mismo pago.');
    end if;
  end if;

  if v_medio = 'plan_manual' then
    if p_tipo <> 'miembro' then
      return jsonb_build_object('ok', false, 'error', 'MEDIO_INVALIDO',
        'mensaje', 'Apuntar a mano con plan solo aplica a quien tiene plan.');
    end if;
    perform set_config('tumbao.plan_manual', '1', true);
  end if;

  v_r := tomar_cupo(p_clase_id, btrim(p_nombre), v_tel, null,
                    'recepcion',
                    case when p_tipo = 'miembro' then 'miembro' else 'suelta' end);

  perform set_config('tumbao.plan_manual', '', true);

  if (v_r->>'ok')::boolean is not true then
    return v_r;
  end if;

  v_cod := v_r->>'codigo';

  if (v_r->>'estado') <> 'confirmada' then
    update reservas
       set estado = 'confirmada',
           resuelta_por = v_admin,
           resuelta_at = now(),
           updated_at = now()
     where codigo = v_cod;
  end if;

  if v_comp is not null then
    update reservas set referencia_pago = left(v_comp, 60), pagador_nombre = 'Transferencia · comprobante ' || left(v_comp, 40)
     where codigo = v_cod;
  elsif p_nota is not null and btrim(p_nota) <> '' then
    update reservas set pagador_nombre = left(btrim(p_nota), 80) where codigo = v_cod;
  end if;

  if v_medio = 'plan_manual' then
    update reservas
       set pagador_nombre = left('Plan a mano (no estaba en AdminGym)'
                                 || coalesce(' · ' || nullif(btrim(p_nota), ''), ''), 80)
     where codigo = v_cod;
  end if;

  if v_esp is not null then
    update reservas
       set valor_especial = v_esp,
           valor_especial_motivo = left(btrim(p_motivo_valor), 120)
     where codigo = v_cod;
  end if;

  v_precio := coalesce(v_esp, (v_r->>'precio_cop')::int, 0);
  v_normal := coalesce(v_normal, (v_r->>'precio_cop')::int);

  if v_medio = 'efectivo' and (v_r->>'tipo') <> 'miembro' and v_precio > 0 then
    v_caja := caja_registrar(
      p_token, 'ingreso', 'clase_suelta', v_precio, 'efectivo',
      'Reserva ' || v_cod || ' — ' || btrim(p_nombre)
      || case when v_esp is not null then ' (valor especial: ' || btrim(p_motivo_valor) || ')' else '' end);

    v_ef_ok := coalesce((v_caja->>'ok')::boolean, false);
    if not v_ef_ok then
      v_ef_msg := coalesce(
        v_caja->>'mensaje',
        'No se pudo registrar el efectivo (' || coalesce(v_caja->>'error', 'motivo desconocido') || ').')
        || ' La reserva SÍ quedó: apunta esos '
        || to_char(v_precio, 'FM999G999G999') || ' en la caja a mano.';
    else
      update reservas set cobro_mov_id = (v_caja->>'id')::uuid,
                          cobrado_en_puerta_at = now()
       where codigo = v_cod;
    end if;
  end if;

  if v_medio = 'en_puerta' and (v_r->>'tipo') <> 'miembro' and v_precio > 0 then
    update reservas set cobra_en_puerta = true where codigo = v_cod;
    v_puerta := true;
  end if;

  perform auditar(v_admin, 'apuntar', v_cod, p_clase_id, btrim(p_nombre), v_precio,
                  'Medio: ' || coalesce(v_medio, 'plan') || coalesce(' · comprobante ' || v_comp, '')
                  || case when v_esp is not null
                          then ' · VALOR ESPECIAL ' || v_esp || ' (normal ' || v_normal || '): ' || btrim(p_motivo_valor)
                          else '' end,
                  jsonb_build_object('tipo', v_r->>'tipo', 'efectivo_registrado', v_ef_ok,
                                     'valor_especial', v_esp, 'precio_normal', v_normal));

  return jsonb_build_object(
    'ok', true,
    'codigo', v_cod,
    'nombre', btrim(p_nombre),
    'telefono', v_tel,
    'tipo', v_r->>'tipo',
    'clase', v_r->>'clase',
    'fecha_hora', v_r->>'fecha_hora',
    'precio_cop', v_precio,
    'precio_normal', v_normal,
    'valor_especial', v_esp is not null,
    'medio', v_medio,
    'efectivo_registrado', v_ef_ok,
    'aviso_efectivo', v_ef_msg,
    'cobra_en_puerta', v_puerta,
    'plan_manual', coalesce(v_medio = 'plan_manual', false),
    'mensaje', 'Reserva creada y confirmada.');
end;
$$;

revoke all on function public.admin_crear_reserva(text, uuid, text, text, text, text, text, integer, text)
  from public, anon, authenticated;
grant execute on function public.admin_crear_reserva(text, uuid, text, text, text, text, text, integer, text)
  to service_role;

-- La versión de 7 argumentos sigue existiendo (por si algo la llama) y pasa por la nueva sin valor especial.
create or replace function public.admin_crear_reserva(p_token text, p_clase_id uuid, p_nombre text, p_telefono text,
                                                       p_tipo text default 'suelta', p_nota text default null,
                                                       p_medio text default null)
returns jsonb language sql security definer set search_path to 'public','extensions','pg_temp' as $$
  select public.admin_crear_reserva(p_token, p_clase_id, p_nombre, p_telefono, p_tipo, p_nota, p_medio, null::integer, null::text)
$$;

-- ── 3 · quien paga al llegar se cobra por su valor; la lista de la puerta lo marca; reprogramar lo trata como suelta normal ──
do $do$
declare d text;
begin
  d := pg_get_functiondef('public.admin_marcar_asistencia(text,uuid,text,boolean)'::regprocedure);
  d := replace(d, 'coalesce(v_clase.precio_cop, 0), ''efectivo'',', 'valor_reserva(v_res.id), ''efectivo'',');
  d := replace(d, 'v_cobro := coalesce(v_clase.precio_cop, 0);', 'v_cobro := valor_reserva(v_res.id);');
  d := replace(d, 'v_cobro := -coalesce(v_clase.precio_cop, 0);', 'v_cobro := -valor_reserva(v_res.id);');
  if d ~ 'v_clase\.precio_cop' then raise exception 'parche de admin_marcar_asistencia no aplicó'; end if;
  execute d;

  d := pg_get_functiondef('public.admin_por_cobrar_en_puerta(text)'::regprocedure);
  d := replace(d, 'coalesce(c.precio_cop, 0)', 'valor_reserva(r.id)');
  if d ~ 'c\.precio_cop' then raise exception 'parche de admin_por_cobrar_en_puerta no aplicó'; end if;
  execute d;

  d := pg_get_functiondef('public._reprogramar_estado(text,text)'::regprocedure);
  d := replace(d, 'valor_reserva(r.id) < coalesce(c.precio_cop, 0) then', 'valor_reserva(r.id) < coalesce(c.precio_cop, 0) and r.valor_especial is null then');
  if d !~ 'valor_especial' then raise exception 'parche de _reprogramar_estado no aplicó'; end if;
  execute d;

  d := pg_get_functiondef('public.admin_reservas_de_clase(text,uuid)'::regprocedure);
  d := replace(d, 'case when r.tipo = ''suelta'' and valor_reserva(r.id) < c.precio_cop then ''promo''',
                  'case when r.valor_especial is not null then ''especial'' when r.tipo = ''suelta'' and valor_reserva(r.id) < c.precio_cop then ''promo''');
  if d !~ 'especial' then raise exception 'parche de admin_reservas_de_clase no aplicó'; end if;
  execute d;
end $do$;
