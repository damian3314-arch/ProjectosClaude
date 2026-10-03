-- =====================================================================
-- PEGAR EN SUPABASE  ·  La semana se abre sola, y los festivos no
--
-- QUÉ ARREGLA
-- La semana del 17 al 23 de agosto estaba VACÍA un sábado por la
-- mañana: el lunes nadie habría podido reservar. Nadie llamaba a
-- generar_horario(), y aunque alguien la llamara, aplica siempre el
-- mismo molde: el lunes 17 es la Asunción y lo habría abierto igual.
--
-- QUÉ TRAE
--   · una tabla de festivos que generar_horario() respeta
--   · los festivos de Colombia se calculan solos (Pascua + Ley Emiliani)
--   · abrir_semana(): abre la semana entrante de una sola llamada
--
-- Los domingos ya quedaban afuera solos: el molde solo tiene lunes a
-- viernes y sábado.
--
-- QUÉ NO TOCA
--   · ninguna clase que ya exista
--   · ninguna reserva, ningún pago, ningún cierre
--
-- Se puede pegar dos veces sin problema.
--
-- DESPUÉS DE PEGAR, avísame: hay que correr una vez el workflow
-- "Tumbao · Abrir la semana" para abrir la del 17, que ya va tarde. De
-- ahí en adelante corre solo cada sábado a las 7 am.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0040 — La semana se abre sola, y los festivos no
--
-- LO QUE PASABA
-- Nadie abría la semana. La del 17 al 23 de agosto estaba vacía un
-- sábado por la mañana: el lunes nadie habría podido reservar. Existía
-- `generar_horario()` desde el primer día, pero no la llamaba nadie —
-- el mismo hueco que tuvo `liberar_cupos_expirados()`.
--
-- Y aunque alguien la llamara, aplica siempre el mismo molde. Lo dice el
-- comentario de la 0011: "si una semana hay festivo, no hay por dónde".
--
-- El lunes 17 de agosto de 2026 es la Asunción. Abrirlo habría dejado a
-- gente pagando por una clase que no se dicta.
--
-- LO QUE HACE
--   · una tabla de festivos, que `generar_horario` respeta
--   · los festivos de Colombia se calculan solos, sin lista que envejezca
--   · `abrir_semana()`: abre la semana entrante de una sola llamada
--
-- LOS DOMINGOS YA ESTABAN AFUERA: el molde solo tiene lunes a viernes y
-- sábado. No hacía falta tocar nada para eso.
--
-- POR QUÉ SE CALCULAN Y NO SE ESCRIBEN A MANO
-- Una lista escrita a mano sirve un año y después miente en silencio, y
-- la forma de enterarse es que la academia abrió un festivo. Los
-- festivos de Colombia son una regla, no una lista: unos son fijos,
-- otros dependen de la Pascua, y la Ley Emiliani corre casi todos al
-- lunes siguiente. Eso se calcula.
--
-- La tabla igual queda, porque además sirve para lo que ninguna ley
-- sabe: "ese jueves cerramos por el evento".
-- ---------------------------------------------------------------------

create table if not exists festivos (
  fecha   date primary key,
  nombre  text not null,
  origen  text not null default 'ley'
          check (origen in ('ley', 'manual')),
  creado_at timestamptz not null default now()
);

comment on table festivos is
  'Días en que no se abren clases. origen=ley los calcula sembrar_festivos(); '
  'origen=manual son cierres que decide Tumbao y nunca se pisan.';


-- ---------------------------------------------------------------------
-- Domingo de Pascua — algoritmo de Gauss/Meeus
--
-- De aquí salen Jueves y Viernes Santo, la Ascensión, el Corpus Christi
-- y el Sagrado Corazón. Sin esto no hay forma de saber los festivos de
-- un año sin buscarlos.
-- ---------------------------------------------------------------------
create or replace function pascua(p_anio int)
returns date
language plpgsql
immutable
as $$
declare
  a int; b int; c int; d int; e int; f int; g int;
  h int; i int; k int; l int; m int; mes int; dia int;
