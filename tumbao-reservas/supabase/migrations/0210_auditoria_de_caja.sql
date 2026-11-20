-- 0210 · Auditoría y control de caja (pedido de Damián, 19 nov 2026). Se publica DESPUÉS de las 10 pm, con el día cerrado.
-- Qué cierra esta migración:
--  1) Nada se rechaza ni se anula sin decir por qué: admin_rechazar y caja_anular exigen motivo (mín. 5 letras) y lo guardan.
--     Todo queda en caja_auditoria (quién, cuándo, a quién, cuánto, por qué). Las versiones viejas (sin motivo) ya no sirven desde afuera.
--  2) Recepción ya no puede apuntar a alguien sin decir cómo pagó: efectivo (entra a la caja), paga al llegar (cobra al marcar la
--     entrada) o transferencia CON número de comprobante (que no se haya usado antes). Con plan, como siempre.
--  3) Una reserva que dijo haber pagado (verificando / pendiente_validacion) y NO manda el soporte por WhatsApp en N minutos
--     (ajustes.validacion_max_min, por defecto 30) se libera sola. Si sí mandó imagen o documento, queda para la cajera.
--  4) auditoria_del_dia(dia): consulta para cuando haya que validar algo (liberadas y rechazadas con quién y por qué, anulaciones de caja,
--     recepción sin respaldo, comprobantes repetidos). NO se muestra en el cierre (Damián, 19 nov): el registro queda guardado en
--     caja_auditoria y se consulta cuando haga falta (Timba lo puede leer).
-- No borra datos. Sin DROP ni DELETE.

-- ── 1 · el registro ──────────────────────────────────────────────────────────────────────────────
create table if not exists public.caja_auditoria (
  id         uuid primary key default gen_random_uuid(),
  at         timestamptz not null default now(),
  admin_id   uuid,
  quien      text,
  accion     text not null,
  codigo     text,
  clase_id   uuid,
  nombre     text,
  valor_cop  integer,
  motivo     text,
  detalle    jsonb
);
create index if not exists caja_auditoria_at on public.caja_auditoria (at desc);
alter table public.caja_auditoria enable row level security;
revoke all on public.caja_auditoria from anon, authenticated;

alter table public.caja_movimientos add column if not exists anulado_motivo text;

create or replace function public.auditar(p_admin uuid, p_accion text, p_codigo text, p_clase uuid, p_nombre text,
                                           p_valor integer, p_motivo text, p_detalle jsonb default null)
returns void language sql security definer set search_path to 'public','pg_temp' as $$
  insert into caja_auditoria (admin_id, quien, accion, codigo, clase_id, nombre, valor_cop, motivo, detalle)
  values (p_admin, coalesce((select t.nombre from admin_tokens t where t.id = p_admin), 'Sistema'),
          p_accion, p_codigo, p_clase, p_nombre, p_valor, nullif(btrim(p_motivo), ''), p_detalle);
$$;
revoke all on function public.auditar(uuid, text, text, uuid, text, integer, text, jsonb) from public, anon, authenticated;

-- ── 2 · anular un movimiento de caja: con motivo ──────────────────────────────────────────────────
create or replace function public.caja_anular(p_token text, p_id uuid, p_motivo text)
returns jsonb language plpgsql security definer set search_path to 'public','extensions','pg_temp' as $$
declare
  v_admin uuid;
  v_mov   caja_movimientos;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;
  if length(btrim(coalesce(p_motivo, ''))) < 5 then
    return jsonb_build_object('ok', false, 'error', 'MOTIVO_OBLIGATORIO',
      'mensaje', 'Escribe por qué anulas este movimiento (mínimo 5 letras).');
  end if;

  select * into v_mov from caja_movimientos where id = p_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'NO_EXISTE');
  end if;
  if v_mov.anulado then
    return jsonb_build_object('ok', false, 'error', 'YA_ANULADO');
  end if;
  if v_mov.dia <> (now() at time zone 'America/Bogota')::date then
    return jsonb_build_object('ok', false, 'error', 'OTRO_DIA',
      'mensaje', 'Solo se pueden anular movimientos de hoy.');
  end if;
  if exists (select 1 from caja_cierres where dia = v_mov.dia) then
    return jsonb_build_object('ok', false, 'error', 'DIA_CERRADO',
      'mensaje', 'El día ya está cerrado. El ajuste va mañana.');
  end if;

  update caja_movimientos
     set anulado = true, anulado_at = now(), anulado_por = v_admin,
         anulado_motivo = left(btrim(p_motivo), 200), pago_id = null
   where id = p_id;

  if v_mov.pago_id is not null then
    perform devolver_al_grupo(v_mov.pago_id, v_mov.valor_cop);
  end if;

  perform auditar(v_admin, 'anular_movimiento', null, null, v_mov.concepto, v_mov.valor_cop, p_motivo,
                  jsonb_build_object('mov_id', p_id, 'medio', v_mov.medio, 'sentido', v_mov.sentido, 'nota', v_mov.nota));

  return jsonb_build_object('ok', true, 'valor_cop', v_mov.valor_cop,
                            'concepto', v_mov.concepto,
                            'libero_pago', v_mov.pago_id is not null);
