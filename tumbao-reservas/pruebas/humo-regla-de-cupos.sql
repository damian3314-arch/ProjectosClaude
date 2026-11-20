-- ---------------------------------------------------------------------
-- La regla de cupos de Tumbao — prueba de humo
--
-- La regla la fijó Damián por escrito el 10 de septiembre de 2026 y vive
-- en la migración 0078. Esta prueba existe porque una política escrita
-- solo en un comentario se despega de la realidad sin que nadie se
-- entere: los cupos viven en `ajustes`, que se cambian con un UPDATE de
-- una línea desde cualquier parte.
--
--   Aforo máximo real: 35 por clase.
--
--   6:00 pm y 7:00 pm    máx. 20 a 26 mensualidades · 11 sueltas
--   7:00 am              20 a 26 mensualidades · 5 sueltas
--
-- Lo que aquí se comprueba es el techo de lo VENDIDO, que es lo único
-- que el sistema puede garantizar. Cuántas personas entran de verdad al
-- salón no lo mide nadie: las mensualidades no generan reserva. Por eso
-- la propia regla habla de «sobreventa controlada».
--
--   psql -d <base> -f humo-regla-de-cupos.sql
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

-- Un lunes cualquiera después del corte, para preguntarle a la regla.
create or replace function un_dia_habil(p_hora text) returns timestamptz
language sql stable as $$
  select ((select valor::date from ajustes where clave = 'suelta_cupos_desde')
          + p_hora::time) at time zone 'America/Bogota';
$$;

\echo ''
\echo '-- 1. Los cupos de clase suelta -------------------------------------'
-- Es lo que la página de reservas puede vender por sesión.

select chk('7:00 am vende 5 clases sueltas',  cupo_suelta_de(un_dia_habil('07:00')), 5);
select chk('6:00 pm vende 11 clases sueltas', cupo_suelta_de(un_dia_habil('18:00')), 11);
select chk('7:00 pm vende 11 clases sueltas', cupo_suelta_de(un_dia_habil('19:00')), 11);

\echo ''
\echo '-- 2. El sábado no entra en la regla --------------------------------'
-- No tiene mensualidad: el salón entero es de clase suelta y se maneja
-- con el cupo manual de esas clases, no con esta regla.

select chk('el sábado 8:00 am no lo toca la regla',
  cupo_suelta_de(un_dia_habil('08:00')), null::int);
select chk('ni el sábado 9:00 am',
  cupo_suelta_de(un_dia_habil('09:00')), null::int);

\echo ''
\echo '-- 3. Antes del corte manda lo de siempre ---------------------------'
-- La regla entra el día que Damián dijo, ni antes ni después. Un día
-- anterior tiene que devolver null, que quiere decir «como siempre».

select chk('el día antes del corte todavía no aplica',
  cupo_suelta_de(((select valor::date from ajustes where clave = 'suelta_cupos_desde') - 1
                  + time '19:00') at time zone 'America/Bogota'), null::int);

\echo ''
\echo '-- 4. El techo de mensualidades -------------------------------------'
-- «Máximo 20 a 26 mensualidades activas por horario». Ninguna hora puede
-- tener el tope por encima de 26: eso sería vender más de lo que el
-- dueño autorizó, y es el error que nadie notaría hasta que el salón no
-- dé abasto.

select chk('ninguna hora pasa de 26 mensualidades',
  (select coalesce(string_agg(h->>'etiqueta' || '=' || (h->>'tope'), ', '), '(ninguna)')
     from jsonb_array_elements(mensualidad_cupos()->'horas') h
    where (h->>'tope')::int > 26),
  '(ninguna)');

-- Las 7:00 am son la única hora con la venta abierta, y va en el tope de
-- la banda. Las otras dos están en cero por la orden del 8 de
-- septiembre: «hasta nueva orden suspendidas las mensualidades de 6pm y
-- 7pm, quedan en lista de espera».
select chk('las 7:00 am venden mensualidad hasta 26',
  (select (h->>'tope')::int from jsonb_array_elements(mensualidad_cupos()->'horas') h
    where h->>'hora' = '07:00'), 26);
