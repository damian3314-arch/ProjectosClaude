-- ---------------------------------------------------------------------
-- Quien verifica el token no puede ser STABLE — prueba de humo
--
-- EL CASO REAL
-- El 6 de septiembre la pestaña Mensualidad del panel no enseñaba nada.
-- El Worker contestaba 502 y en sus registros quedaba:
--
--   supabase 405: {"code":"25006",
--     "message":"cannot execute UPDATE in a read-only transaction"}
--
-- `mensualidad_lista` estaba marcada STABLE porque «solo lee». Lee la
-- lista, sí, pero lo primero que hace es llamar a
-- `verificar_token_admin`, y esa SÍ escribe: sella `ultimo_uso` en cada
-- uso. PostgREST corre las funciones STABLE dentro de una transacción de
-- solo lectura, así que ese UPDATE revienta y se lleva la llamada
-- entera. Lo arregló la 0073.
--
-- POR QUÉ ESTA PRUEBA Y NO UNA DE NAVEGADOR
-- El fallo no está en el HTML ni en el Worker: está en un atributo de
-- una función de Postgres. Ninguna prueba del panel lo habría visto —
-- todas hablan con un servidor fingido, que contesta igual de bien
-- venga la función marcada como venga.
--
-- Y el guardián que trae la 0073 solo corre cuando corre la 0073. Esta
-- prueba es la que se puede pasar cualquier día, sobre todo después de
-- escribir una función nueva.
--
--   psql -d <base> -f humo-volatilidad-token.sql
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
\echo '-- 1. La premisa: verificar el token escribe --------------------------'
-- Si algún día `verificar_token_admin` dejara de escribir, esta prueba
-- entera sobra. Mientras selle `ultimo_uso`, manda.

select chk('verificar_token_admin escribe, así que es VOLATILE',
  (select p.provolatile::text from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'verificar_token_admin'),
  'v');

\echo ''
\echo '-- 2. Ninguna función que lo llame puede ser STABLE -------------------'
-- `prokind = ''f''` deja fuera las agregadas y de ventana: a esas
-- `pg_get_functiondef` no les saca definición y revienta con «array_agg
-- is an aggregate function».

select chk('ninguna función que verifique token está marcada STABLE/IMMUTABLE',
  (select coalesce(string_agg(p.proname, ', ' order by p.proname), '(ninguna)')
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
      and p.provolatile in ('i', 's')
      and pg_get_functiondef(p.oid) like '%verificar_token_admin%'),
  '(ninguna)');

\echo ''
\echo '-- 3. La que lo rompió, por su nombre ---------------------------------'
-- Nombrada aparte a propósito: si mañana alguien la vuelve a marcar
-- STABLE, el fallo dice cuál es sin tener que leer una lista.

select chk('mensualidad_lista es VOLATILE (0073)',
  (select p.provolatile::text from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'mensualidad_lista'),
  'v');

\echo ''
\echo '-- 4. Y la pública sigue pudiendo ser STABLE --------------------------'
-- `mensualidad_cupos` no verifica token y por lo tanto no escribe. Es
-- correcto que sea STABLE y no hay que "arreglarla": la página pública
-- de mensualidad la llama sin autenticarse y funciona.

select chk('mensualidad_cupos no llama a verificar_token_admin',
  (select pg_get_functiondef(p.oid) like '%verificar_token_admin%'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'mensualidad_cupos'),
  false);

\echo ''
select case when count(*) = 0 then 'todo en verde'
            else count(*) || ' FALLOS' end as resultado from fallos;
select * from fallos;
