-- ---------------------------------------------------------------------
-- Un correo, un pago — prueba de humo
--
-- EL CASO QUE MANDA
-- Dos personas transfieren $15.000 en el MISMO minuto. Son dos pagos.
-- Con el índice viejo entraba uno solo y el otro se perdía en silencio:
-- no fallaba nada, no avisaba nadie.
--
-- Lo demás:
--   · reprocesar el mismo correo sigue sin duplicar
--   · y si algún día llega uno sin id de correo, tampoco duplica
--
--   psql -d <base> -f humo-duplicados.sql
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

create or replace function cuantos() returns int language sql stable as
  $$ select count(*)::int from pagos $$;

-- La misma llave Bre-B en todos, que es lo que hay de verdad: es la de
-- la cuenta de Tumbao y no cambia nunca.
create or replace function llega(valor int, minuto text, correo text, quien text)
returns jsonb language sql as $$
  select registrar_pago_y_conciliar('bancolombia', valor,
    (((now() at time zone 'America/Bogota')::date || ' ' || minuto)::timestamp
       at time zone 'America/Bogota'),
    '1096803067', quien, null, 1.0, null, correo)
$$;

delete from pagos where true;


\echo ''
\echo '-- 1. Dos personas, mismo valor, mismo minuto -----------------------'

select chk('entra la primera', (llega(15000, '18:31', 'correo-A', 'ANA PEREZ')->>'duplicado')::boolean, false);
select chk('y la segunda TAMBIÉN',
  (llega(15000, '18:31', 'correo-B', 'BETO GOMEZ')->>'duplicado')::boolean, false);
select chk('son dos pagos, no uno', cuantos(), 2);
select chk('con remitentes distintos',
  (select count(distinct remitente)::int from pagos), 2);
select chk('y suman los 30.000 que entraron de verdad',
  (select sum(valor_cop)::int from pagos), 30000);


\echo ''
\echo '-- 2. El mismo correo dos veces sigue siendo un pago ----------------'
-- Es para lo que existía el índice viejo, y no se puede perder: n8n
-- reprocesa correos cuando algo falla a mitad.

select chk('reprocesar el mismo correo no duplica',
  (llega(15000, '18:31', 'correo-A', 'ANA PEREZ')->>'duplicado')::boolean, true);
select chk('siguen siendo dos', cuantos(), 2);
select chk('y devuelve el pago que ya existía',
  (llega(15000, '18:31', 'correo-A', 'ANA PEREZ')->>'pago_id')::uuid,
  (select id from pagos where hoja_fila = 'correo-A'));


\echo ''
\echo '-- 3. Tres seguidos en el mismo minuto ------------------------------'
-- Las 6 de la tarde de un miércoles.

do $$
begin
  perform llega(15000, '18:45', 'correo-C', 'CARO DIAZ');
  perform llega(15000, '18:45', 'correo-D', 'DANI RUIZ');
  perform llega(15000, '18:45', 'correo-E', 'EVA SOTO');
end $$;

select chk('los tres entran', cuantos(), 5);
select chk('nadie se perdió',
  (select count(*)::int from pagos where hoja_fila in ('correo-C','correo-D','correo-E')), 3);


\echo ''
\echo '-- 4. Sin id de correo tampoco duplica ------------------------------'
-- Hoy no pasa: la ingesta siempre manda el id. Pero el índice es parcial
-- y no cubre los nulos, así que la comprobación va escrita a mano.

select chk('el primero sin id entra',
  (registrar_pago_y_conciliar('bancolombia', 99000,
     now() - interval '2 hours', 'REF-X', 'SIN CORREO', null, 1.0, null, null)
   ->>'duplicado')::boolean, false);
select chk('el mismo otra vez, no',
  (registrar_pago_y_conciliar('bancolombia', 99000,
     (select fecha_pago from pagos where hoja_fila is null),
     'REF-X', 'SIN CORREO', null, 1.0, null, null)
   ->>'duplicado')::boolean, true);
select chk('sigue habiendo uno solo sin id',
  (select count(*)::int from pagos where hoja_fila is null), 1);


\echo ''
\echo '-- 5. El índice viejo ya no está ------------------------------------'

select chk('pagos_unicos se fue',
  (select count(*)::int from pg_indexes where indexname = 'pagos_unicos'), 0);
select chk('y está el nuevo',
  (select count(*)::int from pg_indexes where indexname = 'pagos_por_correo'), 1);


\echo ''
select case when count(*) = 0 then 'todo en verde'
            else count(*) || ' FALLOS' end as resultado from fallos;
select * from fallos;
