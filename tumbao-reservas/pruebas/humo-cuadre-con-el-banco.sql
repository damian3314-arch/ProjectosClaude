-- ---------------------------------------------------------------------
-- El puente entre la puerta y el banco — humo (0064)
--
-- El caso real es la tirilla del sábado 29 de agosto: «Entradas del
-- día $360.000» y debajo «Bancolombia reportó hoy $195.000». Las dos
-- cifras son correctas y no se parecen, porque 16 de las 21 personas
-- que entraron habían pagado días antes y parte de lo que sí entró al
-- banco es de clases que no se han dictado.
--
-- Lo que esta prueba defiende:
--   · quien entró hoy con plata de otro día se cuenta como tal, y su
--     plata NO aparece en lo que entró al banco hoy
--   · quien pagó hoy sale en las dos mitades con la misma cifra
--   · tres cupos futuros con un solo depósito son 3 cupos y 1 depósito
--   · una mensualidad va en `otros`, nunca en «futuras»
--   · LA INVARIANTE: identificado = hoy + futuras + otros, y lo que no
--     se supo nombrar es exactamente reportado − identificado
--   · un día sin nada devuelve ceros y no revienta
-- ---------------------------------------------------------------------
\set ON_ERROR_STOP on
set timezone = 'America/Bogota';
set client_min_messages = notice;

begin;

create temp table fallos (que text, esperado text, obtenido text);
create or replace function chk(que text, obtenido anyelement, esperado anyelement)
returns void language plpgsql as $$
begin
  if obtenido is distinct from esperado then
    insert into fallos values (que, esperado::text, coalesce(obtenido::text,'(null)'));
    raise notice '  x %  (esperaba %, llegó %)', que, esperado, coalesce(obtenido::text,'null');
  else
    raise notice '  v %', que;
  end if;
end $$;

create temp table ctx (token text);
insert into ctx select crear_token_admin('cajera de prueba 0064')->>'token';
create or replace function tk() returns text language sql stable as $$ select token from ctx $$;
create or replace function hoy() returns date language sql stable as
  $$ select (now() at time zone 'America/Bogota')::date $$;
update ajustes set valor = (hoy() - 60)::text where clave = 'inicio_produccion';

-- El bloque que se está probando, para no repetir la llamada entera.
create or replace function cu() returns jsonb language sql as
  $$ select caja_del_dia(tk(), hoy())->'cuadre' $$;
create or replace function q(k text) returns int language sql as
  $$ select (cu()->'quien_entro'->>k)::int $$;
create or replace function b(k text) returns int language sql as
  $$ select (cu()->'entro_al_banco'->>k)::int $$;

-- ── el montaje ───────────────────────────────────────────────────────
insert into clases (id, nombre, profesor, fecha_hora, cupo_total, precio_cop)
values ('c0000000-0000-4000-8000-000000000001','Clase de hoy 6pm','Kevin',
        (hoy() + time '18:00') at time zone 'America/Bogota', 30, 15000),
       ('c0000000-0000-4000-8000-000000000002','Clase del sábado que viene','Kevin',
        (hoy() + 7 + time '18:00') at time zone 'America/Bogota', 30, 15000);

-- 1. Entra hoy, pero pagó hace tres días. Su plata está en el extracto
--    del martes, no en el de hoy: por eso las dos cifras no cuadran.
insert into pagos (id, banco, valor_cop, fecha_pago, remitente, referencia, consumido)
values ('a0000000-0000-4000-8000-000000000001','bancolombia', 15000,
        (hoy() - 3 + time '09:10') at time zone 'America/Bogota',
        'CAMILA LOPEZ','M11112222', true);
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo, origen, pago_id)
values ('d0000000-0000-4000-8000-000000000001','ANT-01',
        'c0000000-0000-4000-8000-000000000001','Camila Lopez','3000000001',
        'confirmada','suelta','web','a0000000-0000-4000-8000-000000000001');

