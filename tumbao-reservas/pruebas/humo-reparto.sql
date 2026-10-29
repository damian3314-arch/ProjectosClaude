-- ---------------------------------------------------------------------
-- Un depósito para varios cobros — prueba de humo
--
-- EL CASO, DEL 15 DE AGOSTO
-- Alguien consignó $30.000 a las 8 de la mañana: dos clases de $15.000.
-- No había forma de registrarlo. `caja_registrar` exigía que el
-- movimiento valiera exactamente lo mismo que el depósito, así que los
-- $30.000 se quedaron en "sin identificar" y ahí iban a quedarse.
--
--   psql -d <base> -f humo-reparto.sql
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

create temp table ctx (token text);
insert into ctx select crear_token_admin('cajera de prueba')->>'token';
create or replace function tk() returns text language sql stable as $$ select token from ctx $$;
create or replace function dia() returns jsonb language sql stable as
  $$ select caja_del_dia(tk()) $$;

update ajustes set valor = ((now() at time zone 'America/Bogota')::date - 60)::text
 where clave = 'inicio_produccion';

-- Un depósito de $30.000 de hoy, sin dueño. Y otro de $15.000 que ya se
-- llevó una reserva, para comprobar que ese NO reaparece.
insert into pagos (id, banco, valor_cop, fecha_pago, remitente, referencia, hoja_fila)
values ('66666666-0000-4000-8000-000000000001', 'Bancolombia', 30000,
        now() - interval '2 hours', 'Erika de Prueba', 'R30', 'h30'),
       ('66666666-0000-4000-8000-000000000002', 'Bancolombia', 15000,
        now() - interval '3 hours', 'Ya Tiene Dueno', 'R15', 'h15');

update pagos set consumido = true
 where id = '66666666-0000-4000-8000-000000000002';


\echo ''
\echo '-- 1. Al principio solo se ve el que está libre --------------------'

select chk('un solo depósito sin identificar',
  (dia()->'banco'->>'libre_hoy_n')::int, 1);
select chk('y son los treinta mil completos',
  (dia()->'banco'->>'libre_hoy_cop')::int, 30000);
select chk('el que se llevó una reserva no aparece',
  (select count(*)::int from jsonb_array_elements(dia()->'pagos_libres') e
    where e->>'id' = '66666666-0000-4000-8000-000000000002'), 0);


\echo ''
\echo '-- 2. Se le muerde la mitad ---------------------------------------'
-- Esto es lo que antes rebotaba: el movimiento vale menos que el
-- depósito.

select chk('registrar quince mil contra el depósito de treinta',
  (caja_registrar(tk(), 'ingreso', 'clase_suelta', 15000, 'transferencia',
                  'primera de las dos', '66666666-0000-4000-8000-000000000001')
   ->>'ok')::boolean, true);

select chk('sigue en la lista, porque le queda plata',
  (dia()->'banco'->>'libre_hoy_n')::int, 1);
select chk('pero ya solo por lo que le queda',
  (dia()->'banco'->>'libre_hoy_cop')::int, 15000);
select chk('y la lista dice cuánto le queda',
  (select (e->>'saldo_cop')::int from jsonb_array_elements(dia()->'pagos_libres') e
    where e->>'id' = '66666666-0000-4000-8000-000000000001'), 15000);


\echo ''
\echo '-- 3. No se puede sacar más de lo que hay -------------------------'

select chk('veinte mil no caben en los quince que quedan',
  caja_registrar(tk(), 'ingreso', 'clase_suelta', 20000, 'transferencia',
                 null, '66666666-0000-4000-8000-000000000001')->>'error',
  'VALOR_NO_COINCIDE');
-- Sin fijar el separador de miles: `to_char` usa el de la base, que no
-- es el mismo en el Postgres de aquí que en el de Supabase. Lo que
-- importa es que el mensaje diga las dos cifras.
select chk('y el mensaje dice cuánto queda y cuánto se pidió',
  caja_registrar(tk(), 'ingreso', 'clase_suelta', 20000, 'transferencia',
                 null, '66666666-0000-4000-8000-000000000001')->>'mensaje'
    ~ 'le quedan 15.?000 y estás registrando 20.?000', true);
select chk('lo rechazado no se cobró',
  (dia()->'banco'->>'libre_hoy_cop')::int, 15000);


\echo ''
\echo '-- 4. La segunda mitad lo cierra ----------------------------------'

select chk('la otra clase también entra',
  (caja_registrar(tk(), 'ingreso', 'clase_suelta', 15000, 'transferencia',
                  'segunda de las dos', '66666666-0000-4000-8000-000000000001')
   ->>'ok')::boolean, true);
select chk('ya no queda nada sin identificar',
  (dia()->'banco'->>'libre_hoy_cop')::int, 0);
select chk('y se cae de la lista',
  (dia()->'banco'->>'libre_hoy_n')::int, 0);
select chk('ahora sí rebota, porque está agotado',
  caja_registrar(tk(), 'ingreso', 'clase_suelta', 1000, 'transferencia',
                 null, '66666666-0000-4000-8000-000000000001')->>'error',
  'PAGO_YA_USADO');


\echo ''
\echo '-- 5. En la caja quedan las DOS líneas ----------------------------'
-- Es la razón de todo esto: registrar una sola de $30.000 cuadra la
-- plata pero en la tirilla no dice de qué fue.

select chk('dos movimientos de clase suelta',
  (select count(*)::int from caja_movimientos
    where concepto = 'clase_suelta' and not anulado), 2);
select chk('y suman los treinta mil',
  (select coalesce(sum(valor_cop),0)::int from caja_movimientos
    where concepto = 'clase_suelta' and not anulado), 30000);


\echo ''
\echo '-- 6. Anular devuelve solo ese pedazo -----------------------------'

select chk('se anula la segunda',
  (caja_anular(tk(),
    (select id from caja_movimientos where nota = 'segunda de las dos'))
   ->>'ok')::boolean, true);
select chk('el depósito vuelve a la lista',
  (dia()->'banco'->>'libre_hoy_n')::int, 1);
select chk('con los quince mil que se devolvieron, no con treinta',
  (dia()->'banco'->>'libre_hoy_cop')::int, 15000);


\echo ''
\echo '-- 7. El cruce automático no lo toca ------------------------------'
-- Apenas la caja le muerde un pedazo, el depósito sale del cruce. Si no,
-- una reserva de $30.000 se lo llevaría entero y la misma plata quedaría
-- contada dos veces.

select chk('queda marcado como no disponible para el cruce',
  (select consumido from pagos where id = '66666666-0000-4000-8000-000000000001'), true);
select chk('aunque le quede saldo',
  (select valor_cop - usado_cop from pagos
    where id = '66666666-0000-4000-8000-000000000001'), 15000);


\echo ''
select case when count(*) = 0 then 'todo en verde'
            else count(*) || ' FALLOS' end as resultado from fallos;
select * from fallos;
