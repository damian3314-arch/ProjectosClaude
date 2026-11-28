-- =====================================================================
-- Tumbao Reservas — conciliación de pagos
--
-- Dos caminos hacia la misma decisión, según qué llegue primero:
--
--   A) El correo del banco llega DESPUÉS de que la persona subió el
--      comprobante  → registrar_pago_y_conciliar()  (la ruta normal)
--   B) El correo del banco llega ANTES  → conciliar_reserva()
--      (la persona se demoró subiendo la captura; lo llama el polling
--      de la barra de progreso)
--
-- Ambos comparten la misma regla: si hay exactamente UN pago candidato
-- sin consumir, se confirma. Si hay cero o más de uno, va a validación
-- humana. Ante la duda gana el humano.
-- =====================================================================

-- Ventana de tolerancia entre el momento de la reserva y el del pago.
-- El margen hacia atrás cubre el desfase de reloj entre el banco y
-- nosotros; el de adelante, que la persona se demore pagando.
-- (Se dejan como constantes en el cuerpo para que se vean al leer.)


-- ---------------------------------------------------------------------
-- A) Llega un pago del banco: se registra y se intenta casar.
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
  v_pago      pagos%rowtype;
  v_reserva   reservas%rowtype;
  v_candidatos int;
begin
  if p_valor_cop is null or p_valor_cop <= 0 then
    return jsonb_build_object('ok', false, 'error', 'valor_invalido');
  end if;

  ------------------------------------------------------------------
  -- 1. Registrar el pago (idempotente por el índice pagos_unicos)
  ------------------------------------------------------------------
  insert into pagos (banco, valor_cop, fecha_pago, referencia,
                     remitente, ultimos_4, raw_email, hoja_fila)
  values (p_banco, p_valor_cop, p_fecha_pago, p_referencia,
          p_remitente, p_ultimos_4, p_raw_email, p_hoja_fila)
  on conflict (banco, valor_cop, fecha_pago, coalesce(referencia, ''))
  do nothing
  returning * into v_pago;

  if not found then
    -- Ya estaba: el mismo correo llegó dos veces. No es un error.
    select * into v_pago from pagos
     where banco = p_banco and valor_cop = p_valor_cop
       and fecha_pago = p_fecha_pago
       and coalesce(referencia, '') = coalesce(p_referencia, '');
    return jsonb_build_object(
      'ok', true, 'duplicado', true,
      'pago_id', v_pago.id, 'accion', 'ninguna');
  end if;

  ------------------------------------------------------------------
  -- 2. Si el parser no estaba seguro, se registra pero no se concilia
  ------------------------------------------------------------------
  if p_confianza < 0.9 then
    return jsonb_build_object(
      'ok', true, 'duplicado', false, 'pago_id', v_pago.id,
      'accion', 'solo_registrado', 'motivo', 'confianza_baja');
  end if;

  ------------------------------------------------------------------
  -- 3. Buscar reservas esperando este monto
  ------------------------------------------------------------------
  select count(*) into v_candidatos
    from reservas r
    join clases c on c.id = r.clase_id
   where r.estado in ('verificando', 'pendiente_validacion')
     and r.pago_id is null
     and c.precio_cop = p_valor_cop
     and p_fecha_pago between r.created_at - interval '15 minutes'
                          and r.created_at + interval '3 hours';

  if v_candidatos = 0 then
    return jsonb_build_object(
      'ok', true, 'duplicado', false, 'pago_id', v_pago.id,
      'accion', 'sin_reserva_que_casar');
  end if;

  if v_candidatos > 1 then
    -- Dos personas pagaron lo mismo casi al tiempo. Adivinar aquí es
    -- confirmarle la clase a quien no pagó.
    return jsonb_build_object(
      'ok', true, 'duplicado', false, 'pago_id', v_pago.id,
      'accion', 'ambiguo', 'candidatos', v_candidatos);
  end if;

  ------------------------------------------------------------------
  -- 4. Exactamente una: se confirma
  ------------------------------------------------------------------
  select r.* into v_reserva
    from reservas r
    join clases c on c.id = r.clase_id
   where r.estado in ('verificando', 'pendiente_validacion')
     and r.pago_id is null
     and c.precio_cop = p_valor_cop
     and p_fecha_pago between r.created_at - interval '15 minutes'
                          and r.created_at + interval '3 hours'
     for update of r
     skip locked;

  if not found then
    -- Otra transacción la tomó entre el conteo y aquí.
    return jsonb_build_object(
      'ok', true, 'duplicado', false, 'pago_id', v_pago.id,
      'accion', 'sin_reserva_que_casar');
  end if;

  update reservas
     set estado = 'confirmada', pago_id = v_pago.id, updated_at = now()
   where id = v_reserva.id;

  update pagos set consumido = true where id = v_pago.id;

  return jsonb_build_object(
    'ok', true, 'duplicado', false, 'pago_id', v_pago.id,
    'accion', 'reserva_confirmada',
    'reserva_id', v_reserva.id, 'codigo', v_reserva.codigo,
    'nombre', v_reserva.nombre, 'telefono', v_reserva.telefono);
