-- ---------------------------------------------------------------------
-- Cuánta gente entró y el depósito que llegó tarde — humo (0065)
--
-- Dos descuadres reales de la caja de Tumbao:
--
--   · Llegan tres personas juntas y pagan $45.000 en efectivo. La cajera
--     registra UN movimiento, porque es un solo cobro. Hasta la 0065 el
--     cierre contaba UNA persona, y la cuenta de gente del día quedaba
--     mal sin que nadie supiera por qué.
--
--   · La cajera cobra una mensualidad por transferencia y la registra a
--     mano con la clienta delante. Horas después llega la alerta del
--     banco y entra un depósito sin dueño. Nadie los cruzaba nunca: esa
--     plata quedaba contada en la Caja Y persiguiéndose en la tirilla.
--
-- Lo que esta prueba defiende:
--   · un cobro de 3 clases sueltas cuenta 3 personas, no 1
--   · las filas anteriores a la 0065 siguen contando 1
--   · el depósito tardío se enlaza y deja de ser «plata sin dueño»
--   · y no se deja enlazar cuando no es el mismo dinero: movimiento ya
--     enlazado, cobro en efectivo, depósito que ya es de una reserva,
--     o depósito que no alcanza
--   · un depósito MAYOR sí cubre y queda con saldo, igual que en
--     caja_registrar desde la 0057
--   · los permisos quedan cerrados a anon y authenticated
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
insert into ctx select crear_token_admin('cajera de prueba 0065')->>'token';
create or replace function tk() returns text language sql stable as $$ select token from ctx $$;
create or replace function hoy() returns date language sql stable as
  $$ select (now() at time zone 'America/Bogota')::date $$;
update ajustes set valor = (hoy() - 60)::text where clave = 'inicio_produccion';

-- Atajos, para que cada comprobación se lea de un vistazo.
create or replace function d() returns jsonb language sql as
  $$ select caja_del_dia(tk(), hoy()) $$;
create or replace function personas() returns int language sql as
  $$ select (d()->'entradas'->>'personas_n')::int $$;
create or replace function e(k text) returns int language sql as
  $$ select (d()->'entradas'->>k)::int $$;
create or replace function co(k text) returns int language sql as
  $$ select (d()->'conciliacion'->>k)::int $$;
create or replace function ba(k text) returns int language sql as
  $$ select (d()->'banco'->>k)::int $$;

insert into clases (id, nombre, profesor, fecha_hora, duracion_min,
                    cupo_total, precio_cop, lugar, activa, aforo)
values ('c0650000-0000-4000-8000-000000000001','Clase de hoy 6pm','Kevin',
        (hoy() + time '18:00') at time zone 'America/Bogota',
        60, 30, 15000, 'Sede Tumbao', true, 30);


\echo ''
\echo '-- 1. Tres personas, un solo cobro ------------------------------------'
-- El caso literal: tres amigas, $45.000 en efectivo, una sola línea.
select chk('el cobro se registra',
  (caja_registrar(tk(), 'ingreso', 'clase_suelta', 45000, 'efectivo',
                  'tres amigas', null, 3)->>'ok')::boolean, true);
select chk('y queda con cantidad 3',
  (select cantidad from caja_movimientos where nota = 'tres amigas'), 3);

select chk('EL CIERRE CUENTA 3 PERSONAS, NO 1',       personas(), 3);
select chk('la casilla de efectivo también dice 3',   e('efectivo_n'), 3);
select chk('y la plata sigue siendo 45.000',          e('efectivo_cop'), 45000);
select chk('la tirilla dice 3 clases sueltas en efectivo',
  (select (x->>'n')::int from jsonb_array_elements(d()->'resumen_conceptos') x
    where x->>'concepto' = 'clase_suelta' and x->>'medio' = 'efectivo'), 3);
select chk('y la línea del día lleva su cantidad a la vista',
  (select (x->>'cantidad')::int from jsonb_array_elements(d()->'movimientos') x
    where x->>'nota' = 'tres amigas'), 3);


