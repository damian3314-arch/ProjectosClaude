-- 0175 · El bot de ventas deja la tiquetera al final de la fila
--
-- 12 oct: en 14 días el bot abrió 75 conversaciones con objetivo «tiquetera» y ninguna compró (0 de 75; en septiembre ya
-- había sido 1 de 40). En el mismo tiempo, el objetivo de mensualidad y la reactivación trajeron 6 mensualidades. Octubre va
-- corto justo en mensualidades (15 del 1 al 12 contra 32 en septiembre) y hay cupos libres.
-- Cambio: en ventas_seleccion los candidatos con objetivo «tiquetera» pasan a prioridad 7 (después de mensualidad,
-- historial y reactivar). No se borra a nadie ni cambia ningún filtro (bajas, dueños, días sin campaña, máximo de
-- campañas, «no» reciente): solo el orden. A los clientes frecuentes la tiquetera les sigue llegando por la campaña de
-- constancia (0171). Para volver atrás: la misma sustitución al revés.

do $$
declare
  v_def text := pg_get_functiondef('public.ventas_seleccion(integer)'::regprocedure);
  v_viejo text := $v$select c.tel, c.nombre, c.objetivo, c.visitas_30d, c.hora_habitual, c.prioridad, 'reservas'::text origen$v$;
  v_nuevo text := $v$select c.tel, c.nombre, c.objetivo, c.visitas_30d, c.hora_habitual, case when c.objetivo = 'tiquetera' then 7 else c.prioridad end prioridad, 'reservas'::text origen$v$;
begin
  if position(v_nuevo in v_def) > 0 then
    raise notice '0175 ya aplicada';
    return;
  end if;
  if position(v_viejo in v_def) = 0 then
    raise exception '0175: no encontré la prioridad en ventas_seleccion';
  end if;
  execute replace(v_def, v_viejo, v_nuevo);
end $$;
