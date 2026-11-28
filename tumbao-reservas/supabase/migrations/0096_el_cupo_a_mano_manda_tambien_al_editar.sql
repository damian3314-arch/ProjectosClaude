-- 0096 · El cupo a mano manda también al EDITAR una clase que ya existe.
--
-- Damián, 23 de septiembre: cambió el cupo de la clase suelta de hoy
-- y no se le tomó.
--
-- LO QUE PASÓ
-- La 0086 dijo, con todas las letras, que `cupo_suelta_de` (la regla fija
-- por hora del 10 de septiembre) salía del `coalesce` en los dos sitios
-- donde decidía: `recalcular_cupos` y la CREACIÓN de clase en
-- `admin_guardar_semana`. Los dos se arreglaron. Pero `admin_guardar_semana`
-- decide el cupo en TRES sitios, no en dos — el tercero es la rama que
-- EDITA una clase que ya existe, que es la que se usa el 99% de las veces,
-- porque `generar_horario` ya creó la semana de antemano:
--
--   update clases
--      set cupo_total = greatest(cupo_tomado,
--                                 coalesce(cupo_suelta_de(v_momento), v_cupo_manual,
--                                          greatest(v_aforo - activos_plan, 0))),
--
-- Esa rama se quedó exactamente como estaba antes de la 0086: la regla
-- fija (07:00=5, 18:00=11, 19:00=11) sigue ganándole a lo que Damián
-- escriba a mano en esas tres horas. Por eso hoy puso `cupo_manual = 9`
-- en la clase de las 7:00 pm y el sistema le siguió vendiendo 11: la
-- regla del 10 de septiembre, que se suponía retirada, seguía decidiendo
-- ahí y solo ahí.
--
-- LO QUE SE CAMBIA
-- Exactamente el mismo cambio que la 0086 le hizo a los otros dos sitios:
--
--   coalesce(v_cupo_manual, greatest(v_aforo - activos_plan, 0))
--
-- sin `cupo_suelta_de` en la cadena. `greatest(cupo_tomado, …)` sigue
-- intacto: el cupo nunca baja de lo ya reservado.
--
-- Se parchea en sitio, como la 0086: producción trae ajustes que no
-- están en el repo y reescribir la función entera los perdería.

do $mig$
declare
  v_src   text;
  v_ancla text;
begin
  select pg_get_functiondef(p.oid) into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'admin_guardar_semana' and p.prokind = 'f';
  if v_src is null then
    raise exception '0096: no existe public.admin_guardar_semana';
  end if;

  if position('0096:' in v_src) > 0 then
    raise notice '0096: ya aplicado, no se toca';
    return;
  end if;

  v_ancla := E'           cupo_total  = greatest(cupo_tomado,\n' ||
             E'                                  coalesce(cupo_suelta_de(v_momento), v_cupo_manual,\n' ||
             E'                                           greatest(v_aforo - activos_plan, 0))),';
  if position(v_ancla in v_src) = 0 then
    raise exception '0096: no se encontro el coalesce de editar una clase existente';
  end if;

  execute replace(v_src, v_ancla,
    E'           -- 0096: lo puesto a mano manda tambien aqui; a la 0086\n' ||
    E'           -- se le escapo esta rama, la de editar una clase que ya\n' ||
    E'           -- existe (la que se usa casi siempre).\n' ||
    E'           cupo_total  = greatest(cupo_tomado,\n' ||
    E'                                  coalesce(v_cupo_manual,\n' ||
    E'                                           greatest(v_aforo - activos_plan, 0))),');
end
$mig$;

-- Corrige ya las clases de hoy que quedaron con el numero viejo de la
-- regla en vez del que Damian puso a mano.
select recalcular_cupos();