\echo ''
\echo '-- 2. Las filas viejas siguen valiendo 1 ------------------------------'
-- Una fila escrita antes de la 0065, sin cantidad. Significaba una cosa
-- cobrada y tiene que seguir significando eso: nada que recalcular.
insert into caja_movimientos (dia, sentido, concepto, valor_cop, medio, nota)
values (hoy(), 'ingreso', 'clase_suelta', 15000, 'efectivo', 'fila vieja');
select chk('la fila vieja quedó en cantidad 1',
  (select cantidad from caja_movimientos where nota = 'fila vieja'), 1);
select chk('y suma una sola persona (3 + 1)',          personas(), 4);

-- Y no se puede escribir una cantidad imposible.
select chk('cantidad 0 se rechaza en caja_registrar',
  caja_registrar(tk(), 'ingreso', 'clase_suelta', 15000, 'efectivo',
                 null, null, 0)->>'error', 'CANTIDAD_INVALIDA');
do $$
begin
  insert into caja_movimientos (dia, sentido, concepto, valor_cop, medio, cantidad)
  values ((now() at time zone 'America/Bogota')::date,
          'ingreso', 'clase_suelta', 15000, 'efectivo', 0);
  perform chk('la base rechaza cantidad 0', 'entró'::text, 'rebotó'::text);
exception when check_violation then
  perform chk('la base rechaza cantidad 0', 'rebotó'::text, 'rebotó'::text);
end $$;


\echo ''
\echo '-- 3. El depósito que llegó tarde -------------------------------------'
-- La mensualidad se cobra por transferencia y se registra con la
-- clienta delante. Todavía no hay depósito que enlazar.
select chk('la mensualidad se registra sin depósito',
  (caja_registrar(tk(), 'ingreso', 'mensualidad', 125000, 'transferencia',
                  'Genny', null)->>'ok')::boolean, true);
select chk('y sale en «hay que buscarla a mano» de la tirilla',
  co('sin_enlazar_cop'), 125000);

-- Horas después, la alerta del banco.
insert into pagos (id, banco, valor_cop, fecha_pago, remitente, referencia, consumido)
values ('a0650000-0000-4000-8000-000000000001','bancolombia', 125000,
        (hoy() + time '17:45') at time zone 'America/Bogota',
        'GENNY MARTINEZ','M65000001', false);
select chk('el depósito llega y aparece como plata sin dueño',
  ba('libre_hoy_cop'), 125000);
select chk('la misma plata está contada en los dos sitios (el descuadre)',
  co('sin_enlazar_cop') + ba('libre_hoy_cop'), 250000);

create temp table ids (mov uuid, pago uuid);
insert into ids
  select (select id from caja_movimientos where nota = 'Genny'),
         'a0650000-0000-4000-8000-000000000001';

-- Se guarda la respuesta: enlazar dos veces el mismo movimiento ya no
-- devuelve lo mismo, y eso se comprueba aparte más abajo.
create temp table enlace as
  select caja_enlazar_deposito(tk(), (select mov from ids), (select pago from ids)) as j;
select chk('se enlazan',        (select (j->>'ok')::boolean from enlace), true);
select chk('y no sobra nada',   (select (j->>'sobrante_cop')::int from enlace), 0);
select chk('la respuesta dice de qué era', (select j->>'concepto' from enlace),
  'mensualidad');
select chk('el movimiento quedó con su depósito',
  (select pago_id from caja_movimientos where nota = 'Genny'),
  'a0650000-0000-4000-8000-000000000001'::uuid);
select chk('DEJA DE SER PLATA SIN DUEÑO',                ba('libre_hoy_cop'), 0);
select chk('y deja de estar en «buscar a mano»',         co('sin_enlazar_cop'), 0);
select chk('el depósito ya no sale en la lista de libres',
  (select count(*)::int from pagos_sin_asignar
    where id = 'a0650000-0000-4000-8000-000000000001'), 0);
select chk('ahora la tirilla lo puede tachar contra el extracto',
  co('banco_hoy_cop'), 125000);