-- 2. Entra hoy y paga hoy: es el único que sale en las dos mitades.
insert into pagos (id, banco, valor_cop, fecha_pago, remitente, referencia, consumido)
values ('a0000000-0000-4000-8000-000000000002','bancolombia', 15000,
        (hoy() + time '17:40') at time zone 'America/Bogota',
        'DANIELA RUIZ','M33334444', true);
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo, origen, pago_id)
values ('d0000000-0000-4000-8000-000000000002','HOY-01',
        'c0000000-0000-4000-8000-000000000001','Daniela Ruiz','3000000002',
        'confirmada','suelta','web','a0000000-0000-4000-8000-000000000002');

-- 3. Entró y no hay depósito que buscar (venía reprogramada).
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo, origen)
values ('d0000000-0000-4000-8000-000000000003','REP-01',
        'c0000000-0000-4000-8000-000000000001','Julieth Herrera','3000000003',
        'confirmada','suelta','reprogramada');

-- 4. TRES amigas, UN solo depósito, para el sábado que viene. Tres
--    sillas que no se han usado y un solo renglón en el extracto. La
--    tercera no lleva pago_id propio: cuelga del grupo, como en la
--    página.
insert into pagos (id, banco, valor_cop, fecha_pago, remitente, referencia, consumido)
values ('a0000000-0000-4000-8000-000000000003','bancolombia', 45000,
        (hoy() + time '11:29') at time zone 'America/Bogota',
        'ISABEL FLOREZ MARTINEZ','M07471046', true);
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo, origen, pago_id, grupo_id)
values ('d0000000-0000-4000-8000-000000000004','FUT-01',
        'c0000000-0000-4000-8000-000000000002','Isabel Florez','3000000004',
        'confirmada','suelta','web','a0000000-0000-4000-8000-000000000003', null),
       ('d0000000-0000-4000-8000-000000000005','FUT-02',
        'c0000000-0000-4000-8000-000000000002','Lizet Gutierrez','3000000005',
        'confirmada','suelta','web','a0000000-0000-4000-8000-000000000003',
        'd0000000-0000-4000-8000-000000000004'),
       ('d0000000-0000-4000-8000-000000000006','FUT-03',
        'c0000000-0000-4000-8000-000000000002','Ludys Herazo','3000000006',
        'confirmada','suelta','web', null,
        'd0000000-0000-4000-8000-000000000004');

-- 5. Una mensualidad de hoy: paga clases sin dictar, pero no tiene
--    cupo ni fecha. Va en `otros`, no en futuras.
insert into pagos (id, banco, valor_cop, fecha_pago, remitente, referencia, consumido)
values ('a0000000-0000-4000-8000-000000000004','bancolombia', 30000,
        (hoy() + time '17:12') at time zone 'America/Bogota',
        'MARTHA NUNEZ','M55554444', false);
select caja_registrar(tk(), 'ingreso', 'mensualidad', 30000, 'transferencia', null,
                      'a0000000-0000-4000-8000-000000000004');

-- 6. Y un depósito de hoy que nadie ha reclamado todavía: es el trabajo
--    que queda, y tiene que salir dicho, no escondido.
insert into pagos (id, banco, valor_cop, fecha_pago, remitente, referencia, consumido)
values ('a0000000-0000-4000-8000-000000000005','bancolombia', 90000,
        (hoy() + time '20:05') at time zone 'America/Bogota',
        'SIN RECLAMAR','M99990000', false);

\echo ''
\echo '-- Quién entró hoy y con qué plata -------------------------------------'
select chk('entraron tres personas',                    q('personas'), 3);
select chk('una traía la plata de hace tres días',      q('pagaron_antes'), 1);
select chk('una pagó hoy',                              q('pagaron_hoy'), 1);
select chk('y una entró sin depósito que buscar',       q('sin_deposito'), 1);
select chk('las tres casillas suman las personas',
  q('pagaron_antes') + q('pagaron_hoy') + q('sin_deposito'), q('personas'));

