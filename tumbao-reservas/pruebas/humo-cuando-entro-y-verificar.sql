-- ---------------------------------------------------------------------
-- Cuándo entró la plata, y qué hay que verificar — prueba de humo (0053)
--
-- El caso real: Tania cierra e imprime, y después se sienta con el
-- extracto de Bancolombia. Hoy revisa las quince personas del día. Casi
-- todas sobran: si una reserva de la página se confirmó SOLA, el cruce
-- automático ya es la prueba de que la plata entró.
--
-- Lo que esta prueba defiende es justamente esa frontera: que lo
-- automático NO salga en la lista de verificar, que lo de a mano SÍ, y
-- que un grupo que paga junto cuente como UN depósito y no como tres.
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
insert into ctx select crear_token_admin('cajera de prueba 0053')->>'token';
create or replace function tk() returns text language sql stable as $$ select token from ctx $$;
-- resuelta_por apunta a admin_tokens: es el token de quien confirmo a
-- mano. Se toma el recien creado en vez de inventar un uuid.
create or replace function quien() returns uuid language sql stable as
  $$ select id from admin_tokens where nombre = 'cajera de prueba 0053' limit 1 $$;
create or replace function hoy() returns date language sql stable as
  $$ select (now() at time zone 'America/Bogota')::date $$;
create or replace function caja(d date) returns jsonb language sql stable as
  $$ select caja_del_dia(tk(), d) $$;

update ajustes set valor = (hoy() - 60)::text where clave = 'inicio_produccion';

insert into clases (id, nombre, profesor, fecha_hora, cupo_total, precio_cop)
values ('71111111-0000-4000-8000-000000000001', 'Clase de hoy', 'Prof',
        (hoy() + time '18:00') at time zone 'America/Bogota', 40, 15000);

\echo ''
\echo '-- Pagos de dias distintos, todos para la clase de HOY ----------------'
-- Dos pagaron hoy y uno pagó anteayer. Los tres entran hoy: es
-- exactamente el caso que hoy obliga a abrir el sistema para responder
-- "vino hoy pero pagó el lunes, ¿sí entró la plata?".
insert into pagos (id, banco, valor_cop, fecha_pago, remitente, referencia, hoja_fila) values
  ('72333333-0000-4000-8000-000000000001','Bancolombia',15000, now(), 'Hoy Uno','H1','f1'),
  ('72333333-0000-4000-8000-000000000002','Bancolombia',15000, now(), 'Hoy Dos','H2','f2'),
  ('72333333-0000-4000-8000-000000000003','Bancolombia',15000,
     now() - interval '2 days', 'Anteayer','A1','f3');

insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo, origen, pago_id, created_at) values
  ('73222222-0000-4000-8000-000000000001','C53-1','71111111-0000-4000-8000-000000000001',
   'Hoy Uno','3200000001','confirmada','suelta','web','72333333-0000-4000-8000-000000000001', now()),
  ('73222222-0000-4000-8000-000000000002','C53-2','71111111-0000-4000-8000-000000000001',
   'Hoy Dos','3200000002','confirmada','suelta','formulario','72333333-0000-4000-8000-000000000002', now()),
  ('73222222-0000-4000-8000-000000000003','C53-3','71111111-0000-4000-8000-000000000001',
   'Anteayer','3200000003','confirmada','suelta','web','72333333-0000-4000-8000-000000000003', now());

select chk('cuando_entro: dos dias distintos',
  jsonb_array_length(caja(hoy())->'cuando_entro'), 2);
select chk('cuando_entro: hoy son 2 personas, $30.000',
  ((caja(hoy())->'cuando_entro'->0->>'personas')::int * 1000000
   + (caja(hoy())->'cuando_entro'->0->>'cop')::int), 2 * 1000000 + 30000);
select chk('cuando_entro: el mas viejo dice cuantos dias antes fue',
  (caja(hoy())->'cuando_entro'->1->>'dias_antes')::int, 2);
select chk('cuando_entro: y su plata, $15.000',
  (caja(hoy())->'cuando_entro'->1->>'cop')::int, 15000);

\echo ''
\echo '-- Lo automatico NO se verifica: el cruce ya es la prueba -------------'
select chk('con solo reservas automaticas, no hay nada que verificar',
  jsonb_array_length(caja(hoy())->'por_verificar'->'lista'), 0);
