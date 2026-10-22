-- =====================================================================
-- Los cupos de clase suelta salen de cuántos afiliados hay con plan
-- activo en ese horario
--
-- REGLA DE NEGOCIO
-- La sala tiene un aforo fijo. Los afiliados con mensualidad tienen su
-- puesto asegurado en SU horario. Lo que sobra es lo que se puede
-- vender como clase suelta.
--     cupos_sueltos = aforo − afiliados_activos_en_ese_horario
-- Ejemplo dado: 25 activos a las 6pm con aforo 30 → 5 cupos sueltos.
--
-- DE DÓNDE SALE EL DATO
-- Del "Reporte Afiliados con Membresía Activa" que se descarga a diario
-- a Drive. Es un .xlsx, no un Google Sheet. Columnas:
--     Afiliado | Membresía | # Documento | Celular | Correo |
--     Dirección | Inicio Membresía | Final Membresía
--
-- La columna Membresía trae la hora dentro del texto:
--     "PLAN MENSUALIDAD 7:00AM"   "MEDIA MENSUALIDAD 6:00PM"
--
-- Sobre el archivo del 26/07/2026, 61 afiliados activos repartidos así:
--     7:00 AM → 19     6:00 PM → 26     7:00 PM → 16
-- Con aforo 30 eso da 11, 4 y 14 cupos sueltos respectivamente.
--
-- OJO CON LAS FECHAS
-- Cada membresía tiene Inicio y Final. Varias terminan el 29, 30 y 31
-- de julio. "Activo" NO es un número fijo: depende de la fecha de cada
-- clase. Por eso se guarda el rango y se recalcula por clase, en vez de
-- guardar un conteo del día.
-- =====================================================================

-- Aforo de la sala. Separado de cupo_total porque cupo_total es lo que
-- queda para clase suelta y cambia cada día con las membresías.
alter table clases add column if not exists aforo int not null default 30
  check (aforo > 0);

alter table clases add column if not exists activos_plan int not null default 0
  check (activos_plan >= 0);


-- ---------------------------------------------------------------------
-- Espejo del reporte de afiliados. Se reemplaza entero en cada importe.
-- ---------------------------------------------------------------------
create table if not exists membresias (
  id           bigserial primary key,
  afiliado     text not null,
  membresia    text not null,          -- texto original, para depurar
  hora         time not null,          -- extraída del texto
  tipo         text not null           -- 'plan' o 'media'
                 check (tipo in ('plan','media','otro')),
  documento    text,
  celular      text,
  correo       text,
  inicio       date not null,
  fin          date not null,
  importado_at timestamptz not null default now(),
  constraint rango_valido check (fin >= inicio)
);

create index if not exists membresias_hora_rango on membresias (hora, inicio, fin);


-- ---------------------------------------------------------------------
-- Generar el horario de un rango de fechas
--   Lunes a viernes: 7:00 am, 6:00 pm, 7:00 pm
--   Sábado:          8:00 am, 9:00 am
--   Cada clase dura una hora.
-- Idempotente: no duplica clases que ya existan a esa hora.
-- ---------------------------------------------------------------------
create or replace function generar_horario(
  p_desde date,
  p_hasta date,
  p_precio_cop int default 15000,
  p_aforo int default 30,
  p_profesor text default 'Por asignar',
  p_lugar text default 'Sede Tumbao'
) returns int
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_creadas int;
begin
  with horario as (
    -- dow: 1=lunes … 5=viernes, 6=sábado
    select * from (values
      (array[1,2,3,4,5], time '07:00', 'Clase 7:00 am'),
      (array[1,2,3,4,5], time '18:00', 'Clase 6:00 pm'),
      (array[1,2,3,4,5], time '19:00', 'Clase 7:00 pm'),
      (array[6],         time '08:00', 'Clase 8:00 am'),
      (array[6],         time '09:00', 'Clase 9:00 am')
    ) as h(dows, hora, nombre)
  ),
  dias as (
    select d::date as dia
    from generate_series(p_desde, p_hasta, interval '1 day') d
  ),
  nuevas as (
    insert into clases (nombre, profesor, fecha_hora, duracion_min,
                        cupo_total, precio_cop, lugar, aforo, activa)
    select h.nombre, p_profesor,
           (dias.dia + h.hora) at time zone 'America/Bogota',
           60, p_aforo, p_precio_cop, p_lugar, p_aforo, true
    from dias
    join horario h on extract(dow from dias.dia)::int = any(h.dows)
    where not exists (
      select 1 from clases c
       where c.fecha_hora = (dias.dia + h.hora) at time zone 'America/Bogota'
    )
    returning 1
  )
  select count(*)::int into v_creadas from nuevas;

  return v_creadas;
end;
$$;


-- ---------------------------------------------------------------------
-- Recalcular los cupos sueltos de todas las clases futuras
--
-- Se cuenta, para la FECHA de cada clase, cuántas membresías de esa
-- hora la cubren. No un conteo global del día.
--
-- El greatest(cupo_tomado, ...) evita violar el CHECK
-- cupo_tomado <= cupo_total si entran afiliados nuevos después de que
-- alguien ya reservó una suelta. Preferimos pasarnos un puesto antes
-- que dejar la base en un estado inválido o cancelarle a alguien que ya
-- pagó.
-- ---------------------------------------------------------------------
create or replace function recalcular_cupos()
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_afectadas int;
  v_apretadas int;
begin
  with calculo as (
    select c.id,
           c.aforo,
           c.cupo_tomado,
           (select count(*)
              from membresias m
             where m.hora = (c.fecha_hora at time zone 'America/Bogota')::time
               and (c.fecha_hora at time zone 'America/Bogota')::date
                   between m.inicio and m.fin)::int as activos
      from clases c
     where c.fecha_hora > now()
  ),
  aplicado as (
    update clases c
       set activos_plan = k.activos,
           cupo_total   = greatest(k.cupo_tomado, greatest(k.aforo - k.activos, 0))
      from calculo k
     where c.id = k.id
       and (c.activos_plan is distinct from k.activos
            or c.cupo_total is distinct from greatest(k.cupo_tomado, greatest(k.aforo - k.activos, 0)))
     returning c.id, k.aforo - k.activos as ideal, c.cupo_total as real
  )
  select count(*)::int,
         count(*) filter (where real > greatest(ideal, 0))::int
    into v_afectadas, v_apretadas
    from aplicado;

  return jsonb_build_object(
    'ok', true,
    'clases_actualizadas', v_afectadas,
    'clases_sobrevendidas_por_reservas_previas', v_apretadas);
end;
$$;


revoke execute on function generar_horario(date, date, int, int, text, text) from public, anon, authenticated;
revoke execute on function recalcular_cupos()                                from public, anon, authenticated;
grant  execute on function generar_horario(date, date, int, int, text, text) to service_role;
grant  execute on function recalcular_cupos()                                to service_role;

alter table membresias enable row level security;