select chk('y el cuadre lo nombra como mensualidad',
  (d()->'cuadre'->'entro_al_banco'->'otros'->0->>'concepto'), 'mensualidad');


\echo ''
\echo '-- 4. Lo que NO se deja enlazar ---------------------------------------'
-- a) un movimiento que ya tiene depósito: ya se comprobó arriba, con el
--    mensaje que le dice a la cajera qué hacer.
select chk('un movimiento ya enlazado se rechaza',
  caja_enlazar_deposito(tk(), (select mov from ids), (select pago from ids))
    ->>'error', 'YA_ENLAZADO');
select chk('y el mensaje dice qué hacer',
  caja_enlazar_deposito(tk(), (select mov from ids), (select pago from ids))
    ->>'mensaje' like '%anula el movimiento%', true);

-- b) un cobro en efectivo. No es una regla de formulario: esa plata está
--    en el cajón, así que no puede ser la transferencia del banco.
insert into pagos (id, banco, valor_cop, fecha_pago, remitente, referencia, consumido)
values ('a0650000-0000-4000-8000-000000000002','bancolombia', 45000,
        (hoy() + time '18:10') at time zone 'America/Bogota',
        'QUIEN SEA','M65000002', false);
select chk('un cobro en efectivo no se enlaza',
  caja_enlazar_deposito(tk(),
    (select id from caja_movimientos where nota = 'tres amigas'),
    'a0650000-0000-4000-8000-000000000002')->>'error', 'ES_EFECTIVO');
select chk('y el mensaje explica que no es el mismo dinero',
  caja_enlazar_deposito(tk(),
    (select id from caja_movimientos where nota = 'tres amigas'),
    'a0650000-0000-4000-8000-000000000002')->>'mensaje'
      like '%el mismo dinero%', true);

-- c) un depósito que ya es de una reserva. Queda `consumido` con
--    usado_cop en cero, así que sale de la lista de plata sin dueño.
insert into pagos (id, banco, valor_cop, fecha_pago, remitente, referencia, consumido)
values ('a0650000-0000-4000-8000-000000000003','bancolombia', 15000,
        (hoy() + time '09:10') at time zone 'America/Bogota',
        'CAMILA LOPEZ','M65000003', true);
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo, origen, pago_id)
values ('d0650000-0000-4000-8000-000000000001','RES-01',
        'c0650000-0000-4000-8000-000000000001','Camila Lopez','3000000001',
        'confirmada','suelta','web','a0650000-0000-4000-8000-000000000003');
select chk('el cobro suelto se registra',
  (caja_registrar(tk(), 'ingreso', 'otro_ingreso', 15000, 'transferencia',
                  'suelto uno', null)->>'ok')::boolean, true);
select chk('un depósito que ya es de una reserva no se enlaza',
  caja_enlazar_deposito(tk(),
    (select id from caja_movimientos where nota = 'suelto uno'),
    'a0650000-0000-4000-8000-000000000003')->>'error', 'PAGO_YA_USADO');

-- d) valores que no alcanzan. Se devuelven los dos números para que el
--    mensaje los pueda decir.
insert into pagos (id, banco, valor_cop, fecha_pago, remitente, referencia, consumido)
values ('a0650000-0000-4000-8000-000000000004','bancolombia', 40000,
        (hoy() + time '19:00') at time zone 'America/Bogota',
        'NO ALCANZA','M65000004', false);
select chk('el cobro grande se registra',
  (caja_registrar(tk(), 'ingreso', 'otro_ingreso', 60000, 'transferencia',
                  'sesenta mil', null)->>'ok')::boolean, true);
select chk('un depósito que no alcanza se rechaza',
  caja_enlazar_deposito(tk(),
    (select id from caja_movimientos where nota = 'sesenta mil'),
    'a0650000-0000-4000-8000-000000000004')->>'error', 'VALORES_DISTINTOS');
select chk('y devuelve el valor del movimiento',
  (caja_enlazar_deposito(tk(),
    (select id from caja_movimientos where nota = 'sesenta mil'),
    'a0650000-0000-4000-8000-000000000004')->>'movimiento_cop')::int, 60000);
