-- ---------------------------------------------------------------------
-- 0030 — El cierre contaba dos veces la misma plata
--
-- ESTA MIGRACIÓN YA ESTÁ APLICADA EN PRODUCCIÓN.
-- Se escribe aquí para que el repositorio diga la verdad. El arreglo lo
-- hizo otra sesión trabajando sobre este mismo proyecto y quedó vivo en
-- Supabase sin quedar en el repo, así que cualquiera que volviera a
-- pegar 0029 lo habría borrado sin enterarse. Eso ya casi pasa.
--
-- EL ERROR
-- caja_del_dia mostraba:
--   total_ingresos = efectivo + transferencias de caja + reservas sueltas
--                    confirmadas del día
--
-- Pero "reservas sueltas confirmadas" incluía también las que el cajero
-- confirma A MANO en el mostrador, cuya plata él ya registró como
-- movimiento de caja. Misma plata, dos puertas, sumada dos veces.
--
-- Pasó el 10 de agosto: MG5GRX (yira zahira, 17:18) y UU7KK7 (doris,
-- 17:22) estaban en las dos partes. El cierre iba a mostrar $1.215.000
-- cuando lo real eran $1.185.000.
--
-- EL ARREGLO
-- `reservas_cop` cuenta solo las que cruzó la página sola
-- (`pago_id is not null`). Esas viven en el banco y nunca pasan por
-- caja_movimientos, así que sumarlas es correcto.
--
-- Las confirmadas a mano NO desaparecen del reporte: salen aparte en
-- `reservas_a_mano_cop` / `reservas_a_mano_n`, sin sumarse. Si alguien
-- confirma a mano y se le olvida registrarlo en Caja, ese número deja de
-- cuadrar con los movimientos y se nota. Quitarlas en silencio habría
-- cambiado un error visible por uno invisible, que es peor.
--
-- `caja_cerrar` no se toca: solo cuadra el efectivo del cajón
-- (base + ingresos − egresos), que siempre estuvo bien. El doble conteo
-- era en lo que VE el cajero, que es justo lo que causaba la confusión.
--
-- Lo demás del cuerpo es 0029 sin cambios: el control del banco y el
-- corte de producción siguen igual.
-- ---------------------------------------------------------------------
create or replace function caja_del_dia(p_token text, p_dia date default null)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_admin  uuid;
  v_dia    date;
  v_movs   jsonb;
  v_cierre caja_cierres;
  v_ing_ef int; v_ing_tr int; v_egr_ef int; v_egr_tr int;
  v_reservas int; v_base int;
  v_res_mano int; v_res_mano_n int;
  v_desde timestamptz; v_hasta timestamptz; v_corte timestamptz;
  v_recibido int; v_ultimo timestamptz;
  v_libre_hoy int; v_libre_hoy_n int;
  v_libre int; v_libre_n int;
  v_mes int;
  v_sin_resp int; v_sin_resp_n int;
  v_libres jsonb;
  c_dias constant int := 20;