begin
  a := p_anio % 19;
  b := p_anio / 100;
  c := p_anio % 100;
  d := b / 4;
  e := b % 4;
  f := (b + 8) / 25;
  g := (b - f + 1) / 3;
  h := (19 * a + b - d - g + 15) % 30;
  i := c / 4;
  k := c % 4;
  l := (32 + 2 * e + 2 * i - h - k) % 7;
  m := (a + 11 * h + 22 * l) / 451;
  mes := (h + l - 7 * m + 114) / 31;
  dia := ((h + l - 7 * m + 114) % 31) + 1;
  return make_date(p_anio, mes, dia);
end;
$$;


-- ---------------------------------------------------------------------
-- Los festivos de un año
--
-- Se puede correr las veces que se quiera: no pisa lo que ya está, y
-- nunca toca los que puso una persona a mano.
-- ---------------------------------------------------------------------
create or replace function sembrar_festivos(p_anio int)
returns int
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_p    date := pascua(p_anio);
  v_n    int;
  -- Ley Emiliani: si no cae lunes, se corre al lunes siguiente.
  v_lunes constant text := '';
begin
  with lista(fecha, nombre, corre) as (values
    -- Los que no se mueven nunca.
    (make_date(p_anio,  1,  1), 'Año Nuevo',                   false),
    (make_date(p_anio,  5,  1), 'Día del Trabajo',             false),
    (make_date(p_anio,  7, 20), 'Independencia',               false),
    (make_date(p_anio,  8,  7), 'Batalla de Boyacá',           false),
    (make_date(p_anio, 12,  8), 'Inmaculada Concepción',       false),
    (make_date(p_anio, 12, 25), 'Navidad',                     false),
    -- Semana Santa: tampoco se mueven.
    (v_p - 3,                   'Jueves Santo',                false),
    (v_p - 2,                   'Viernes Santo',               false),
    -- Los que corre la Ley Emiliani al lunes siguiente.
    (make_date(p_anio,  1,  6), 'Reyes Magos',                 true),
    (make_date(p_anio,  3, 19), 'San José',                    true),
    (make_date(p_anio,  6, 29), 'San Pedro y San Pablo',       true),
    (make_date(p_anio,  8, 15), 'Asunción',                    true),
    (make_date(p_anio, 10, 12), 'Día de la Raza',              true),
    (make_date(p_anio, 11,  1), 'Todos los Santos',            true),
    (make_date(p_anio, 11, 11), 'Independencia de Cartagena',  true),
    (v_p + 39,                  'Ascensión',                   true),
    (v_p + 60,                  'Corpus Christi',              true),
    (v_p + 68,                  'Sagrado Corazón',             true)
  ),
  corridos as (
    select case when corre
                then fecha + ((8 - extract(isodow from fecha)::int) % 7)
                else fecha end as fecha,
           nombre
      from lista
  ),
  puestos as (
    insert into festivos (fecha, nombre, origen)
    select fecha, nombre, 'ley' from corridos
    on conflict (fecha) do nothing
    returning 1
  )
  select count(*)::int into v_n from puestos;

  return v_n;
end;
$$;


