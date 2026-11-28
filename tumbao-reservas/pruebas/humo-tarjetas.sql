-- ---------------------------------------------------------------------
-- Las tarjetas del dueño — prueba de humo
--
-- PARA QUÉ EXISTE
-- El 5 de septiembre de 2026 la hoja 1 del cierre decía $300.000 y la
-- hoja 2 decía $315.000 del mismo día. Damián lo dijo así: «esas son
-- las diferencias que causan las confusiones». Se arregló haciendo que
-- las dos hojas leyeran UNA sola cuenta.
--
-- Las tarjetas del resumen son una tercera pantalla que dice «ventas del
-- día». Si sumara distinto que la tirilla, el problema vuelve, y vuelve
-- peor: esta vez entre dos pantallas que nadie mira a la vez, así que la
-- diferencia podría vivir meses sin que nadie la note.
--
-- Esta prueba es lo que lo impide. No comprueba que `ventas_entre` dé un
-- número concreto —eso envejece— sino que dé EL MISMO que `caja_del_dia`
-- para todos los días que tienen datos. Si alguien cambia una regla en
-- una de las dos y no en la otra, esto falla.
--
--   psql -d <base> -f humo-tarjetas.sql
--
-- No escribe nada: monta el token dentro de una transacción y la
-- deshace al final.
-- ---------------------------------------------------------------------
\set ON_ERROR_STOP on
set client_min_messages = notice;

begin;

create temp table fallos (que text, esperado text, obtenido text) on commit drop;

create or replace function pg_temp.chk(que text, obtenido anyelement, esperado anyelement)
returns void language plpgsql as $$
begin
  if obtenido is distinct from esperado then
    insert into fallos values (que, esperado::text, coalesce(obtenido::text, '(null)'));
    raise notice '  x %  (esperaba %, llegó %)', que, esperado, coalesce(obtenido::text, 'null');
  else
    raise notice '  v %', que;
  end if;
end $$;

create temp table ctx (token text) on commit drop;
insert into ctx select crear_token_admin('tarjetas de prueba')->>'token';
create or replace function pg_temp.tk() returns text language sql stable as
  $$ select token from ctx $$;

-- Los días que de verdad tienen algo. Se calcula y no se escribe a mano
-- para que la prueba siga sirviendo el mes que viene.
create temp table dias as
  select generate_series(
           least((select min(dia) from caja_movimientos where not anulado),
                 (select min((c.fecha_hora at time zone 'America/Bogota')::date)
                    from reservas r join clases c on c.id = r.clase_id
                   where r.estado = 'confirmada' and r.tipo = 'suelta')),
           (now() at time zone 'America/Bogota')::date,
           '1 day')::date as d;

\echo ''
\echo '-- 1. La tarjeta suma lo mismo que la tirilla ------------------------'
-- La cuenta de la tirilla es la de ingresosDelDia() en docs/admin.html:
-- las cuatro casillas de `entradas` más los demás conceptos del resumen.
-- Si esas dos cuentas se separan, una pantalla miente y no hay forma de
-- saber cuál.

create temp table cotejo as
  select d.d,
         (caja_del_dia(pg_temp.tk(), d.d)) as hoja,
         (ventas_entre(d.d, d.d))          as tarjeta
    from dias d;

select pg_temp.chk('ningún día discrepa en plata',
  (select coalesce(string_agg(
            d::text || ': hoja ' || hoja_cop || ' vs tarjeta ' || tarjeta_cop, '; '),
          '(ninguno)')
     from (select d,
             (hoja->'entradas'->>'efectivo_cop')::int
           + (hoja->'entradas'->>'pagina_transferencia_cop')::int
           + (hoja->'entradas'->>'recepcion_transferencia_cop')::int
           + (hoja->'entradas'->>'a_mano_cop')::int
           + coalesce((select sum((x->>'valor_cop')::int)
                         from jsonb_array_elements(hoja->'resumen_conceptos') x
                        where x->>'sentido' = 'ingreso'
                          and x->>'concepto' <> 'clase_suelta'), 0) as hoja_cop,
             (tarjeta->>'ingreso_cop')::int as tarjeta_cop
             from cotejo) t
    where hoja_cop <> tarjeta_cop),
  '(ninguno)');

-- La cuenta de GENTE es otra pregunta que la de plata —no es cómo
-- pagaron, sino si entraron— y tiene su propia regla desde la 0059. Se
-- coteja aparte porque puede despegarse sola.
select pg_temp.chk('ningún día discrepa en cuenta de personas',
  (select coalesce(string_agg(
            d::text || ': hoja ' || coalesce(hoja_n::text, 'null')
            || ' vs tarjeta ' || coalesce(tarjeta_n::text, 'null'), '; '),
          '(ninguno)')
     from (select d,
             (hoja->'entradas'->>'personas_n')::int as hoja_n,
             (tarjeta->>'personas')::int            as tarjeta_n
             from cotejo) t
    where hoja_n is distinct from tarjeta_n),
  '(ninguno)');

\echo ''
\echo '-- 2. El mes es la suma de sus días ---------------------------------'
-- `ventas_entre` se usa con un día y con un mes. Si el rango largo no
-- diera la suma de los cortos, la tarjeta del mes y la del día se
-- contradirían entre ellas y ninguna de las dos sería comprobable.