\echo ''
\echo '-- De lo que entró al banco hoy, qué era -------------------------------'
select chk('un cupo de hoy pagado hoy',                 b('clases_hoy_n'), 1);
select chk('y son 15.000',                              b('clases_hoy_cop'), 15000);
select chk('las dos mitades dicen la misma cifra',
  b('clases_hoy_cop'), q('pagaron_hoy_cop'));

-- Lo que motivó todo el bloque: los 15.000 de Camila entraron por la
-- puerta hoy pero al banco entraron el martes. Si se colaran aquí, el
-- papel volvería a decir que sobran 15.000 que nadie va a encontrar.
select chk('la plata de quien pagó antes NO está en lo del banco de hoy',
  (select count(*)::int from pagos p
    where p.id = 'a0000000-0000-4000-8000-000000000001'
      and (p.fecha_pago at time zone 'America/Bogota')::date = hoy()), 0);
select chk('y por eso lo del banco no incluye sus 15.000',
  b('clases_hoy_cop') < 30000, true);

\echo ''
\echo '-- Tres cupos futuros con un solo depósito -----------------------------'
select chk('son tres sillas del sábado que viene',      b('futuras_cupos'), 3);
select chk('pero un solo renglón que buscar',           b('futuras_depositos'), 1);
select chk('por 45.000',                                b('futuras_cop'), 45000);
select chk('y no se cuelan en las clases de hoy',       b('clases_hoy_cop'), 15000);

\echo ''
\echo '-- La mensualidad va en su propio renglón ------------------------------'
select chk('sale un solo concepto en otros',
  jsonb_array_length(cu()->'entro_al_banco'->'otros'), 1);
select chk('y es la mensualidad',
  (cu()->'entro_al_banco'->'otros'->0->>'concepto'), 'mensualidad');
select chk('una, por 30.000',
  (cu()->'entro_al_banco'->'otros'->0->>'cop')::int, 30000);
select chk('otros_cop es esa mensualidad',              b('otros_cop'), 30000);
select chk('y NO se contó como futura',                 b('futuras_cop'), 45000);

\echo ''
\echo '-- LA INVARIANTE: el cuadre cierra ------------------------------------'
select chk('identificado = clases de hoy + futuras + otros',
  b('identificado_cop'), b('clases_hoy_cop') + b('futuras_cop') + b('otros_cop'));
select chk('el banco reportó los cuatro depósitos de hoy',
  b('reporto_banco_cop'), 15000 + 45000 + 30000 + 90000);
select chk('reporto_banco_cop es el mismo que se imprime arriba',
  b('reporto_banco_cop'),
  (caja_del_dia(tk(), hoy())->'banco'->>'recibido_cop')::int);
select chk('lo que falta por nombrar es la resta, exacta',
  b('sin_identificar_cop'), b('reporto_banco_cop') - b('identificado_cop'));
select chk('y es el depósito que nadie ha reclamado',
  b('sin_identificar_cop'), 90000);

\echo ''
\echo '-- Un día sin nada no revienta ----------------------------------------'
select chk('día vacío: cero personas',
  ((caja_del_dia(tk(), hoy() + 30)->'cuadre'->'quien_entro')->>'personas')::int, 0);
select chk('día vacío: cero identificado',
  ((caja_del_dia(tk(), hoy() + 30)->'cuadre'->'entro_al_banco')->>'identificado_cop')::int, 0);
select chk('día vacío: cero sin identificar',
  ((caja_del_dia(tk(), hoy() + 30)->'cuadre'->'entro_al_banco')->>'sin_identificar_cop')::int, 0);
select chk('día vacío: otros es una lista vacía',
  jsonb_array_length(caja_del_dia(tk(), hoy() + 30)->'cuadre'->'entro_al_banco'->'otros'), 0);

\echo ''
select case when count(*) = 0 then 'TODO EN VERDE'
            else count(*) || ' FALLO(S)' end as resultado from fallos;
select * from fallos;

rollback;