-- ---------------------------------------------------------------------
-- generar_horario ahora salta los festivos
--
-- Se parchea el texto que de verdad está en la base en vez de
-- reescribir la función. Ver `aplicar/LEEME-ANTES-DE-PEGAR.md`.
-- ---------------------------------------------------------------------
do $mig$
declare
  v_def   text;
  v_veces int;
  v_viejo constant text :=
    E'    from dias\n' ||
    E'    join horario h on extract(dow from dias.dia)::int = any(h.dows)\n' ||
    E'    where not exists (';
  v_nuevo constant text :=
    E'    from dias\n' ||
    E'    join horario h on extract(dow from dias.dia)::int = any(h.dows)\n' ||
    E'    -- Un festivo no se abre. Los domingos ya quedaban afuera solos:\n' ||
    E'    -- el molde de arriba solo tiene lunes a viernes y sábado.\n' ||
    E'    where not exists (select 1 from festivos fe where fe.fecha = dias.dia)\n' ||
    E'      and not exists (';
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'generar_horario';

  if v_def is null then
    raise exception '0040: no existe generar_horario';
  end if;

  if position('festivos' in v_def) > 0 then
    raise notice '0040: generar_horario ya respeta los festivos, se deja como está';
  else
    v_veces := (length(v_def) - length(replace(v_def, v_viejo, ''))) / length(v_viejo);
    if v_veces <> 1 then
      raise exception '0040: en generar_horario el trozo aparece % veces, esperaba 1. '
                      'Alguien la cambió; hay que mirarla a mano antes de parchear.', v_veces;
    end if;
    execute replace(v_def, v_viejo, v_nuevo);
    raise notice '0040: generar_horario parcheada';
  end if;
end $mig$;


-- ---------------------------------------------------------------------
-- abrir_semana — lo que llama n8n el sábado
--
-- Una sola llamada, sin cuentas de fechas en el workflow: si la aritmética
-- de "cuál es el lunes que viene" vive en n8n, el día que alguien la
-- corra a mano un martes abre la semana equivocada.
--
-- Correrla dos veces no hace daño: `generar_horario` no crea una clase
-- que ya exista.
-- ---------------------------------------------------------------------
create or replace function abrir_semana()
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_hoy     date := (now() at time zone 'America/Bogota')::date;
  v_lunes   date;
  v_domingo date;
  v_creadas int;
  v_fest    jsonb;
begin
  -- El lunes que VIENE. Si hoy es lunes, el de la otra semana: esta ya
  -- está abierta y lo que falta es la siguiente.
  v_lunes := v_hoy + ((8 - extract(isodow from v_hoy)::int) % 7);
  if v_lunes = v_hoy then
    v_lunes := v_hoy + 7;
  end if;
  v_domingo := v_lunes + 6;

  -- Por si la semana cruza de año.
  perform sembrar_festivos(extract(year from v_lunes)::int);
  perform sembrar_festivos(extract(year from v_domingo)::int);

  v_creadas := generar_horario(v_lunes, v_domingo);

  select coalesce(jsonb_agg(jsonb_build_object(
           'fecha', f.fecha, 'nombre', f.nombre) order by f.fecha), '[]'::jsonb)
    into v_fest
    from festivos f
   where f.fecha between v_lunes and v_domingo;

  return jsonb_build_object(
    'ok', true,
    'desde', v_lunes,
    'hasta', v_domingo,
    'clases_creadas', v_creadas,
    'festivos', v_fest,
    -- Cuántas clases quedaron en pie esa semana, hayan sido creadas
    -- ahora o antes. Es lo que hay que mirar para saber si la semana
    -- está lista, no cuántas se crearon.
    'clases_en_la_semana', (
      select count(*)::int from clases c
       where (c.fecha_hora at time zone 'America/Bogota')::date
             between v_lunes and v_domingo));
end;
$$;

revoke execute on function pascua(int)            from public, anon, authenticated;
revoke execute on function sembrar_festivos(int)  from public, anon, authenticated;
revoke execute on function abrir_semana()         from public, anon, authenticated;
grant  execute on function pascua(int)            to service_role;
grant  execute on function sembrar_festivos(int)  to service_role;
grant  execute on function abrir_semana()         to service_role;


-- Se siembran ya los de este año y el que viene, para que el festivo del
-- lunes 17 valga desde el momento en que se pegue esto.
select sembrar_festivos(extract(year from now() at time zone 'America/Bogota')::int);
select sembrar_festivos(extract(year from now() at time zone 'America/Bogota')::int + 1);
