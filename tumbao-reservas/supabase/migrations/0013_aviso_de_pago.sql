-- =====================================================================
-- Lo que la persona declara al decir "ya pagué"
--
-- Hasta ahora, decir "ya pagué" solo movía la reserva a 'verificando'
-- con un PATCH desde n8n. No se guardaba nada de lo que la persona sabe
-- y el sistema no: a qué hora transfirió, quién pagó si no fue ella, y
-- el código de su comprobante.
--
-- Las tres cosas atacan el mismo problema. Hoy el pago se busca en una
-- ventana de -15 min a +3 horas alrededor de CUANDO EMPEZÓ a reservar,
-- que es antes de pagar. En esa ventana caben varias personas pagando
-- $15.000, y cuando eso pasa se necesita el nombre para desempatar.
--
-- Pero el nombre falla justo cuando más se necesita: **muchas veces paga
-- la mamá, la pareja o un amigo**, así que el nombre del banco no es el
-- de quien reserva. Nombre inútil + dos candidatos = validación manual
-- siempre.
--
-- Con la hora del comprobante la ventana pasa de 3 horas a ±15 minutos,
-- y con el nombre de quien paga el desempate vuelve a funcionar aunque
-- la cuenta sea de otro.
--
-- NO se guarda ninguna imagen. El comprobante se lee en el navegador de
-- quien paga (solo para sacarle el QR, si lo tiene) y se descarta ahí
-- mismo. Aquí solo llega texto.
-- =====================================================================

alter table reservas add column if not exists pagado_en timestamptz;
alter table reservas add column if not exists pagador_nombre text;
alter table reservas add column if not exists referencia_pago text;
alter table reservas add column if not exists comprobante_qr text;

comment on column reservas.pagado_en is
  'Hora de la transferencia, segun el comprobante de quien paga. Acota la busqueda del pago.';
comment on column reservas.pagador_nombre is
  'A nombre de quien sale la cuenta, cuando no es quien reserva. null = paga la misma persona.';
comment on column reservas.referencia_pago is
  'Referencia del comprobante. Sirve para que el mismo comprobante no se use dos veces.';

-- Un mismo comprobante no puede sustentar dos reservas. Parcial porque
-- la referencia es opcional: no todos los bancos la muestran igual.
create unique index if not exists reservas_referencia_unica
  on reservas (upper(btrim(referencia_pago)))
  where referencia_pago is not null and btrim(referencia_pago) <> '';


-- ---------------------------------------------------------------------
-- "Ya pagué"
--
-- Reemplaza el PATCH crudo que hacia n8n sobre la tabla. La decision de
-- si la reserva puede pasar a 'verificando' es logica de negocio y va
-- aqui, no en el enrutador.
-- ---------------------------------------------------------------------
create or replace function registrar_aviso_pago(
  p_codigo      text,
  p_pagado_en   timestamptz default null,
  p_referencia  text default null,
  p_pagador     text default null,
  p_qr          text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_reserva reservas%rowtype;
  v_ref     text := nullif(btrim(coalesce(p_referencia, '')), '');
  v_duena   text;
begin
  select * into v_reserva from reservas
   where upper(btrim(codigo)) = upper(btrim(p_codigo))
   for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'no_encontrada',
      'mensaje', 'No encontramos esa reserva.');
  end if;

  if v_reserva.estado = 'confirmada' then
    return jsonb_build_object('ok', true, 'estado', 'confirmada',
      'codigo', v_reserva.codigo, 'mensaje', 'Tu pago ya estaba confirmado.');
  end if;

  if v_reserva.estado not in ('pendiente_pago', 'verificando') then
    return jsonb_build_object('ok', false, 'error', 'estado_invalido',
      'estado', v_reserva.estado,
      'mensaje', 'Esa reserva esta en ' || v_reserva.estado || '. Escribenos por WhatsApp.');
  end if;

  -- Si esa referencia ya sustenta otra reserva, es el mismo comprobante
  -- reusado. Se avisa en vez de dejarlo pasar.
  if v_ref is not null then
    select codigo into v_duena from reservas
     where upper(btrim(referencia_pago)) = upper(v_ref)
       and id <> v_reserva.id
     limit 1;
    if v_duena is not null then
      return jsonb_build_object('ok', false, 'error', 'referencia_repetida',
        'mensaje', 'Ese comprobante ya se uso para otra reserva. ' ||
                   'Si crees que es un error escribenos por WhatsApp.');
    end if;
  end if;

  update reservas
     set estado          = 'verificando',
         pagado_en       = coalesce(p_pagado_en, pagado_en, now()),
         pagador_nombre  = coalesce(nullif(btrim(coalesce(p_pagador, '')), ''), pagador_nombre),
         referencia_pago = coalesce(v_ref, referencia_pago),
         comprobante_qr  = coalesce(nullif(btrim(coalesce(p_qr, '')), ''), comprobante_qr),
         updated_at      = now()
   where id = v_reserva.id;

  return jsonb_build_object('ok', true, 'estado', 'verificando',
    'codigo', v_reserva.codigo);
