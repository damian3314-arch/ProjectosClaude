-- 0112 · Validar a mano la tiquetera comprada en la página, y el código
--        llega por WhatsApp solo cuando el pago está confirmado.
--
-- LO QUE DIJO DAMIÁN (28 sep)
-- «Si la persona dio en "ya pagué" y el pago no se comprobó
--  automáticamente, no se le envía mensaje de confirmación ni el código
--  hasta que envíe el soporte al WhatsApp de Tumbao y se pueda comprobar
--  que la plata entró. Ya confirmado, sí le llega su mensaje. En las
--  tiqueteras se necesita un botón para marcar validado manual.»
--
-- LO QUE YA ERA ASÍ: un código pendiente no reserva nada (tomar_cupo
-- exige estado 'confirmada'), y "recuperar código" solo devuelve
-- tiqueteras confirmadas.
--
-- LO NUEVO
--   · admin_tiqueteras_listar dice el estado de cada una y trae las
--     pendientes arriba (las que dieron "ya pagué" o quedaron para
--     validar), para que el panel les ponga el botón.
--   · admin_tiquetera_validar(): recepción la confirma a mano con el
--     depósito del banco (si ya aparece) o con la referencia del
--     comprobante. Gasta el depósito, recalcula el vencimiento desde hoy
--     (no pierde días por esperar la validación) y la activa. El ingreso
--     entra al cierre solo (disparador de la 0111).
--   · wa_encolar_tiquetera(): cuando una tiquetera queda confirmada (sola,
--     a mano o vendida en recepción) se encola el WhatsApp
--     'tiquetera_activa' con su código. Encendido con
--     ajustes.wa_aviso_tiquetera cuando Meta apruebe la plantilla.

-- ── 1. la lista dice el estado ───────────────────────────────────────
create or replace function public.admin_tiqueteras_listar(p_token text, p_estado text default 'activas')
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $function$
declare
  v_admin uuid;
  v_hoy   date := (now() at time zone 'America/Bogota')::date;
  v_lista jsonb;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', t.id, 'codigo', t.codigo, 'nombre', t.nombre,
           'telefono', t.telefono, 'clases_totales', t.clases_totales,
           'clases_usadas', t.clases_usadas,
           'clases_restantes', t.clases_totales - t.clases_usadas,
           'precio_cop', t.precio_cop, 'vence_el', t.vence_el,
           'activa', t.activa, 'creada_en', t.creada_en,
           -- 0112: el estado del pago y si la persona dijo "ya pagué".
           'estado', t.estado,
           'en_linea', t.creada_por is null,
           'reporto_pago', t.pagado_en is not null and t.estado <> 'confirmada',
           'referencia', t.referencia
         ) order by (t.estado <> 'confirmada') desc, t.creada_en desc), '[]'::jsonb)
    into v_lista
    from tiqueteras t
   where case p_estado
           when 'activas' then
             (t.estado = 'confirmada' and t.activa and t.vence_el >= v_hoy
              and t.clases_usadas < t.clases_totales)
             -- Por validar: dijo "ya pagué" o la página la mandó a validar.
             or (t.estado = 'pendiente_validacion')
             or (t.estado = 'pendiente_pago' and t.pagado_en is not null)
           else true
         end;

  return jsonb_build_object('ok', true, 'tiqueteras', v_lista);
end;
$function$;
revoke all on function public.admin_tiqueteras_listar(text, text) from public, anon, authenticated;