select pg_temp.chk('el rango largo suma lo que suman los días sueltos',
  ((ventas_entre((select min(d) from dias), (select max(d) from dias)))->>'ingreso_cop')::int,
  (select sum(((ventas_entre(d, d))->>'ingreso_cop')::int) from dias)::int);

select pg_temp.chk('y lo mismo con los gastos',
  ((ventas_entre((select min(d) from dias), (select max(d) from dias)))->>'egreso_cop')::int,
  (select sum(((ventas_entre(d, d))->>'egreso_cop')::int) from dias)::int);

-- La gente NO tiene por qué sumar igual: una persona que entra el lunes
-- y el jueves son dos visitas, y eso está bien en las dos escalas. Se
-- deja dicho para que nadie lo "arregle" pensando que es un fallo.
\echo '   (la cuenta de personas son visitas, no personas distintas: no se suma aparte)'

\echo ''
\echo '-- 3. Lo que entró menos lo que salió -------------------------------'

select pg_temp.chk('queda_cop es exactamente ingreso menos egreso',
  (select count(*) from dias d
    where ((ventas_entre(d.d, d.d))->>'queda_cop')::int
       <> ((ventas_entre(d.d, d.d))->>'ingreso_cop')::int
        - ((ventas_entre(d.d, d.d))->>'egreso_cop')::int), 0::bigint);

select pg_temp.chk('el desglose de dónde viene la plata suma el total',
  (select count(*) from dias d
    where ((ventas_entre(d.d, d.d))->>'ingreso_cop')::int
       <> ((ventas_entre(d.d, d.d))->>'de_caja_cop')::int
        + ((ventas_entre(d.d, d.d))->>'de_pagina_cop')::int
        + ((ventas_entre(d.d, d.d))->>'a_mano_cop')::int), 0::bigint);

\echo ''
\echo '-- 4. El comparativo compara ventanas del mismo tamaño --------------'
-- Un mes de doce días contra uno de treinta y uno da un porcentaje que
-- no significa nada. Es el error que nadie ve porque el número sale
-- bonito.

create temp table res as
  select admin_resumen_gerencia(pg_temp.tk()) as j;

select pg_temp.chk('el mes y el mes pasado miden los mismos días',
  (select (j->'mes'->>'dias')::int from res),
  (select (j->'mes_antes'->>'dias')::int from res));

select pg_temp.chk('la semana y la semana pasada también',
  (select (j->'semana'->>'dias')::int from res),
  (select (j->'semana_antes'->>'dias')::int from res));

select pg_temp.chk('el día se compara contra un solo día',
  (select (j->'dia_semana_antes'->>'dias')::int from res), 1);

-- Y que sea el MISMO día de la semana: un martes contra un sábado no se
-- parecen en nada en una academia de baile.
select pg_temp.chk('y contra el mismo día de la semana',
  (select extract(dow from (j->'dia'->>'desde')::date)::int from res),
  (select extract(dow from (j->'dia_semana_antes'->>'desde')::date)::int from res));

select pg_temp.chk('el mes pasado acaba antes de que empiece este',
  (select (j->'mes_antes'->>'hasta')::date < (j->'mes'->>'desde')::date from res), true);

\echo ''
\echo '-- 5. El aviso de comparativo injusto dice la verdad ----------------'
-- Hoy los datos de Caja arrancan el 10 de agosto. Mientras la ventana de
-- atrás empiece antes de ese día, el comparativo del mes no es justo y
-- la pantalla tiene que decirlo. El día que haya un mes entero de
-- historia, este aviso se apaga solo.

select pg_temp.chk('el aviso del mes coincide con la realidad',
  (select (j->>'mes_antes_parcial')::boolean from res),
  (select ((j->'mes_antes'->>'desde')::date
           < (select min(dia) from caja_movimientos where not anulado)) from res));

select pg_temp.chk('y el de la semana igual',
  (select (j->>'semana_antes_parcial')::boolean from res),
  (select ((j->'semana_antes'->>'desde')::date
           < (select min(dia) from caja_movimientos where not anulado)) from res));

-- `primer_caja` es la referencia del aviso: tiene que ser el primer
-- movimiento de verdad, no el primer dato de cualquier clase. Medirlo
-- contra lo segundo daba un falso negativo —decía que agosto era
-- comparable cuando la Caja no existía antes del 10—.
select pg_temp.chk('primer_caja es el primer movimiento de caja',
  (select (j->>'primer_caja')::date from res),
  (select min(dia) from caja_movimientos where not anulado));

\echo ''
\echo '-- 6. Quien no debe verlo, no lo ve ---------------------------------'

create temp table ctx2 (token text) on commit drop;
insert into ctx2 select crear_token_admin('cajera de prueba')->>'token';
update admin_tokens set rol = 'cajero'
 where token_hash = hash_token((select token from ctx2));

select pg_temp.chk('un token de cajero no ve la plata del negocio',
  (admin_resumen_gerencia((select token from ctx2)))->>'error', 'SIN_PERMISO');

select pg_temp.chk('y un token inventado tampoco',
  (admin_resumen_gerencia('esto-no-es-un-token'))->>'error', 'NO_AUTORIZADO');

\echo ''
select case when count(*) = 0 then 'todo en verde'
            else count(*) || ' FALLOS' end as resultado from fallos;
select * from fallos;

-- Nada de esto se guarda: los dos tokens de prueba se van con la
-- transacción. Es la única forma de probar esto contra la base de verdad
-- sin dejar una llave suelta.
rollback;
