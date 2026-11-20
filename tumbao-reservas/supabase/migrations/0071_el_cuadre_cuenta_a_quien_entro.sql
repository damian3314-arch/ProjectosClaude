-- 0071 · El cuadre del día cuenta a quien ENTRÓ, no a quien pagó.
--
-- Lo dijo Damián después de cuadrar el 5 de septiembre con Tania:
--
--   «Si hay clases que la gente hizo el pago por la página pero no
--    asistió, pues esa gente no entró ese día, entonces esa gente no hay
--    que tenerla en cuenta. La persona pagó pero no asistió: como tal,
--    esa plata no tiene que entrar, es como si esa plata no hubiera
--    entrado. Y si ya la persona registró cuándo la va a disfrutar, pues
--    superbién, pero si no lo ha registrado, pues no importa, porque ya
--    eso ahí paré de contar.»
--
-- El sistema ya tiene las dos marcas de eso y hasta hoy solo miraba una:
--
--   `no_vino_at`     recepción la marcó como que no vino (el momento en
--                    que deja de ser gente que entró).
--   `reprogramada_a` además ya escogió el día en que la va a disfrutar.
--
-- El cuadre miraba `reprogramada_a` a secas. Quien no vino y todavía no
-- ha escogido fecha seguía contando como si hubiera entrado — el 5 de
-- septiembre eran dos personas, $30.000 que la hoja juraba haber
-- recibido en la puerta. Y al revés: hay diez reservas movidas de fecha
-- sin `no_vino_at` (se reprograman antes de la clase, sin que nadie las
-- marque), así que ninguna de las dos marcas sola alcanza. La condición
-- es la conjunción, y va igual en las cuatro consultas para que la hoja
-- 1 y la hoja 2 no puedan contar distinto.
--
-- Los cuatro sitios que se tocan:
--
--   1. `v_entra_pag_tr`  la puerta «Reservas por página» de la hoja 1.
--   2. `v_cuando_entro`  el «cuándo pagaron» de la hoja 2.
--   3. `suyas` (0059)    la cuenta de personas del día.
--   4. `suyas` (0062)    la lista que se puntea contra el extracto.
--
-- NO se toca el bloque de `v_cuadre` (0064), que es la maquinaria de la
-- plata futura: esa deja de imprimirse en el papel en este mismo lote y
-- cambiarle las reglas ahora solo movería un número que ya nadie lee.
--
-- Se parchea EN SITIO sobre la definición viva, no se reescribe la
-- función: producción trae arreglos que no están en este repo.

do $mig$
declare
  v_src  text;
  v_new  text;
  v_ancla text;
  v_rep   text;
begin
  select pg_get_functiondef(p.oid) into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'caja_del_dia';

  if v_src is null then
    raise exception '0071: no existe public.caja_del_dia';
  end if;

  if position('0071:' in v_src) > 0 then
    raise notice '0071: ya aplicado, no se toca';
    return;
  end if;

  v_new := v_src;

  -- ── 1. la puerta de la página, en la hoja 1 ───────────────────────
  v_ancla :=
    E'     and r.origen in (''web'', ''formulario'')\n' ||
    E'     and (c.fecha_hora at time zone ''America/Bogota'')::date = v_dia;';
  if position(v_ancla in v_new) = 0 then
    raise exception '0071: no se encontro la consulta de v_entra_pag_tr';
  end if;
  v_rep :=
    E'     and r.origen in (''web'', ''formulario'')\n' ||
    E'     -- 0071: quien no vino no entro por esta puerta. Las dos\n' ||
    E'     -- marcas: la de recepcion y la de haber escogido ya otra\n' ||
    E'     -- fecha. Ninguna sola alcanza.\n' ||
    E'     and r.no_vino_at is null and r.reprogramada_a is null\n' ||
    E'     and (c.fecha_hora at time zone ''America/Bogota'')::date = v_dia;';
  v_new := replace(v_new, v_ancla, v_rep);

  -- ── 2. el «cuando pagaron» de la hoja 2 ───────────────────────────
  v_ancla := E'             and r2.origen in (''web'', ''formulario'')';
  if position(v_ancla in v_new) = 0 then
    raise exception '0071: no se encontro la consulta de v_cuando_entro';
  end if;
  v_rep :=
    E'             and r2.origen in (''web'', ''formulario'')\n' ||
    E'             -- 0071: los mismos que cuenta la hoja 1.\n' ||
    E'             and r2.no_vino_at is null and r2.reprogramada_a is null';
  v_new := replace(v_new, v_ancla, v_rep);

  -- ── 3. la cuenta de personas del dia (0059) ───────────────────────
  v_ancla :=
    E'       -- La que se movio a otra fecha no entro este dia: su\n' ||
    E'       -- reprogramada ya la cuenta el dia que si vino.\n' ||
    E'       and r.reprogramada_a is null';
  if position(v_ancla in v_new) = 0 then
    raise exception '0071: no se encontro el suyas de v_personas_n';
  end if;
  v_rep :=
    E'       -- La que se movio a otra fecha no entro este dia: su\n' ||
    E'       -- reprogramada ya la cuenta el dia que si vino. 0071: y la\n' ||
    E'       -- que recepcion marco como que no vino tampoco entro,\n' ||
    E'       -- aunque todavia no haya escogido cuando la disfruta.\n' ||
    E'       and r.no_vino_at is null and r.reprogramada_a is null';
  v_new := replace(v_new, v_ancla, v_rep);

  -- ── 4. la lista que se puntea contra el extracto (0062) ───────────
  v_ancla :=
    E'    select r.id, r.nombre, r.pago_id, r.origen::text as origen\n' ||
    E'      from reservas r join clases c on c.id = r.clase_id\n' ||
    E'     where r.estado = ''confirmada'' and r.tipo = ''suelta''\n' ||
    E'       and r.reprogramada_a is null';
  if position(v_ancla in v_new) = 0 then
    raise exception '0071: no se encontro el suyas de v_concilia';
  end if;
  v_rep :=
    E'    select r.id, r.nombre, r.pago_id, r.origen::text as origen\n' ||
    E'      from reservas r join clases c on c.id = r.clase_id\n' ||
    E'     where r.estado = ''confirmada'' and r.tipo = ''suelta''\n' ||
    E'       -- 0071: palabra por palabra el de la 0059, como dice el\n' ||
    E'       -- comentario de arriba. Si divergen, una hoja dice 17 y la\n' ||
    E'       -- otra lista 21 y no hay como saber cual miente.\n' ||
    E'       and r.no_vino_at is null and r.reprogramada_a is null';
  v_new := replace(v_new, v_ancla, v_rep);

  -- La marca de idempotencia, en el encabezado de la funcion.
  v_ancla := E'AS $function$\ndeclare';
  if position(v_ancla in v_new) = 0 then
    raise exception '0071: no se encontro el encabezado de la funcion';
  end if;
  v_new := replace(v_new, v_ancla,
    E'AS $function$\n-- 0071: el cuadre cuenta a quien entro, no a quien pago.\ndeclare');

  execute v_new;
end
$mig$;