select chk('y el del depósito',
  (caja_enlazar_deposito(tk(),
    (select id from caja_movimientos where nota = 'sesenta mil'),
    'a0650000-0000-4000-8000-000000000004')->>'deposito_cop')::int, 40000);
select chk('el movimiento sigue sin enlazar',
  (select pago_id from caja_movimientos where nota = 'sesenta mil'), null::uuid);


\echo ''
\echo '-- 5. Un depósito mayor SÍ cubre, y sobra -----------------------------'
-- Es la regla que caja_registrar ya aplica desde la 0057: uno de 30.000
-- paga dos clases de 15.000. Enlazar tarde no puede ser más estricto que
-- registrar en el momento, o la misma pareja de números se aceptaría por
-- un camino y se rechazaría por el otro.
insert into pagos (id, banco, valor_cop, fecha_pago, remitente, referencia, consumido)
values ('a0650000-0000-4000-8000-000000000005','bancolombia', 50000,
        (hoy() + time '19:30') at time zone 'America/Bogota',
        'PAGO GRANDE','M65000005', false);
select chk('el cobro pequeño se registra',
  (caja_registrar(tk(), 'ingreso', 'otro_ingreso', 20000, 'transferencia',
                  'veinte mil', null)->>'ok')::boolean, true);
select chk('un depósito mayor sí cubre el cobro',
  (caja_enlazar_deposito(tk(),
    (select id from caja_movimientos where nota = 'veinte mil'),
    'a0650000-0000-4000-8000-000000000005')->>'ok')::boolean, true);
select chk('y dice cuánto sobró',
  (select saldo_grupo('a0650000-0000-4000-8000-000000000005')), 30000);
select chk('el sobrante sigue siendo plata sin dueño, dicha, no escondida',
  (select saldo_grupo_cop from pagos_sin_asignar
    where id = 'a0650000-0000-4000-8000-000000000005'), 30000);

-- Y se puede deshacer: caja_anular ya sabía soltar el pago_id.
select chk('anular el movimiento devuelve la plata al depósito',
  (caja_anular(tk(), (select id from caja_movimientos where nota = 'veinte mil'))
     ->>'libero_pago')::boolean, true);
select chk('y el depósito vuelve a tener sus 50.000',
  (select saldo_grupo('a0650000-0000-4000-8000-000000000005')), 50000);


\echo ''
\echo '-- 6. Los permisos quedan cerrados ------------------------------------'
select chk('caja_enlazar_deposito: anon NO',
  has_function_privilege('anon',
    'caja_enlazar_deposito(text, uuid, uuid)', 'execute'), false);
select chk('caja_enlazar_deposito: authenticated NO',
  has_function_privilege('authenticated',
    'caja_enlazar_deposito(text, uuid, uuid)', 'execute'), false);
select chk('caja_enlazar_deposito: service_role SÍ',
  has_function_privilege('service_role',
    'caja_enlazar_deposito(text, uuid, uuid)', 'execute'), true);
-- La firma de caja_registrar cambió, así que sus permisos NO viajaron:
-- la función nueva nace con execute para PUBLIC. Es lo que se perdió en
-- la 0056 y por eso se reafirma en la 0065.
select chk('caja_registrar (con cantidad): anon NO',
  has_function_privilege('anon',
    'caja_registrar(text, text, text, int, text, text, uuid, int)', 'execute'), false);
select chk('caja_registrar (con cantidad): authenticated NO',
  has_function_privilege('authenticated',
    'caja_registrar(text, text, text, int, text, text, uuid, int)', 'execute'), false);
select chk('caja_registrar (con cantidad): service_role SÍ',
  has_function_privilege('service_role',
    'caja_registrar(text, text, text, int, text, text, uuid, int)', 'execute'), true);
select chk('y no quedó viva la firma vieja de siete parámetros',
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'caja_registrar'), 1);


\echo ''
select case when count(*) = 0 then 'TODO EN VERDE'
            else count(*) || ' FALLO(S)' end as resultado from fallos;
select * from fallos;

rollback;
