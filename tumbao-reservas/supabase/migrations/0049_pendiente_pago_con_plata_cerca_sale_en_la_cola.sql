-- ---------------------------------------------------------------------
-- 0049 — Si nunca se registró el aviso pero llegó plata real, que
-- salga en la cola de pendientes, no solo en "sin dueño"
--
-- EL PROBLEMA
-- Ludys Herazo reutilizó por error la referencia de un comprobante de
-- una clase suya de dos semanas atrás. registrar_aviso_pago la rechazó
-- correctamente (0036: una referencia no sirve para dos reservas), así
-- que su reserva se quedó en pendiente_pago — nunca llegó a
-- verificando. Su plata real ($15.000, de verdad transferida) sí entró
-- y quedó en pagos sin consumir.
--
-- admin_pendientes() solo mira estado in ('pendiente_validacion',
-- 'verificando'), así que esa reserva es invisible ahí. Lo único que se
-- ve es su plata en "sin dueño" —a propósito sin botones, es una alerta
-- no un mostrador (ver comentario en admin.html)— sin nombre ni forma
-- de cerrarla desde el panel. Quien atiende ve "$15.000 · 26/08 15:03"
-- y no tiene qué hacer con eso.
--
-- LO QUE HACE
-- Sin tocar el criterio de "pendiente_validacion"/"verificando", suma
-- un tercer caso: una reserva en pendiente_pago SÍ sale en la cola —con
-- sus botones de siempre, "Confirmar igual" incluido— cuando hay una
-- plata real sin consumir en una ventana de tiempo razonable alrededor
-- de cuándo se hizo la reserva. Reutiliza la misma ventana (-2h/+3h) y
-- el mismo emparejamiento por "Es este" que ya existe para pagos
-- sueltos: no es un mecanismo nuevo, es dejar que el que ya existe
-- también mire este caso.
--
-- Se agrega 'sin_aviso' a la respuesta para que el panel pueda decir
-- "nunca dijo que pagó" en vez de "esperando banco" — son dos cosas
-- distintas y conviene que se lean distinto.
--
-- admin_confirmar YA acepta pendiente_pago desde 0011 (y sigue
-- aceptándolo en 0034): el botón "Confirmar igual" no necesita cambios,
-- solo hacía falta que la tarjeta llegara a pintarse.
--
-- Se parchea sobre pg_get_functiondef en vez de reescribir la función:
-- es larga, y reescribir de memoria ya salió mal en este proyecto.
-- ---------------------------------------------------------------------
do $$
declare
  v_def text;
  v_a   text;
  v_b   text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'admin_pendientes';
  if v_def is null then
    raise exception 'no existe admin_pendientes';
  end if;
  if position('sin_aviso' in v_def) > 0 then
    raise notice 'ya estaba aplicada';
    return;
  end if;

  -- 1. Marcar en la respuesta si nunca hubo aviso de pago.
  v_a := '''estado'',      r.estado,';
  v_b := v_a || E'\n' ||
    '      -- true cuando nunca se registro el aviso de pago: esta' || E'\n' ||
    '      -- tarjeta salio por una plata sin dueno cerca, no porque' || E'\n' ||
    '      -- la persona dijera que ya pago. El panel lo lee distinto.' || E'\n' ||
    '      ''sin_aviso'',   r.estado = ''pendiente_pago'',';
  if (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a) <> 1 then
    raise exception 'no se encontro estado en la respuesta exactamente una vez';
  end if;
  v_def := replace(v_def, v_a, v_b);

  -- 2. El filtro: ahora tambien entra pendiente_pago, pero SOLO si hay
  -- una plata real sin consumir cerca de cuando se hizo la reserva. Sin
  -- ese requisito, cualquiera que todavia no haya llegado a pagar
  -- inundaria la cola.
  v_a := '   where r.estado in (''pendiente_validacion'', ''verificando'')' || E'\n' ||
    '     -- Solo el líder del grupo. Las hermanas se resuelven con él.' || E'\n' ||
    '     and (r.grupo_id is null or r.grupo_id = r.id)';
  v_b := '   where (' || E'\n' ||
    '       r.estado in (''pendiente_validacion'', ''verificando'')' || E'\n' ||
    '       or (' || E'\n' ||
    '         r.estado = ''pendiente_pago''' || E'\n' ||
    '         and exists (' || E'\n' ||
    '           select 1 from pagos p' || E'\n' ||
    '            where not p.consumido' || E'\n' ||
    '              and p.fecha_pago >= v_desde' || E'\n' ||
    '              and p.fecha_pago between r.created_at - interval ''2 hours''' || E'\n' ||
    '                                  and r.created_at + interval ''3 hours''' || E'\n' ||
    '         )' || E'\n' ||
    '       )' || E'\n' ||
    '     )' || E'\n' ||
    '     -- Solo el líder del grupo. Las hermanas se resuelven con él.' || E'\n' ||
    '     and (r.grupo_id is null or r.grupo_id = r.id)';
  if (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a) <> 1 then
    raise exception 'no se encontro el where de pendiente_validacion exactamente una vez';
  end if;
  v_def := replace(v_def, v_a, v_b);

  execute v_def;
end $$;