select chk('y el total a buscar es cero',
  (caja(hoy())->'por_verificar'->>'cop')::int, 0);

\echo ''
\echo '-- Un grupo que paga junto es UN deposito, no tres --------------------'
-- El 27 de agosto pasó de verdad: tres personas distintas confirmadas a
-- mano compartian la referencia 91289724619. En el extracto hay UNA
-- linea de $45.000. Listarlas por separado manda a buscar tres.
-- El grupo_id apunta al primero. Asi lo modela la base: el indice
-- reservas_referencia_unica exime a los miembros de un grupo, porque un
-- solo deposito paga por varios. Es la misma razon por la que aqui se
-- agrupa por referencia.
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo,
                      origen, referencia_pago, grupo_id, resuelta_por, resuelta_at, created_at) values
  ('73222222-0000-4000-8000-000000000004','C53-4','71111111-0000-4000-8000-000000000001',
   'Grupo Uno','3200000004','confirmada','suelta','web','91289724619',
   '73222222-0000-4000-8000-000000000004',
   quien(), now(), now()),
  ('73222222-0000-4000-8000-000000000005','C53-5','71111111-0000-4000-8000-000000000001',
   'Grupo Dos','3200000005','confirmada','suelta','web','91289724619',
   '73222222-0000-4000-8000-000000000004',
   quien(), now(), now()),
  ('73222222-0000-4000-8000-000000000006','C53-6','71111111-0000-4000-8000-000000000001',
   'Grupo Tres','3200000006','confirmada','suelta','web','91289724619',
   '73222222-0000-4000-8000-000000000004',
   quien(), now(), now());

select chk('las tres del grupo son UNA linea',
  jsonb_array_length(caja(hoy())->'por_verificar'->'lista'), 1);
select chk('esa linea dice 3 personas',
  (caja(hoy())->'por_verificar'->'lista'->0->>'personas')::int, 3);
select chk('y un solo deposito de $45.000',
  (caja(hoy())->'por_verificar'->'lista'->0->>'cop')::int, 45000);
select chk('con la referencia que se busca en el extracto',
  caja(hoy())->'por_verificar'->'lista'->0->>'referencia', '91289724619');

\echo ''
\echo '-- Una reprogramada se lista, pero con cero --------------------------'
-- Ya pagó otro dia. Sumarla mandaria a buscar plata que no existe; no
-- listarla la haria parecer perdida.
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo,
                      origen, resuelta_por, resuelta_at, created_at) values
  ('73222222-0000-4000-8000-000000000007','C53-7','71111111-0000-4000-8000-000000000001',
   'Reprogramada','3200000007','confirmada','suelta','reprogramada',
   quien(), now(), now());

select chk('la reprogramada aparece aparte',
  jsonb_array_length(caja(hoy())->'por_verificar'->'lista'), 2);
select chk('marcada como que no trae plata',
  (caja(hoy())->'por_verificar'->'lista'->1->>'sin_plata')::boolean, true);
select chk('y no infla el total a buscar',
  (caja(hoy())->'por_verificar'->>'cop')::int, 45000);
select chk('el total de personas si las cuenta a todas',
  (caja(hoy())->'por_verificar'->>'personas')::int, 4);

\echo ''
\echo '-- Lo de recepcion no se data: se cobra en el momento -----------------'
select chk('se registra un cobro del mostrador',
  (caja_registrar(tk(), 'ingreso', 'clase_suelta', 15000, 'transferencia', 'mostrador')->>'ok')::boolean, true);
select chk('no se cuela en cuando_entro, que solo mira la pagina',
  jsonb_array_length(caja(hoy())->'cuando_entro'), 2);

\echo ''
\echo '-- Las entradas de 0051/0052 siguen intactas -------------------------'
select chk('pagina: 3 personas de la clase de hoy',
  (caja(hoy())->'entradas'->>'pagina_transferencia_n')::int, 3);
select chk('recepcion por transferencia: el cobro del mostrador',
  (caja(hoy())->'entradas'->>'recepcion_transferencia_cop')::int, 15000);

\echo ''
select case when count(*) = 0 then 'todo en verde'
            else count(*) || ' FALLOS' end as resultado from fallos;
select * from fallos;
