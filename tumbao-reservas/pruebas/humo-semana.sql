-- ---------------------------------------------------------------------
-- La semana se abre sola y los festivos no — prueba de humo
--
-- EL CASO
-- Un sábado por la mañana la semana del 17 al 23 de agosto estaba vacía:
-- el lunes nadie habría podido reservar. Y el lunes 17 de agosto de 2026
-- es la Asunción, así que abrirlo habría sido peor: gente pagando por
-- una clase que no se dicta.
--
--   psql -d <base> -f humo-semana.sql
-- ---------------------------------------------------------------------
\set ON_ERROR_STOP on
set client_min_messages = notice;

create temp table fallos (que text, esperado text, obtenido text);

create or replace function chk(que text, obtenido anyelement, esperado anyelement)
returns void language plpgsql as $$
begin
  if obtenido is distinct from esperado then
    insert into fallos values (que, esperado::text, coalesce(obtenido::text, '(null)'));
    raise notice '  x %  (esperaba %, llegó %)', que, esperado, coalesce(obtenido::text, 'null');
  else
    raise notice '  v %', que;
  end if;
end $$;


\echo ''
\echo '-- 1. La Pascua, que es de donde sale media Semana Santa -----------'
-- Si esto se tuerce, se tuercen cinco festivos de golpe y nadie lo nota
-- hasta que la academia abre un Viernes Santo.

select chk('Pascua 2026', pascua(2026), date '2026-04-05');
select chk('Pascua 2027', pascua(2027), date '2027-03-28');
select chk('Pascua 2024', pascua(2024), date '2024-03-31');
select chk('Pascua 2030', pascua(2030), date '2030-04-21');


\echo ''
\echo '-- 2. Los festivos de Colombia ------------------------------------'

select sembrar_festivos(2026);

select chk('el lunes 17 de agosto es festivo',
  (select nombre from festivos where fecha = date '2026-08-17'), 'Asunción');
select chk('y es el que le importa a Tumbao esta semana',
  (select count(*)::int from festivos where fecha = date '2026-08-17'), 1);

-- La Ley Emiliana corre al lunes siguiente los que no caen en lunes.
select chk('Reyes se corre al lunes 12',
  (select count(*)::int from festivos where fecha = date '2026-01-12'), 1);
select chk('y el 6 de enero deja de serlo',
  (select count(*)::int from festivos where fecha = date '2026-01-06'), 0);

-- Los fijos NO se corren.
select chk('el 1 de mayo no se mueve',
  (select nombre from festivos where fecha = date '2026-05-01'), 'Día del Trabajo');
select chk('Viernes Santo tampoco',
  (select nombre from festivos where fecha = date '2026-04-03'), 'Viernes Santo');

select chk('son 18 festivos en el año',
  (select count(*)::int from festivos
    where fecha between date '2026-01-01' and date '2026-12-31'), 18);

-- Se puede volver a sembrar sin que pase nada.
select chk('sembrar dos veces no duplica', sembrar_festivos(2026), 0);


\echo ''
\echo '-- 3. Un cierre a mano manda igual que la ley ----------------------'
-- "Ese jueves cerramos por el evento". Ninguna ley sabe eso.

insert into festivos (fecha, nombre, origen)
values (date '2026-09-17', 'Cerrado por evento', 'manual');

delete from clases where true;
-- Semana completa son 17: cinco días entre semana por tres clases, más
-- las dos del sábado. Sin el jueves quedan 14.
select chk('el jueves cerrado a mano no se abre',
  (select generar_horario(date '2026-09-14', date '2026-09-20')), 14);
select chk('y ese día queda sin clases',
  (select count(*)::int from clases
    where (fecha_hora at time zone 'America/Bogota')::date = date '2026-09-17'), 0);
select chk('pero el resto de la semana sí',
  (select count(*)::int from clases
    where (fecha_hora at time zone 'America/Bogota')::date = date '2026-09-16'), 3);
select chk('sembrar de nuevo no le pisa el cierre a mano',
  (select origen from festivos where fecha = date '2026-09-17'), 'manual');


\echo ''
\echo '-- 4. La semana del festivo ---------------------------------------'
-- Lo que de verdad pasó: lunes 17 festivo, domingo cerrado, y de martes
-- a sábado se abre todo.

delete from clases where true;
select chk('se crean 14 clases, no las 17 de una semana entera',
  (select generar_horario(date '2026-08-17', date '2026-08-23')), 14);
select chk('el lunes festivo queda vacío',
  (select count(*)::int from clases
    where (fecha_hora at time zone 'America/Bogota')::date = date '2026-08-17'), 0);
select chk('el domingo también',
  (select count(*)::int from clases
    where (fecha_hora at time zone 'America/Bogota')::date = date '2026-08-23'), 0);
select chk('el martes abre las tres de siempre',
  (select count(*)::int from clases
    where (fecha_hora at time zone 'America/Bogota')::date = date '2026-08-18'), 3);
select chk('y el sábado las dos suyas',
  (select count(*)::int from clases
    where (fecha_hora at time zone 'America/Bogota')::date = date '2026-08-22'), 2);


\echo ''
\echo '-- 5. abrir_semana: una sola llamada, sin cuentas afuera -----------'

delete from clases where true;
create temp table r as select abrir_semana() as j;

select chk('abre la semana entrante', (select (j->>'ok')::boolean from r), true);
select chk('empieza un lunes',
  (select extract(isodow from (j->>'desde')::date)::int from r), 1);
select chk('termina un domingo',
  (select extract(isodow from (j->>'hasta')::date)::int from r), 7);
select chk('y es una semana que todavía no llegó',
  (select ((j->>'desde')::date > (now() at time zone 'America/Bogota')::date) from r), true);
select chk('deja clases en pie',
  (select (j->>'clases_en_la_semana')::int > 0 from r), true);

-- Correrla otra vez no crea nada, pero la semana sigue lista. Importa
-- porque el sábado puede correr dos veces si alguien la dispara a mano.
create temp table r2 as select abrir_semana() as j;
select chk('la segunda vez no crea nada', (select (j->>'clases_creadas')::int from r2), 0);
select chk('pero la semana sigue igual de abierta',
  (select (j->>'clases_en_la_semana')::int from r2),
  (select (j->>'clases_en_la_semana')::int from r));


\echo ''
\echo '-- 6. Ningún domingo, nunca ---------------------------------------'

select chk('no hay una sola clase en domingo',
  (select count(*)::int from clases
    where extract(isodow from fecha_hora at time zone 'America/Bogota') = 7), 0);
select chk('ni en un festivo',
  (select count(*)::int from clases c join festivos f
      on f.fecha = (c.fecha_hora at time zone 'America/Bogota')::date), 0);


\echo ''
select case when count(*) = 0 then 'todo en verde'
            else count(*) || ' FALLOS' end as resultado from fallos;
select * from fallos;