end;
$$;


-- ---------------------------------------------------------------------
-- Conciliación, ahora usando la hora declarada y el nombre de quien paga
--
-- Cambia solo la busqueda de candidatos respecto a 0008:
--   * si la reserva declaro hora, se busca a ±15 min de ESA hora;
--     si no, se mantiene la ventana vieja alrededor de created_at
--   * el nombre se compara contra quien paga de verdad
-- ---------------------------------------------------------------------
create or replace function registrar_pago_y_conciliar(
  p_banco      text,
  p_valor_cop  int,
  p_fecha_pago timestamptz,
  p_referencia text default null,
  p_remitente  text default null,
  p_ultimos_4  text default null,
  p_confianza  numeric default 1.0,
  p_raw_email  text default null,
  p_hoja_fila  text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_pago       pagos%rowtype;
  v_reserva    reservas%rowtype;
  v_candidatos int;
  v_con_nombre int;
  v_metodo     text := 'monto_unico';
begin
  if p_valor_cop is null or p_valor_cop <= 0 then
    return jsonb_build_object('ok', false, 'error', 'valor_invalido');
  end if;

  -- El conflicto se declara explicito: es el indice pagos_unicos, que es
  -- lo que hace que reprocesar el mismo correo no registre el pago dos
  -- veces. `on conflict do nothing` a secas no lo garantiza igual.
  insert into pagos (banco, valor_cop, fecha_pago, referencia,
                     remitente, ultimos_4, raw_email, hoja_fila)
  values (p_banco, p_valor_cop, p_fecha_pago, p_referencia,
          p_remitente, p_ultimos_4, p_raw_email, p_hoja_fila)
  on conflict (banco, valor_cop, fecha_pago, coalesce(referencia, ''))
  do nothing
  returning * into v_pago;

  if not found then
    select * into v_pago from pagos
     where banco = p_banco and valor_cop = p_valor_cop
       and fecha_pago = p_fecha_pago
       and coalesce(referencia, '') = coalesce(p_referencia, '');
    return jsonb_build_object('ok', true, 'duplicado', true,
      'pago_id', v_pago.id, 'accion', 'ninguna');
  end if;

  if p_confianza < 0.9 then
    return jsonb_build_object('ok', true, 'duplicado', false,
      'pago_id', v_pago.id, 'accion', 'solo_registrado',
      'motivo', 'confianza_baja');
  end if;

  create temp table if not exists _cand (id uuid, puntaje numeric) on commit drop;
  -- El "where true" no sobra: Supabase carga la extension safeupdate en
  -- las conexiones de PostgREST, y ahi un DELETE sin WHERE revienta con
  -- "DELETE requires a WHERE clause". Aplica hasta a las tablas temporales.
  delete from _cand where true;

  insert into _cand (id, puntaje)
  -- Se compara contra quien PAGA, no contra quien reserva. Cuando paga
  -- la mama o la pareja son personas distintas, y comparar contra quien
  -- reserva daria cero justo cuando hace falta desempatar.
  select r.id, similitud_nombre(coalesce(r.pagador_nombre, r.nombre), p_remitente)
    from reservas r
    join clases c on c.id = r.clase_id
   where r.estado in ('verificando', 'pendiente_validacion')
     and r.pago_id is null
     and c.precio_cop = p_valor_cop
     and case
           when r.pagado_en is not null then
             -- Hora declarada por quien pago: ventana corta.
             p_fecha_pago between r.pagado_en - interval '15 minutes'
                              and r.pagado_en + interval '15 minutes'
           else
             -- Sin hora declarada, la ventana vieja alrededor del momento
             -- en que empezo a reservar.
             p_fecha_pago between r.created_at - interval '15 minutes'
                              and r.created_at + interval '3 hours'
         end;

  select count(*) into v_candidatos from _cand;

  if v_candidatos = 0 then
    return jsonb_build_object('ok', true, 'duplicado', false,
      'pago_id', v_pago.id, 'accion', 'sin_reserva_que_casar');
  end if;

  if v_candidatos = 1 then
    -- Un solo candidato: se confirma sin mirar el nombre. Es el caso de
    -- "pago la mama": el nombre no coincide y da igual, no hay con quien
    -- confundirlo.
    select r.* into v_reserva from reservas r
     where r.id = (select id from _cand limit 1)
       for update skip locked;
  else
    select count(*) into v_con_nombre from _cand where puntaje >= 0.5;

    if v_con_nombre <> 1 then
      return jsonb_build_object('ok', true, 'duplicado', false,
        'pago_id', v_pago.id, 'accion', 'ambiguo',
        'candidatos', v_candidatos,
        'con_nombre_parecido', v_con_nombre,
        'remitente', p_remitente);
    end if;

    v_metodo := 'nombre_remitente';
    select r.* into v_reserva from reservas r
     where r.id = (select id from _cand where puntaje >= 0.5 limit 1)
       for update skip locked;
  end if;

  if not found then
    return jsonb_build_object('ok', true, 'duplicado', false,
      'pago_id', v_pago.id, 'accion', 'sin_reserva_que_casar');
  end if;

  update reservas
     set estado = 'confirmada', pago_id = v_pago.id, updated_at = now()
   where id = v_reserva.id;

  update pagos set consumido = true where id = v_pago.id;

  return jsonb_build_object('ok', true, 'duplicado', false,
    'pago_id', v_pago.id, 'accion', 'reserva_confirmada',
    'metodo', v_metodo, 'candidatos', v_candidatos,
    'reserva_id', v_reserva.id, 'codigo', v_reserva.codigo,
    'nombre', v_reserva.nombre, 'telefono', v_reserva.telefono);
end;
$$;


-- ---------------------------------------------------------------------
-- La cola de validación, con lo que declaró quien paga
-- ---------------------------------------------------------------------
create or replace function admin_pendientes(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin uuid;
  v_out   jsonb;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  select coalesce(jsonb_agg(x order by x->>'creada_at'), '[]'::jsonb) into v_out
  from (
    select jsonb_build_object(
      'codigo',      r.codigo,
      'nombre',      r.nombre,
      'telefono',    r.telefono,
      'estado',      r.estado,
      'creada_at',   r.created_at,
      'pagado_en',   r.pagado_en,
      'pagador',     r.pagador_nombre,
      'referencia',  r.referencia_pago,
      'clase',       c.nombre,
      'fecha_hora',  c.fecha_hora,
      'precio_cop',  c.precio_cop,
      'pagos_sueltos', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'pago_id',   p.id,
                 'valor_cop', p.valor_cop,
                 'fecha',     p.fecha_pago,
                 'remitente', p.remitente,
                 -- El parecido se mide contra quien paga de verdad.
                 'parecido',  round(similitud_nombre(
                                coalesce(r.pagador_nombre, r.nombre), p.remitente), 2),
                 -- Minutos de diferencia con la hora que declaro. Es el
                 -- dato que mas rapido resuelve el caso a ojo.
                 'minutos',   case when r.pagado_en is null then null
                              else round(extract(epoch from
                                     (p.fecha_pago - r.pagado_en)) / 60) end)
               order by case when r.pagado_en is null then 0
                        else abs(extract(epoch from (p.fecha_pago - r.pagado_en))) end)
          from pagos p
         where p.valor_cop = c.precio_cop
           and p.fecha_pago between coalesce(r.pagado_en, r.created_at) - interval '1 hour'
                               and coalesce(r.pagado_en, r.created_at) + interval '3 hours'
           and not exists (select 1 from reservas r2 where r2.pago_id = p.id)
      ), '[]'::jsonb)
    ) as x
    from reservas r
    join clases c on c.id = r.clase_id
   where r.estado in ('pendiente_validacion', 'verificando')
  ) s;

  return jsonb_build_object('ok', true, 'reservas', v_out);
end;
$$;


revoke execute on function registrar_aviso_pago(text, timestamptz, text, text, text)
  from public, anon, authenticated;
grant  execute on function registrar_aviso_pago(text, timestamptz, text, text, text)
  to service_role;
revoke execute on function registrar_pago_y_conciliar(text, int, timestamptz, text, text, text, numeric, text, text)
  from public, anon, authenticated;
grant  execute on function registrar_pago_y_conciliar(text, int, timestamptz, text, text, text, numeric, text, text)
  to service_role;
revoke execute on function admin_pendientes(text) from public, anon, authenticated;
grant  execute on function admin_pendientes(text) to service_role;