end;
$$;

-- La versión sin motivo sigue existiendo SOLO para lo que el sistema anula por dentro (marcar asistencia al revés, rechazar una
-- reserva): deja el motivo escrito y queda en la auditoría. Desde el panel el Worker ya exige el motivo.
create or replace function public.caja_anular(p_token text, p_id uuid)
returns jsonb language sql security definer set search_path to 'public','extensions','pg_temp' as $$
  select caja_anular(p_token, p_id, 'Automático: se deshizo la reserva o la entrada que originó este cobro');
$$;

-- ── 3 · rechazar / liberar una reserva: con motivo ────────────────────────────────────────────────
-- La función nueva (con p_motivo) se arma PARCHANDO la que ya existe, para no copiar su lógica a mano: misma lógica, más el motivo.
do $do$
declare d text;
begin
  d := pg_get_functiondef('public.admin_rechazar(text,text)'::regprocedure);
  d := replace(d, 'admin_rechazar(p_token text, p_codigo text)', 'admin_rechazar(p_token text, p_codigo text, p_motivo text)');
  d := replace(d, E'  v_aviso    text := null;\n',
                  E'  v_aviso    text := null;\n  v_motivo   text := left(btrim(coalesce(p_motivo, '''')), 200);\n');
  d := replace(d, E'  select * into v_reserva from reservas\n   where codigo = upper(trim(p_codigo)) for update;',
                  E'  if length(v_motivo) < 5 then\n'
                  E'    return jsonb_build_object(''ok'', false, ''error'', ''MOTIVO_OBLIGATORIO'',\n'
                  E'      ''mensaje'', ''Escribe por qué liberas este cupo (mínimo 5 letras).'');\n'
                  E'  end if;\n\n'
                  E'  select * into v_reserva from reservas\n   where codigo = upper(trim(p_codigo)) for update;');
  d := replace(d, 'caja_anular(p_token, v_reserva.cobro_mov_id)',
                  'caja_anular(p_token, v_reserva.cobro_mov_id, ''Reserva '' || v_reserva.codigo || '' liberada: '' || v_motivo)');
  d := replace(d, E'           resuelta_at   = now(),\n           updated_at    = now()\n     where coalesce(grupo_id, id) = v_grupo',
                  E'           resuelta_at   = now(),\n           motivo_rechazo = v_motivo,\n           updated_at    = now()\n     where coalesce(grupo_id, id) = v_grupo');
  d := replace(d, E'  return jsonb_build_object(''ok'', true, ''estado'', ''rechazada'',\n    ''codigo'', v_reserva.codigo, ''nombre'', v_reserva.nombre,',
                  E'  perform auditar(v_admin, ''liberar_reserva'', v_reserva.codigo, v_reserva.clase_id, v_reserva.nombre, v_devuelto, v_motivo,\n'
                  E'                  jsonb_build_object(''estado_antes'', v_reserva.estado, ''origen'', v_reserva.origen, ''cupos'', v_n,\n'
                  E'                                     ''tenia_pago'', v_reserva.pago_id is not null, ''referencia'', v_reserva.referencia_pago));\n\n'
                  E'  return jsonb_build_object(''ok'', true, ''estado'', ''rechazada'',\n    ''codigo'', v_reserva.codigo, ''nombre'', v_reserva.nombre,');
  if d !~ 'p_motivo text' or d !~ 'MOTIVO_OBLIGATORIO' or d !~ 'motivo_rechazo = v_motivo' or d !~ 'auditar\(v_admin, ''liberar_reserva''' or d !~ 'liberada: ' then
    raise exception 'parche de admin_rechazar no aplicó';
  end if;
  execute d;
end $do$;

-- La de dos argumentos ya no libera nada: obliga a usar la que pide motivo.
create or replace function public.admin_rechazar(p_token text, p_codigo text)
returns jsonb language sql security definer set search_path to 'public','extensions','pg_temp' as $$
  select jsonb_build_object('ok', false, 'error', 'MOTIVO_OBLIGATORIO',
    'mensaje', 'Escribe por qué liberas este cupo (mínimo 5 letras).');
$$;

-- Deshacer también deja huella.
do $do$
declare d text;
begin
  d := pg_get_functiondef('public.admin_deshacer(text,text)'::regprocedure);
  d := replace(d, E'  return jsonb_build_object(''ok'', true,\n    ''codigo'',  v_reserva.codigo,',
                  E'  perform auditar(v_admin, ''deshacer'', v_reserva.codigo, v_reserva.clase_id, v_reserva.nombre, null,\n'
                  E'                  ''Deshizo: '' || v_reserva.estado || '' → '' || v_reserva.estado_antes, null);\n'
                  E'  return jsonb_build_object(''ok'', true,\n    ''codigo'',  v_reserva.codigo,');
  if d !~ 'auditar\(v_admin, ''deshacer''' then raise exception 'parche de admin_deshacer no aplicó'; end if;
  execute d;
end $do$;

-- ── 4 · apuntar a mano: cómo pagó, sí o sí ────────────────────────────────────────────────────────
create or replace function public.admin_crear_reserva(p_token text, p_clase_id uuid, p_nombre text, p_telefono text,
                                                       p_tipo text default 'suelta', p_nota text default null,
                                                       p_medio text default null)
returns jsonb language plpgsql security definer set search_path to 'public','extensions','pg_temp' as $$
declare
  v_admin  uuid;
  v_tel    text;
  v_r      jsonb;
  v_cod    text;
  v_medio  text;
  v_precio int;
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

  -- 0210: una clase suelta no se apunta sin decir cómo se paga. Con plan no se cobra.
  if p_tipo <> 'miembro' and v_medio is null then
    return jsonb_build_object('ok', false, 'error', 'MEDIO_OBLIGATORIO',
      'mensaje', 'Di cómo pagó: efectivo, paga al llegar o transferencia con el número del comprobante.');
  end if;

  -- 0210: la transferencia se apunta con el número del comprobante, y ese número no puede haberse usado ya.
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

  v_precio := coalesce((v_r->>'precio_cop')::int, 0);

  if v_medio = 'efectivo' and (v_r->>'tipo') <> 'miembro' and v_precio > 0 then
    v_caja := caja_registrar(
      p_token, 'ingreso', 'clase_suelta', v_precio, 'efectivo',
      'Reserva ' || v_cod || ' — ' || btrim(p_nombre));

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
                  'Medio: ' || coalesce(v_medio, 'plan') || coalesce(' · comprobante ' || v_comp, ''),
                  jsonb_build_object('tipo', v_r->>'tipo', 'efectivo_registrado', v_ef_ok));

  return jsonb_build_object(
    'ok', true,
    'codigo', v_cod,
    'nombre', btrim(p_nombre),
    'telefono', v_tel,
    'tipo', v_r->>'tipo',
    'clase', v_r->>'clase',
    'fecha_hora', v_r->>'fecha_hora',
    'precio_cop', v_precio,
    'medio', v_medio,
    'efectivo_registrado', v_ef_ok,
    'aviso_efectivo', v_ef_msg,
    'cobra_en_puerta', v_puerta,
    'plan_manual', coalesce(v_medio = 'plan_manual', false),
    'mensaje', 'Reserva creada y confirmada.');
