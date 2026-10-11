-- 0151 · Cambio de horario: un solo cupo por persona (y por día)
--
-- Damián (6 oct): Alejandra Ospina Suárez (mensualidad de 7 am) aparecía dos veces en la clase de
-- las 6 pm. Eran dos reservas de tipo 'cambio' creadas con 28 segundos de diferencia (doble envío
-- del formulario): gastaba 2 de los 4 cupos de cambio y, además, sumaba dos veces el cupo que se
-- libera en la clase de 7 am.
--
-- Arreglo en tomar_cupo, dentro del mismo bloqueo de fila de la clase (sin carreras):
--   · si la persona ya tiene un cambio activo para ESTA clase, se devuelve el mismo (idempotente,
--     'repetida': true) y no se crea otro;
--   · si ya tiene un cambio activo el mismo día en otra clase, se rechaza con CAMBIO_YA_PEDIDO.
--
-- Sin cambios de esquema. Se aplica parchando la función viva (pg_get_functiondef + replace).
-- Dato corregido a mano: la reserva duplicada 56FMKN pasó a 'rechazada' (el trigger
-- reservas_cambio_libera_origen devolvió el cupo de la clase de 7 am).

do $mig$
declare
  v_def text;
  v_ancla text := E'        select count(*) into v_cambios_tomados\n          from reservas r\n         where r.clase_id = p_clase_id';
  v_nuevo text;
begin
  v_def := pg_get_functiondef('public.tomar_cupo(uuid,text,text,text,text,text,text)'::regprocedure);
  if position('CAMBIO_YA_PEDIDO' in v_def) > 0 then
    raise notice '0151 ya aplicado';
    return;
  end if;
  if position(v_ancla in v_def) = 0 then
    raise exception 'tomar_cupo: no encuentro el texto a cambiar';
  end if;
  v_nuevo := E'        -- 0151: un cambio por persona. Si ya tiene uno activo para ESTA clase (doble clic, red lenta),\n        -- se devuelve el mismo; si tiene otro el mismo dia en otra clase, no se le da un segundo cupo.\n        select * into v_reserva from reservas r\n         where r.clase_id = p_clase_id and r.tipo = ''cambio''::tipo_reserva\n           and r.estado not in (''rechazada'', ''expirada'')\n           and right(solo_digitos(r.telefono), 10) = right(v_tel, 10)\n         order by r.created_at limit 1;\n        if found then\n          return jsonb_build_object(''ok'', true, ''tipo'', ''cambio'', ''requiere_pago'', false,\n            ''reserva_id'', v_reserva.id, ''codigo'', v_reserva.codigo, ''nombre'', v_reserva.nombre,\n            ''telefono'', v_reserva.telefono, ''estado'', v_reserva.estado, ''expira_en'', v_reserva.expira_en,\n            ''clase'', v_clase.nombre, ''profesor'', v_clase.profesor, ''fecha_hora'', v_clase.fecha_hora,\n            ''lugar'', v_clase.lugar, ''precio_cop'', v_clase.precio_cop,\n            ''cupos_restantes'', greatest(v_clase.cupo_total - v_clase.cupo_tomado, 0), ''tiquetera_saldo'', null,\n            ''repetida'', true);\n        end if;\n        if exists (select 1 from reservas r join clases c on c.id = r.clase_id\n                    where r.tipo = ''cambio''::tipo_reserva and r.estado not in (''rechazada'', ''expirada'')\n                      and right(solo_digitos(r.telefono), 10) = right(v_tel, 10)\n                      and (c.fecha_hora at time zone ''America/Bogota'')::date = v_fecha) then\n          return jsonb_build_object(''ok'', false, ''error'', ''CAMBIO_YA_PEDIDO'',\n            ''mensaje'', ''Ya tienes un cambio de horario para hoy. Si necesitas otro, escríbenos por WhatsApp.'');\n        end if;\n\n';
  v_def := replace(v_def, v_ancla, v_nuevo || v_ancla);
  execute v_def;
end
$mig$;