begin
  v_admin := verificar_token_admin(p_token);
  if v_admin is null then
    return jsonb_build_object('ok', false, 'error', 'NO_AUTORIZADO');
  end if;

  v_dia := coalesce(p_dia, (now() at time zone 'America/Bogota')::date);

  select
    coalesce(sum(valor_cop) filter (where sentido='ingreso' and medio='efectivo'), 0),
    coalesce(sum(valor_cop) filter (where sentido='ingreso' and medio='transferencia'), 0),
    coalesce(sum(valor_cop) filter (where sentido='egreso'  and medio='efectivo'), 0),
    coalesce(sum(valor_cop) filter (where sentido='egreso'  and medio='transferencia'), 0),
    coalesce(sum(valor_cop) filter (
      where sentido='ingreso' and medio='transferencia' and pago_id is null), 0),
    count(*) filter (
      where sentido='ingreso' and medio='transferencia' and pago_id is null)
  into v_ing_ef, v_ing_tr, v_egr_ef, v_egr_tr, v_sin_resp, v_sin_resp_n
  from caja_movimientos where dia = v_dia and not anulado;

  -- SOLO las que cruzo la pagina. Su plata esta en el banco y no pasa por
  -- caja_movimientos, asi que hay que sumarla aparte.
  select coalesce(sum(c.precio_cop), 0) into v_reservas
    from reservas r join clases c on c.id = r.clase_id
   where r.estado = 'confirmada'
     and r.tipo = 'suelta'
     and r.pago_id is not null
     and (c.fecha_hora at time zone 'America/Bogota')::date = v_dia;

  -- Las confirmadas a mano en el mostrador. NO se suman: su plata ya entro
  -- por Caja. Se muestran para poder verificar que ahi esten.
  select coalesce(sum(c.precio_cop), 0), count(*)
    into v_res_mano, v_res_mano_n
    from reservas r join clases c on c.id = r.clase_id
   where r.estado = 'confirmada'
     and r.tipo = 'suelta'
     and r.pago_id is null
     and (c.fecha_hora at time zone 'America/Bogota')::date = v_dia;

  v_desde := v_dia::timestamp        at time zone 'America/Bogota';
  v_hasta := (v_dia + 1)::timestamp  at time zone 'America/Bogota';
  -- Nada de antes del estreno entra en el inventario ni en la lista.
  v_corte := greatest(v_hasta - make_interval(days => c_dias),
                      inicio_produccion()::timestamp at time zone 'America/Bogota');

  select coalesce(sum(valor_cop), 0), max(fecha_pago),
         coalesce(sum(valor_cop) filter (where not consumido), 0),
         count(*) filter (where not consumido)
    into v_recibido, v_ultimo, v_libre_hoy, v_libre_hoy_n
    from pagos where fecha_pago >= v_desde and fecha_pago < v_hasta;

  select coalesce(sum(valor_cop), 0), count(*)
    into v_libre, v_libre_n
    from pagos where not consumido and fecha_pago >= v_corte;

  select coalesce(sum(valor_cop), 0) into v_mes
    from pagos
   where fecha_pago >= greatest(
           date_trunc('month', v_dia)::timestamp at time zone 'America/Bogota',
           inicio_produccion()::timestamp at time zone 'America/Bogota')
     and fecha_pago < v_hasta;

  select coalesce(jsonb_agg(x order by x->>'fecha_pago' desc), '[]'::jsonb)
    into v_libres
    from (
      select jsonb_build_object(
               'id', p.id,
               'valor_cop', p.valor_cop,
               'fecha_pago', p.fecha_pago,
               'cuando', to_char(p.fecha_pago at time zone 'America/Bogota',
                                 'DD/MM HH24:MI'),
               'dias', (v_dia - (p.fecha_pago at time zone 'America/Bogota')::date),
               'remitente', p.remitente,
               'referencia', p.referencia) as x
        from pagos p
       where not p.consumido and p.fecha_pago >= v_corte
       order by p.fecha_pago desc
       limit 120
    ) s;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', m.id, 'sentido', m.sentido, 'concepto', m.concepto,
           'valor_cop', m.valor_cop, 'medio', m.medio, 'nota', m.nota,
           'hora', to_char(m.created_at at time zone 'America/Bogota', 'HH24:MI'),
           'quien', t.nombre,
           'con_banco', m.pago_id is not null)
         order by m.created_at desc), '[]'::jsonb)
    into v_movs
    from caja_movimientos m
    left join admin_tokens t on t.id = m.registrado_por
   where m.dia = v_dia and not m.anulado;

  select * into v_cierre from caja_cierres where dia = v_dia;

  select coalesce(c.dejado_cop, 100000) into v_base
    from caja_cierres c where c.dia < v_dia order by c.dia desc limit 1;
  v_base := coalesce(v_cierre.base_cop, v_base, 100000);

  return jsonb_build_object(
    'ok', true,
    'dia', v_dia,
    'movimientos', v_movs,
    'base_cop', v_base,
    'ingreso_efectivo', v_ing_ef,
    'egreso_efectivo',  v_egr_ef,
    'esperado_efectivo', v_base + v_ing_ef - v_egr_ef,
    'ingreso_transferencia', v_ing_tr,
    'egreso_transferencia',  v_egr_tr,
    'reservas_cop', v_reservas,
    -- Confirmadas en el mostrador. Su plata deberia estar ya en los
    -- movimientos de Caja: esto es para poder comprobarlo, no para sumarlo.
    'reservas_a_mano_cop', v_res_mano,
    'reservas_a_mano_n',   v_res_mano_n,
    'total_ingresos', v_ing_ef + v_ing_tr + v_reservas,
    'total_egresos',  v_egr_ef + v_egr_tr,
    'contra_admingym', jsonb_build_object(
      'venta_membresias', v_ing_ef,
      'ingresos_a_banco', v_ing_tr + v_reservas,
      'retirar_dinero_de_caja', v_egr_ef,
      'dinero_en_caja', v_base + v_ing_ef - v_egr_ef
    ),
    'banco', jsonb_build_object(
      'recibido_cop', v_recibido,
      'libre_hoy_cop', v_libre_hoy,
      'libre_hoy_n', v_libre_hoy_n,
      'libre_cop', v_libre,
      'libre_n', v_libre_n,
      'atras_cop', v_libre - v_libre_hoy,
      'atras_n', v_libre_n - v_libre_hoy_n,
      'mes_cop', v_mes,
      'sin_respaldo_cop', v_sin_resp,
      'sin_respaldo_n', v_sin_resp_n,
      'ventana_dias', c_dias,
      'corte', case when v_ultimo is null then null
               else to_char(v_ultimo at time zone 'America/Bogota', 'HH24:MI') end
    ),
    'pagos_libres', v_libres,
    'cerrado', v_cierre.dia is not null,
    'cierre', case when v_cierre.dia is null then null else jsonb_build_object(
        'contado_cop', v_cierre.contado_cop,
        'esperado_cop', v_cierre.esperado_cop,
        'diferencia_cop', v_cierre.diferencia_cop,
        'dejado_cop', v_cierre.dejado_cop,
        'retirado_cop', v_cierre.retirado_cop,
        'banco_cop', v_cierre.banco_cop,
        'banco_sin_ident_cop', v_cierre.banco_sin_ident_cop,
        'nota', v_cierre.nota,
        'cerrado_at', v_cierre.cerrado_at) end
  );
end;
$$;

revoke execute on function caja_del_dia(text, date) from public, anon, authenticated;
grant  execute on function caja_del_dia(text, date) to service_role;