select chk('las 6:00 pm siguen con la venta cerrada',
  (select (h->>'tope')::int from jsonb_array_elements(mensualidad_cupos()->'horas') h
    where h->>'hora' = '18:00'), 0);
select chk('las 7:00 pm siguen con la venta cerrada',
  (select (h->>'tope')::int from jsonb_array_elements(mensualidad_cupos()->'horas') h
    where h->>'hora' = '19:00'), 0);

\echo ''
\echo '-- 5. La regla llega de verdad a la página de reservas ---------------'
-- Lo que la página vende NO es `cupo_total` a secas: `clases_para`
-- devuelve `coalesce(cupo_sueltas, cupo_total)`. `cupo_sueltas` es la
-- tapa por tipo que puso la 0058 para partir el sábado en 20 sueltas y
-- 15 afiliadas. Si alguien la pusiera en un día de semana, taparía la
-- regla sin que nada fallara: la tabla diría 11 y la página vendería
-- otra cosa. Este es el chequeo que lo impide.

select chk('la regla ya está vigente, no en el futuro',
  (select valor::date <= (now() at time zone 'America/Bogota')::date
     from ajustes where clave = 'suelta_cupos_desde'), true);

select chk('ninguna clase futura tiene una tapa por tipo que contradiga la regla',
  (select coalesce(string_agg(
            to_char(c.fecha_hora at time zone 'America/Bogota','DD/MM HH24:MI')
            || ' vende ' || c.cupo_sueltas || ' y la regla dice '
            || cupo_suelta_de(c.fecha_hora), '; '), '(ninguna)')
     from clases c
    where c.fecha_hora > now()
      and c.cupo_sueltas is not null
      and cupo_suelta_de(c.fecha_hora) is not null
      and c.cupo_sueltas <> cupo_suelta_de(c.fecha_hora)),
  '(ninguna)');

select chk('lo que vende la página es exactamente lo que dice la regla',
  (select coalesce(string_agg(
            to_char(c.fecha_hora at time zone 'America/Bogota','DD/MM HH24:MI')
            || ' vende ' || coalesce(c.cupo_sueltas, c.cupo_total)
            || ' y la regla dice ' || cupo_suelta_de(c.fecha_hora), '; '), '(cuadran todas)')
     from clases c
    where c.fecha_hora > now()
      and cupo_suelta_de(c.fecha_hora) is not null
      -- Una clase con más reservas que el cupo nuevo no es un fallo: el
      -- cupo nunca baja de lo ya vendido, y esa es la regla que manda.
      and c.cupo_tomado <= cupo_suelta_de(c.fecha_hora)
      and coalesce(c.cupo_sueltas, c.cupo_total) <> cupo_suelta_de(c.fecha_hora)),
  '(cuadran todas)');

\echo ''
\echo '-- 6. El aforo, y lo que la regla admite pasarse ---------------------'
-- El aforo de todas las clases futuras es 35. Y se deja dicho, sin que
-- sea un fallo, cuánto podría pasarse la sala si TODAS las afiliadas
-- asistieran: es la sobreventa que la regla acepta a propósito.

select chk('todas las clases futuras tienen aforo 35',
  (select coalesce(string_agg(distinct aforo::text, ', '), '(no hay clases futuras)')
     from clases where fecha_hora > now()), '35');

do $$
declare r record;
begin
  for r in
    select h->>'etiqueta' as hora,
           (h->>'ocupadas')::int as vendidas,
           coalesce(cupo_suelta_de(un_dia_habil(h->>'hora')), 0) as sueltas
      from jsonb_array_elements(mensualidad_cupos()->'horas') h
  loop
    raise notice '  · % → % mensualidades + % sueltas = % si todas entraran%',
      r.hora, r.vendidas, r.sueltas, r.vendidas + r.sueltas,
      case when r.vendidas + r.sueltas > 35
           then ' (SOBREVENTA de ' || (r.vendidas + r.sueltas - 35) || ')' else '' end;
  end loop;
end $$;

\echo ''
select case when count(*) = 0 then 'todo en verde'
            else count(*) || ' FALLOS' end as resultado from fallos;
select * from fallos;
