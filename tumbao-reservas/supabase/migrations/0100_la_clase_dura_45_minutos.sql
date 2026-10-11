-- 0100 · La clase dura 45 minutos, no 60.
--
-- LO QUE PIDIÓ DAMIÁN (27 de septiembre)
-- «Ayúdame a cambiar la duración de la clase a 45 minutos, pues dice en
--  la página cuando la gente va a seleccionar el horario, que es de 60
--  minutos, y eso no es así.»
--
-- La página no inventa el número: pinta `clases.duracion_min`. Y ese 60
-- estaba escrito en tres sitios:
--
--   · el default de la columna (0001)
--   · `admin_guardar_semana`, al crear una clase desde el panel
--   · `generar_horario`, al generar semanas de corrido
--
-- Las clases que ya existían de hoy en adelante se pasaron a 45 con un
-- UPDATE directo el mismo 27 (19 clases, del 26 sep al 3 oct). Esta
-- migración cierra el grifo: sin ella, la próxima semana que se guarde
-- en el panel volvería a nacer en 60.
--
-- Se parchea EN SITIO sobre la definición viva, como la 0086: producción
-- trae arreglos que no están en este repo y reescribir las funciones
-- enteras sería perderlos. Si el ancla no aparece, se detiene en vez de
-- adivinar.

alter table clases alter column duracion_min set default 45;

do $mig$
declare
  v_src   text;
  v_new   text;
  v_ancla text;
begin
  -- ── 1. admin_guardar_semana ────────────────────────────────────────
  select pg_get_functiondef(p.oid) into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'admin_guardar_semana' and p.prokind = 'f';
  if v_src is null then
    raise exception '0100: no existe public.admin_guardar_semana';
  end if;

  if position('0100:' in v_src) > 0 then
    raise notice '0100: admin_guardar_semana ya aplicado';
  else
    v_ancla := 'v_momento, 60,';
    if position(v_ancla in v_src) = 0 then
      raise exception '0100: no se encontro la duracion en admin_guardar_semana';
    end if;
    v_new := replace(v_src, v_ancla,
      E'v_momento, 45,  -- 0100: la clase dura 45 minutos');
    execute v_new;
  end if;

  -- ── 2. generar_horario ─────────────────────────────────────────────
  select pg_get_functiondef(p.oid) into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'generar_horario' and p.prokind = 'f';
  if v_src is null then
    raise notice '0100: no existe public.generar_horario, nada que tocar';
  elsif position('0100:' in v_src) > 0 then
    raise notice '0100: generar_horario ya aplicado';
  else
    v_ancla := E'at time zone ''America/Bogota'',\n           60,';
    if position(v_ancla in v_src) = 0 then
      raise exception '0100: no se encontro la duracion en generar_horario';
    end if;
    v_new := replace(v_src, v_ancla,
      E'at time zone ''America/Bogota'',\n           45,  -- 0100: la clase dura 45 minutos');
    execute v_new;
  end if;
end
$mig$;