end;
$$;

-- ── 5 · sin soporte, se libera ────────────────────────────────────────────────────────────────────
create or replace function public.liberar_cupos_expirados()
returns integer language plpgsql security definer set search_path to 'public','extensions','pg_temp' as $$
declare
  v_n   int;
  v_n2  int := 0;
  v_min int := coalesce(nullif((select valor from ajustes where clave = 'validacion_max_min'), '')::int, 30);
begin
  with liberadas as (
    update reservas set estado = 'expirada', updated_at = now()
    where estado = 'pendiente_pago' and expira_en < now()
    returning clase_id
  ),
  por_clase as (
    select clase_id, count(*)::int as n from liberadas group by clase_id
  ),
  ajuste as (
    update clases c set cupo_tomado = greatest(0, c.cupo_tomado - p.n)
    from por_clase p
    where c.id = p.clase_id
    returning p.n
  )
  select coalesce(sum(n), 0)::int into v_n from ajuste;

  -- 0210: dijo que pagó (verificando / pendiente_validacion), no hay pago enlazado y pasaron N minutos sin que mandara imagen
  -- o documento por WhatsApp: se libera el cupo y queda escrito por qué. Si mandó el soporte, se queda para la cajera.
  with sin_soporte as (
    select r.id, r.codigo, r.clase_id, r.nombre, r.referencia_pago
      from reservas r
     where r.estado in ('verificando', 'pendiente_validacion')
       and r.pago_id is null
       and r.tipo = 'suelta'
       and r.updated_at < now() - make_interval(mins => v_min)
       and not exists (
         select 1 from wa_mensajes m
          where m.direccion = 'entrante' and m.tipo in ('image', 'document')
            and right(regexp_replace(m.telefono, '\D', '', 'g'), 10) = right(regexp_replace(coalesce(r.telefono, ''), '\D', '', 'g'), 10)
            and m.creado_at > r.created_at)
     order by r.created_at
     for update skip locked),
  marcadas as (
    update reservas r
       set estado = 'expirada', motivo_rechazo = 'Sin soporte por WhatsApp en ' || v_min || ' min: cupo liberado',
           updated_at = now()
      from sin_soporte s
     where r.id = s.id
    returning r.clase_id, r.codigo, r.nombre, r.referencia_pago),
  aud as (
    insert into caja_auditoria (admin_id, quien, accion, codigo, clase_id, nombre, motivo, detalle)
    select null, 'Sistema', 'liberar_sin_soporte', codigo, clase_id, nombre,
           'No compartió el comprobante por WhatsApp en ' || v_min || ' min', jsonb_build_object('referencia', referencia_pago)
      from marcadas
    returning 1),
  por_clase2 as (
    select clase_id, count(*)::int as n from marcadas group by clase_id),
  ajuste2 as (
    update clases c set cupo_tomado = greatest(0, c.cupo_tomado - p.n)
      from por_clase2 p
     where c.id = p.clase_id
    returning p.n)
  select coalesce(sum(n), 0)::int into v_n2 from ajuste2;

  return v_n + v_n2;
