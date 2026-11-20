-- ---------------------------------------------------------------------
-- 0036 — Un correo, un pago
--
-- EL AGUJERO
-- Dos personas que transfieran el MISMO valor en el MISMO minuto se
-- registran como un solo depósito. El segundo se pierde en silencio: no
-- falla nada, no avisa nadie, simplemente no existe.
--
-- La culpa es del índice que impide procesar dos veces el mismo correo:
--
--   pagos_unicos (banco, valor_cop, fecha_pago, coalesce(referencia,''))
--
-- Parece razonable hasta que se mira qué hay en `referencia`: la llave
-- Bre-B de la cuenta de Tumbao, **la misma en los 150 pagos** que hay
-- registrados. Y `fecha_pago` viene del correo con precisión de minuto.
-- Así que la clave real es (valor, minuto), y a las 6 de la tarde, con
-- varios de $15.000 seguidos, chocar es cuestión de tiempo.
--
-- LO QUE HACE
-- Se dedupea por el id del correo de Gmail, que ya se venía guardando en
-- `hoja_fila` sin usarse para esto. Es lo único de verdad único: un
-- correo es un aviso del banco, y un aviso del banco es un pago.
--
-- Comprobado antes de tocar nada: los 150 pagos tienen `hoja_fila`, los
-- 150 son distintos. El índice nuevo entra sin pelear.
--
-- Y SI ALGÚN DÍA LLEGA UNO SIN ID DE CORREO
-- El índice es parcial, así que no lo cubre. Para ese caso se deja la
-- comprobación vieja escrita a mano antes de insertar. No es tan firme
-- como un índice —dos llamadas a la vez podrían colarse— pero hoy no
-- existe ese caso: la única cosa que llama a esta función es el workflow
-- de ingesta, y siempre manda el id.
-- ---------------------------------------------------------------------

create unique index if not exists pagos_por_correo
  on pagos (hoja_fila) where hoja_fila is not null;

comment on index pagos_por_correo is
  'Un aviso del banco = un pago. Reemplaza a pagos_unicos, que juntaba dos pagos iguales del mismo minuto.';

drop index if exists pagos_unicos;


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

  -- Sin id de correo no hay índice que proteja: se mira a mano. Hoy no
  -- pasa nunca —la ingesta siempre lo manda— pero si alguien llama a
  -- esto desde otro sitio, mejor que no duplique.
  if p_hoja_fila is null then
    select * into v_pago from pagos
     where banco = p_banco and valor_cop = p_valor_cop
       and fecha_pago = p_fecha_pago
       and coalesce(referencia, '') = coalesce(p_referencia, '');
    if found then
      return jsonb_build_object('ok', true, 'duplicado', true,
        'pago_id', v_pago.id, 'accion', 'ninguna');
    end if;
  end if;

  -- El conflicto se declara explícito: es el índice pagos_por_correo,
  -- que es lo que hace que reprocesar el mismo correo no registre el
  -- pago dos veces. `on conflict do nothing` a secas no lo garantiza
  -- igual.
  insert into pagos (banco, valor_cop, fecha_pago, referencia,
                     remitente, ultimos_4, raw_email, hoja_fila)
  values (p_banco, p_valor_cop, p_fecha_pago, p_referencia,
          p_remitente, p_ultimos_4, p_raw_email, p_hoja_fila)
  on conflict (hoja_fila) where hoja_fila is not null
  do nothing
  returning * into v_pago;

  if not found then
    -- Ya estaba: es el mismo correo, no un pago nuevo.
    select * into v_pago from pagos where hoja_fila = p_hoja_fila;
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

revoke execute on function registrar_pago_y_conciliar(text, int, timestamptz, text, text, text, numeric, text, text)
  from public, anon, authenticated;
grant  execute on function registrar_pago_y_conciliar(text, int, timestamptz, text, text, text, numeric, text, text)
  to service_role;
