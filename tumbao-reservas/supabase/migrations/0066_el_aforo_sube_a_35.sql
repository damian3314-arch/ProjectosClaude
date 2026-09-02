-- ---------------------------------------------------------------------
-- 0066 — El aforo sube de 30 a 35
--
-- POR QUÉ
-- El aforo no es el tamaño del salón: es cuánta gente se deja entrar. Y
-- de la gente con mensualidad no viene toda. Con 20 mensualidades
-- activas suelen aparecer unas 15, así que reservar 20 puestos para
-- ellas deja el salón a medias y sin nada que vender en la puerta.
--
-- Subiendo el aforo a 35 ese margen se convierte en clases sueltas. El
-- efecto es directo, porque los cupos de suelta se calculan por resta:
--
--     cupo_total = aforo − activos_plan     (salvo cupo_manual)
--
-- Un miércoles a las 6 con 27 mensualidades pasa de 3 sueltas a 8.
--
-- ES UNA SOBREVENTA DELIBERADA, NO UN SALÓN MÁS GRANDE. Si un día
-- vinieran los 35, entran 35. Quien lo pidió lo sabe y es su decisión;
-- queda escrito aquí para que nadie lo lea dentro de seis meses como si
-- fuera un error de dedo.
--
-- DÓNDE VIVÍA EL 30
-- En cuatro sitios, y los cuatro tienen que moverse a la vez o la
-- semana siguiente vuelve sola a 30:
--
--   1. el `default` de la columna `clases.aforo`
--   2. `generar_horario(p_aforo int default 30)`
--   3. `admin_guardar_semana`, que rellena con 30 la celda que llega sin
--      aforo desde el panel
--   4. el panel (docs/admin.html), fuera de esta migración
--
-- LO QUE NO SE TOCA
-- Las clases ya dictadas. Su aforo es lo que de verdad se ofreció ese
-- día y cambiarlo reescribiría el pasado: los papeles de cierre que ya
-- se imprimieron dejarían de cuadrar contra la base.
--
-- Tampoco las clases con `cupo_manual`: los sábados ya van con 35 puesto
-- a mano y el cupo manual manda sobre el aforo. Subir el aforo no las
-- altera, que es justo lo que se quiere.
-- ---------------------------------------------------------------------

do $$
declare
  v_def text;
  v_ini int;
  c_viejo constant text := 'v_aforo := coalesce((v_celda->>''aforo'')::int, 30);';
  c_nuevo constant text := 'v_aforo := coalesce((v_celda->>''aforo'')::int, 35);   -- 0066: era 30';
  v_futuras int;
  v_recalculo jsonb;
begin

  -- ── 1. el default de la columna ───────────────────────────────────
  -- Vale para cualquier clase que se cree sin decir aforo, venga de
  -- donde venga. Es la red de abajo: aunque un camino se olvide de
  -- pasar el valor, ya no nace con 30.
  alter table clases alter column aforo set default 35;

  -- ── 2. el generador de horario ────────────────────────────────────
  -- Solo cambia el valor por defecto del parámetro, empalmado sobre la
  -- definición viva: el cuerpo de esta función no se reescribe a mano.
  -- La firma no se toca (el default no forma parte de ella), así que no
  -- hay que soltar nada ni queda una ventana con dos versiones vivas.
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'generar_horario';
  if v_def is null then
    raise exception '0066: no existe generar_horario';
  end if;

  if position('p_aforo integer DEFAULT 35' in v_def) > 0 then
    raise notice '0066: generar_horario ya venía con 35';
  else
    v_ini := position('p_aforo integer DEFAULT 30' in v_def);
    if v_ini = 0 then
      raise exception '0066: no se encontró el aforo por defecto de generar_horario';
    end if;
    v_def := left(v_def, v_ini - 1) || 'p_aforo integer DEFAULT 35'
             || substr(v_def, v_ini + length('p_aforo integer DEFAULT 30'));
    execute v_def;
    raise notice '0066: generar_horario ahora nace con aforo 35';
  end if;

  -- ── 3. el relleno de admin_guardar_semana ─────────────────────────
  -- Se empalma por marcador sobre la definición VIVA: producción tiene
  -- arreglos que no están en el repo y reescribir la función entera los
  -- borraría. Si el anclaje no aparece se falla — parchear a ciegas la
  -- función que abre la semana es peor que no parchearla.
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'admin_guardar_semana';
  if v_def is null then
    raise exception '0066: no existe admin_guardar_semana';
  end if;

  if position('0066:' in v_def) > 0 then
    raise notice '0066 ya estaba puesta en admin_guardar_semana';
  else
    v_ini := position(c_viejo in v_def);
    if v_ini = 0 then
      raise exception
        '0066: no se encontró el relleno de aforo en admin_guardar_semana';
    end if;
    v_def := left(v_def, v_ini - 1) || c_nuevo
             || substr(v_def, v_ini + length(c_viejo));
    if position('0066:' in v_def) = 0 then
      raise exception '0066: el empalme no dejó la marca';
    end if;
    execute v_def;
    raise notice '0066: admin_guardar_semana parcheada';
  end if;

  -- ── 4. las clases que todavía no se han dictado ───────────────────
  -- Solo las futuras, y solo las que llevan el 30 de antes: una clase
  -- que alguien haya puesto a mano en otro número es una decisión suya
  -- y no se pisa.
  update clases
     set aforo = 35
   where fecha_hora > now()
     and aforo = 30;
  get diagnostics v_futuras = row_count;

  -- El aforo no mueve los cupos por sí solo: `cupo_total` es una columna
  -- guardada que recalcula esta función, la misma que corre al abrir la
  -- semana. Nunca baja de `cupo_tomado`, así que no puede dejar fuera a
  -- nadie que ya tenga su puesto.
  v_recalculo := recalcular_cupos();

  raise notice '0066: aforo 35 en % clases futuras; recálculo: %',
    v_futuras, v_recalculo;
end $$;

comment on column clases.aforo is
  'Cuánta gente se deja entrar a la clase, no el tamaño del salón. '
  'Los cupos de clase suelta salen por resta: aforo − activos_plan. '
  'Subió de 30 a 35 el 2026-09-02 (0066) como sobreventa deliberada '
  'contra las mensualidades que no asisten.';