end;
$$;

-- ── 6 · lo que hay que mirar antes de cerrar ──────────────────────────────────────────────────────
create or replace function public.auditoria_del_dia(p_dia date)
returns jsonb language sql stable security definer set search_path to 'public','pg_temp' as $$
  with lib as (
    select r.codigo, r.nombre, r.estado::text estado, r.origen,
           to_char(coalesce(r.resuelta_at, r.updated_at) at time zone 'America/Bogota', 'HH24:MI') hora,
           (select t.nombre from admin_tokens t where t.id = r.resuelta_por) quien,
           r.motivo_rechazo motivo,
           (r.pago_id is not null or r.cobro_mov_id is not null or r.referencia_pago is not null) tuvo_pago,
           (select to_char(c.fecha_hora at time zone 'America/Bogota', 'HH24:MI') from clases c where c.id = r.clase_id) clase_hora
      from reservas r
     where r.estado in ('rechazada', 'expirada')
       and (coalesce(r.resuelta_at, r.updated_at) at time zone 'America/Bogota')::date = p_dia
       and (r.estado = 'rechazada' or r.motivo_rechazo is not null or r.referencia_pago is not null)),
  anul as (
    select m.concepto, m.valor_cop, m.medio, m.anulado_motivo motivo,
           to_char(m.anulado_at at time zone 'America/Bogota', 'HH24:MI') hora,
           (select t.nombre from admin_tokens t where t.id = m.anulado_por) quien
      from caja_movimientos m
     where m.anulado and (m.anulado_at at time zone 'America/Bogota')::date = p_dia),
  sinresp as (
    select r.codigo, r.nombre, to_char(c.fecha_hora at time zone 'America/Bogota', 'HH24:MI') clase_hora
      from reservas r join clases c on c.id = r.clase_id
     where r.estado = 'confirmada' and r.tipo = 'suelta' and r.origen = 'recepcion'
       and r.pago_id is null and r.cobro_mov_id is null and coalesce(r.cobra_en_puerta, false) = false
       and r.referencia_pago is null
       and (c.fecha_hora at time zone 'America/Bogota')::date = p_dia),
  repetidas as (
    select upper(regexp_replace(r.referencia_pago, '\s+', '', 'g')) referencia,
           count(distinct coalesce(r.grupo_id, r.id)) compras, string_agg(distinct r.nombre, ' · ') quienes
      from reservas r join clases c on c.id = r.clase_id
     where r.referencia_pago is not null and r.estado not in ('rechazada', 'expirada')
       and (c.fecha_hora at time zone 'America/Bogota')::date = p_dia
     group by 1 having count(distinct coalesce(r.grupo_id, r.id)) > 1)
  select jsonb_build_object(
    'dia', p_dia,
    'liberadas', coalesce((select jsonb_agg(to_jsonb(l) order by l.hora) from lib l), '[]'::jsonb),
    'anulaciones', coalesce((select jsonb_agg(to_jsonb(a) order by a.hora) from anul a), '[]'::jsonb),
    'recepcion_sin_respaldo', coalesce((select jsonb_agg(to_jsonb(s)) from sinresp s), '[]'::jsonb),
    'comprobantes_repetidos', coalesce((select jsonb_agg(to_jsonb(x)) from repetidas x), '[]'::jsonb),
    'por_revisar',
      (select count(*) from lib where motivo is null) + (select count(*) from anul where motivo is null)
      + (select count(*) from sinresp) + (select count(*) from repetidas));
$$;
revoke all on function public.auditoria_del_dia(date) from public, anon, authenticated;
grant execute on function public.auditoria_del_dia(date) to service_role;