-- ── 2. validar a mano ────────────────────────────────────────────────
create or replace function public.admin_tiquetera_validar(
  p_token text, p_id bigint, p_pago_id uuid default null, p_referencia text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin uuid;
  v_t     tiqueteras%rowtype;
  v_ref   text := nullif(btrim(coalesce(p_referencia, '')), '');
  v_hoy   date := (now() at time zone 'America/Bogota')::date;
  v_vig   int;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select * into v_t from tiqueteras where id = p_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'NO_EXISTE',
      'mensaje', 'Esa tiquetera no existe. Recarga la lista.');
  end if;
  if v_t.estado = 'confirmada' then
    return jsonb_build_object('ok', false, 'error', 'YA_CONFIRMADA',
      'mensaje', 'Esa tiquetera ya estaba activa.');
  end if;
  if p_pago_id is null and (v_ref is null or length(v_ref) < 4) then
    return jsonb_build_object('ok', false, 'error', 'SOPORTE_REQUERIDO',
      'mensaje', 'Escoge el depósito del banco o escribe la referencia del comprobante que mandó.');
  end if;

  if p_pago_id is not null then
    perform 1 from pagos where id = p_pago_id for update;
    if not found then
      return jsonb_build_object('ok', false, 'error', 'PAGO_NO_EXISTE',
        'mensaje', 'Ese depósito ya no está. Recarga la lista.');
    end if;
    if saldo_grupo(p_pago_id) < coalesce(v_t.precio_cop, 0) then
      return jsonb_build_object('ok', false, 'error', 'VALOR_NO_ALCANZA',
        'mensaje', 'A ese depósito le quedan ' || to_char(saldo_grupo(p_pago_id), 'FM999G999G999')
                   || ' y la tiquetera vale ' || to_char(coalesce(v_t.precio_cop, 0), 'FM999G999G999') || '.');
    end if;
    perform gastar_del_grupo(p_pago_id, coalesce(v_t.precio_cop, 0));
  end if;

  -- La vigencia corre desde que se activa: esperar la validación no le
  -- quita días.
  v_vig := greatest(v_t.vence_el - (v_t.creada_en at time zone 'America/Bogota')::date, 1);

  update tiqueteras
     set estado = 'confirmada',
         pago_id = coalesce(p_pago_id, pago_id),
         referencia = coalesce(v_ref, referencia),
         pagado_en = coalesce(pagado_en, now()),
         activa = true,
         vence_el = greatest(vence_el, v_hoy + v_vig)
   where id = p_id
   returning * into v_t;

  return jsonb_build_object('ok', true, 'id', v_t.id, 'codigo', v_t.codigo,
    'nombre', v_t.nombre, 'clases', v_t.clases_totales, 'vence_el', v_t.vence_el,
    'con_deposito', p_pago_id is not null);
end;
$$;
revoke all on function public.admin_tiquetera_validar(text, bigint, uuid, text) from public, anon, authenticated;

-- El ingreso de la 0111 anota la referencia del comprobante si la hay.
create or replace function public.tiquetera_ingreso_en_linea()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_dia date := (now() at time zone 'America/Bogota')::date;
begin
  if new.estado = 'confirmada' and coalesce(old.estado, '') <> 'confirmada'
     and new.creada_por is null
     and coalesce(new.precio_cop, 0) > 0
     and not exists (select 1 from caja_movimientos m
                      where m.tiquetera_id = new.id and not m.anulado) then
    if exists (select 1 from caja_cierres where dia = v_dia) then
      v_dia := v_dia + 1;
    end if;
    insert into caja_movimientos (dia, sentido, concepto, valor_cop, medio, nota,
                                  registrado_por, pago_id, cantidad, origen, tiquetera_id)
    values (v_dia, 'ingreso', 'tiquetera', new.precio_cop, 'transferencia',
            'Tiquetera ' || new.codigo || ' · ' || new.nombre || ' · comprada en la página'
              || coalesce(' · ref ' || nullif(btrim(new.referencia), ''), ''),
            null, new.pago_id, 1, 'caja_menor', new.id);
  end if;
  return new;
end;
$$;

-- ── 3. el WhatsApp con el código, solo cuando está confirmada ────────
insert into public.ajustes (clave, valor, nota) values
  ('wa_aviso_tiquetera', 'apagado',
   'Enviar el WhatsApp tiquetera_activa (con el código) cuando una tiquetera queda confirmada. Se enciende cuando Meta aprueba la plantilla. 0112.')
on conflict (clave) do nothing;

create or replace function public.wa_encolar_tiquetera()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_tel text;
begin
  if new.estado <> 'confirmada' then return new; end if;
  if tg_op = 'UPDATE' and old.estado = 'confirmada' then return new; end if;
  if coalesce((select valor from ajustes where clave = 'wa_aviso_tiquetera'), 'apagado')
     <> 'encendido' then
    return new;
  end if;
  v_tel := right(regexp_replace(coalesce(new.telefono, ''), '\D', '', 'g'), 10);
  if v_tel !~ '^3[0-9]{9}$' then return new; end if;

  insert into wa_avisos (clave, tipo, telefono, plantilla, variables, vence_at)
  values ('tiquetera_activa:' || new.id, 'tiquetera_activa', v_tel, 'tiquetera_codigo',
          jsonb_build_array(
            coalesce(nullif(initcap(split_part(btrim(new.nombre), ' ', 1)), ''), 'amigo(a)'),
            new.clases_totales::text, new.codigo, wa_fecha_texto(new.vence_el)),
          now() + interval '3 days')
  on conflict (clave) do nothing;
  return new;
exception when others then
  -- Un aviso NUNCA puede tumbar una venta.
  raise warning 'wa_encolar_tiquetera: %', sqlerrm;
  return new;
end;
$$;
revoke all on function public.wa_encolar_tiquetera() from public, anon, authenticated;

drop trigger if exists wa_aviso_tiquetera on public.tiqueteras;
create trigger wa_aviso_tiquetera
  after insert or update of estado on public.tiqueteras
  for each row execute function public.wa_encolar_tiquetera();