end;
$$;


-- ---------------------------------------------------------------------
-- B) La página pregunta por una reserva concreta (barra de progreso).
--    Si el pago ya había llegado, la confirma en el acto.
-- ---------------------------------------------------------------------
create or replace function conciliar_reserva(p_codigo text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_reserva  reservas%rowtype;
  v_clase    clases%rowtype;
  v_pago     pagos%rowtype;
  v_cand     int;
begin
  select * into v_reserva from reservas
   where upper(btrim(codigo)) = upper(btrim(p_codigo))
     for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'no_encontrada');
  end if;

  select * into v_clase from clases where id = v_reserva.clase_id;

  -- Ya resuelta: se devuelve tal cual.
  if v_reserva.estado in ('confirmada', 'rechazada', 'expirada') then
    return jsonb_build_object(
      'ok', true, 'estado', v_reserva.estado, 'codigo', v_reserva.codigo,
      'clase', v_clase.nombre, 'fecha_hora', v_clase.fecha_hora);
  end if;

  -- Solo se busca pago si ya subió el comprobante.
  if v_reserva.estado <> 'verificando' then
    return jsonb_build_object(
      'ok', true, 'estado', v_reserva.estado, 'codigo', v_reserva.codigo,
      'clase', v_clase.nombre, 'fecha_hora', v_clase.fecha_hora);
  end if;

  select count(*) into v_cand
    from pagos p
   where not p.consumido
     and p.valor_cop = v_clase.precio_cop
     and p.fecha_pago between v_reserva.created_at - interval '15 minutes'
                          and v_reserva.created_at + interval '3 hours';

  if v_cand = 1 then
    select * into v_pago
      from pagos p
     where not p.consumido
       and p.valor_cop = v_clase.precio_cop
       and p.fecha_pago between v_reserva.created_at - interval '15 minutes'
                            and v_reserva.created_at + interval '3 hours'
       for update skip locked;

    if found then
      update reservas
         set estado = 'confirmada', pago_id = v_pago.id, updated_at = now()
       where id = v_reserva.id;
      update pagos set consumido = true where id = v_pago.id;

      return jsonb_build_object(
        'ok', true, 'estado', 'confirmada', 'codigo', v_reserva.codigo,
        'clase', v_clase.nombre, 'fecha_hora', v_clase.fecha_hora);
    end if;
  end if;

  return jsonb_build_object(
    'ok', true, 'estado', 'verificando', 'codigo', v_reserva.codigo,
    'clase', v_clase.nombre, 'fecha_hora', v_clase.fecha_hora,
    'candidatos', v_cand);
end;
$$;


-- ---------------------------------------------------------------------
-- C) Se acabaron los 5 minutos de la barra: a validación humana.
-- ---------------------------------------------------------------------
create or replace function marcar_pendiente_validacion(p_codigo text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare v_reserva reservas%rowtype;
begin
  update reservas
     set estado = 'pendiente_validacion', updated_at = now()
   where upper(btrim(codigo)) = upper(btrim(p_codigo))
     and estado = 'verificando'
   returning * into v_reserva;

  if not found then
    select * into v_reserva from reservas
     where upper(btrim(codigo)) = upper(btrim(p_codigo));
    if not found then
      return jsonb_build_object('ok', false, 'error', 'no_encontrada');
    end if;
  end if;

  return jsonb_build_object('ok', true, 'estado', v_reserva.estado,
                            'codigo', v_reserva.codigo);
end;
$$;


revoke execute on function registrar_pago_y_conciliar(text,int,timestamptz,text,text,text,numeric,text,text) from public;
revoke execute on function conciliar_reserva(text)          from public;
revoke execute on function marcar_pendiente_validacion(text) from public;

grant execute on function registrar_pago_y_conciliar(text,int,timestamptz,text,text,text,numeric,text,text) to service_role;
grant execute on function conciliar_reserva(text)           to service_role;
grant execute on function marcar_pendiente_validacion(text) to service_role;
