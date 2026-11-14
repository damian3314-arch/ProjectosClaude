-- 0086 · El cupo vuelve a ser el real: aforo menos mensualidades.
--
-- LO QUE PIDIÓ DAMIÁN (15 de septiembre, con un «¡Ayuda!» delante)
-- «Volver a que los cupos libres se recalculen con el valor real,
--  tomando el total y restando las mensualidades, y que si requiero un
--  cambio manual lo pueda hacer.»
--
-- ── POR QUÉ ESTABA MAL ──────────────────────────────────────────────
--
-- La 0078 escribió la regla que él mismo fijó el 10 de septiembre:
-- 07:00 = 5 sueltas, 18:00 = 11, 19:00 = 11. Números FIJOS, sin mirar
-- cuánta gente con plan hay esa hora. Y esos números entraron en el
-- `coalesce` POR DELANTE de todo lo demás:
--
--   coalesce( cupo_suelta_de(hora),   ← la regla, ganaba siempre
--             cupo_manual,            ← lo puesto a mano, nunca se leía
--             aforo - activos )       ← el cálculo real, tampoco
--
-- Dos consecuencias, las dos medidas hoy contra producción:
--
-- 1. LAS 7:00 PM SE ESTABAN SOBREVENDIENDO. Hay 29 mensualidades
--    activas a esa hora. La regla ofrecía 11 sueltas encima: 29 + 11 =
--    40 personas para un salón de 35. El propio comentario de la 0078
--    ya avisaba de que el papel permitía pasarse; con 29 en vez de 26,
--    se pasa de 2 a 5.
--
-- 2. LAS 7:00 AM SE ESTABAN INFRAVENDIENDO. 35 − 23 = 12 sitios libres
--    y la regla ofrecía 5. Siete cupos vendibles que nadie podía
--    comprar, todos los días.
--
-- 3. Y EL CAMBIO A MANO NO SERVÍA PARA NADA. Damián había escrito 6, 8
--    y 6 en las 7:00 pm de esta semana. Estaban guardados en
--    `cupo_manual` y la función los ignoraba: la regla iba delante. Lo
--    que él veía en pantalla no era lo que el sistema vendía.
--
-- ── LO QUE SE CAMBIA ────────────────────────────────────────────────
--
--   coalesce( cupo_manual,            ← lo que él diga, manda
--             aforo - activos )       ← si no dice nada, la cuenta real
--
-- `cupo_suelta_de` sale de la cadena en los dos sitios donde decidía:
-- `recalcular_cupos` y la creación de clase de `admin_guardar_semana`.
--
-- LO QUE NO SE TOCA: `greatest(cupo_tomado, …)` sigue por encima de
-- todo. El cupo NUNCA baja de lo ya reservado, así que bajar el número
-- no le cancela la clase a nadie que ya pagó. El miércoles 19:00 tiene
-- 8 vendidas y el cálculo real da 6: se queda en 8 y se reporta en
-- `clases_sobrevendidas_por_reservas_previas`, que es justo para lo que
-- existe ese contador.
--
-- LA FUNCIÓN `cupo_suelta_de` Y EL AJUSTE `suelta_cupos` SE QUEDAN, pero
-- ya no deciden nada. No se borran por dos motivos: son el registro de
-- la política del 10 de septiembre, y volver a ella es devolver un
-- `coalesce` a su sitio. Que estén ahí sin mandar hay que decirlo en voz
-- alta —un ajuste que parece hacer algo y no lo hace es una trampa— y
-- por eso está escrito aquí.
--
-- Se parchea EN SITIO sobre la definición viva: producción trae arreglos
-- que no están en este repo, y reescribir estas dos funciones enteras
-- sería perderlos.

do $mig$
declare
  v_src   text;
  v_new   text;
  v_ancla text;
begin
  -- ── 1. recalcular_cupos ────────────────────────────────────────────
  select pg_get_functiondef(p.oid) into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'recalcular_cupos' and p.prokind = 'f';
  if v_src is null then
    raise exception '0086: no existe public.recalcular_cupos';
  end if;

  if position('0086:' in v_src) > 0 then
    raise notice '0086: ya aplicado, no se toca';
  else
    v_new := v_src;

    -- El que decide el cupo nuevo de cada clase.
    v_ancla := E'             coalesce(cupo_suelta_de(k.fecha_hora), k.cupo_manual,\n' ||
               E'                      greatest(k.aforo - k.activos, 0))';
    if position(v_ancla in v_new) = 0 then
      raise exception '0086: no se encontro el coalesce del objetivo';
    end if;
    v_new := replace(v_new, v_ancla,
      E'             coalesce(k.cupo_manual,\n' ||
      E'                      greatest(k.aforo - k.activos, 0))');

    -- Y el que calcula el «ideal» para saber si quedo apretada. Tiene
    -- que ser la MISMA cuenta que el de arriba: si se cambiara solo uno,
    -- el contador de sobrevendidas mediria contra una regla que ya no
    -- se usa y marcaria clases sanas.
    v_ancla := E'               coalesce(cupo_suelta_de(o.fecha_hora), o.cupo_manual,\n' ||
               E'                        greatest(o.aforo - o.activos, 0)) as ideal,';
    if position(v_ancla in v_new) = 0 then
      raise exception '0086: no se encontro el coalesce del ideal';
    end if;
    v_new := replace(v_new, v_ancla,
      E'               coalesce(o.cupo_manual,\n' ||
      E'                        greatest(o.aforo - o.activos, 0)) as ideal,');

    v_new := replace(v_new,
      E'-- 0076: el cupo de suelta puede venir de una regla por hora.',
      E'-- 0086: el cupo sale del aforo menos las mensualidades, y lo puesto\n' ||
      E'-- a mano manda sobre eso. La regla por hora de la 0078 ya no decide.');

    execute v_new;
  end if;

  -- ── 2. admin_guardar_semana, al crear una clase ────────────────────
  select pg_get_functiondef(p.oid) into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'admin_guardar_semana' and p.prokind = 'f';
  if v_src is null then
    raise exception '0086: no existe public.admin_guardar_semana';
  end if;

  if position('0086:' in v_src) > 0 then
    raise notice '0086: admin_guardar_semana ya aplicado, no se toca';
    return;
  end if;

  v_ancla := E'          -- 0076: la regla del 15 de septiembre, si aplica.\n' ||
             E'          coalesce(cupo_suelta_de(v_momento), v_cupo_manual, v_aforo),';
  if position(v_ancla in v_src) = 0 then
    raise exception '0086: no se encontro el coalesce de la clase nueva';
  end if;

  -- Al crear, el aforo entero es el valor de arranque y dura segundos:
  -- `recalcular_cupos` corre detrás y le resta las mensualidades. Lo que
  -- importa aquí es que `v_cupo_manual` vuelva a ir por delante.
  execute replace(v_src, v_ancla,
    E'          -- 0086: lo puesto a mano manda; si no hay nada, el aforo.\n' ||
    E'          -- recalcular_cupos corrige en el acto restando las mensualidades.\n' ||
    E'          coalesce(v_cupo_manual, v_aforo),');
end
$mig$;

-- Y se aplica ya, sin esperar al barrido de la noche: mientras tanto la
-- pagina esta ofreciendo 11 sueltas en una hora que solo tiene 6.
select recalcular_cupos();
