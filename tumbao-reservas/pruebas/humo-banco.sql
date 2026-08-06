-- ---------------------------------------------------------------------
-- El banco como tercer testigo — prueba de humo
--
-- Lo que se comprueba no es que sume: es que la resta señale a la
-- persona correcta en los tres casos que importan.
--
--   1. Todo cuadra                  → sin identificar = 0
--   2. Entró plata que nadie apuntó  → sin identificar > 0
--   3. Se apuntó plata que el banco
--      nunca confirmó                → sin identificar < 0   ← el caro
--
-- Y uno más, que es la razón de que esto no bloquee el cierre: alguien
-- paga hoy una clase del martes. El banco lo ve hoy; la caja del día no.
--
-- Ojo con las aserciones: en Postgres `null <> 0` no es true, así que un
-- dato que llegue nulo pasaría de largo dando un verde falso. Todo va
-- con IS DISTINCT FROM.
--
-- Se corre así, contra una base desechable con las 26 migraciones:
--   psql -d t26 -f humo-banco.sql
-- ---------------------------------------------------------------------
\set ON_ERROR_STOP on
set client_min_messages = warning;

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

-- ---------------------------------------------------------------------
-- Montaje
-- ---------------------------------------------------------------------
create temp table ctx (token text);
insert into ctx select crear_token_admin('cajera de prueba')->>'token';

-- Dos clases: una hoy y otra el martes que viene. La del martes es la
-- que desmonta cualquier intento de exigir que banco y caja cuadren.
insert into clases (id, nombre, profesor, fecha_hora, cupo_total, precio_cop)
values ('aaaaaaaa-0000-4000-8000-000000000001', 'Salsa hoy', 'Prof',
        (((now() at time zone 'America/Bogota')::date + time '18:00')
          at time zone 'America/Bogota'), 20, 15000),
       ('aaaaaaaa-0000-4000-8000-000000000002', 'Salsa martes', 'Prof',
        (((now() at time zone 'America/Bogota')::date + 4 + time '18:00')
          at time zone 'America/Bogota'), 20, 15000);

-- Un momento de hoy que no se sale del día en Bogotá pase lo que pase.
create or replace function hoy_a_las(h int) returns timestamptz language sql stable as $$
  select (((now() at time zone 'America/Bogota')::date + make_time(h,0,0))
          at time zone 'America/Bogota')
$$;

\echo ''
\echo '-- 1. Todo cuadra --------------------------------------------------'

-- Una reserva de la página, pagada y casada con su aviso del banco.
insert into pagos (id, banco, valor_cop, fecha_pago, referencia, remitente, consumido)
values ('bbbbbbbb-0000-4000-8000-000000000001', 'bancolombia', 15000,
        hoy_a_las(10), 'REF1', 'CAMILA ROJAS', true);
insert into reservas (codigo, clase_id, nombre, telefono, estado, tipo, pago_id)
values ('TB-0001', 'aaaaaaaa-0000-4000-8000-000000000001', 'Camila Rojas',
        '3001112233', 'confirmada', 'suelta', 'bbbbbbbb-0000-4000-8000-000000000001');

-- Una transferencia del mostrador: la cajera la apunta Y el banco avisa.
select caja_registrar((select token from ctx), 'ingreso', 'mensualidad',
                      125000, 'transferencia', 'llave');
insert into pagos (banco, valor_cop, fecha_pago, referencia, remitente, consumido)
values ('bancolombia', 125000, hoy_a_las(11), 'REF2', 'LUIS PEREZ', false);

-- Y algo de efectivo, que con el banco no tiene nada que ver.
select caja_registrar((select token from ctx), 'ingreso', 'clase_suelta',
                      15000, 'efectivo', null);

select chk('recibido en banco = 140.000',
  (caja_del_dia((select token from ctx))->'banco'->>'recibido_cop')::int, 140000);
select chk('de reservas = 15.000',
  (caja_del_dia((select token from ctx))->'banco'->>'de_reservas_cop')::int, 15000);
select chk('del mostrador = 125.000',
  (caja_del_dia((select token from ctx))->'banco'->>'de_mostrador_cop')::int, 125000);
select chk('sin identificar = 0',
  (caja_del_dia((select token from ctx))->'banco'->>'sin_identificar_cop')::int, 0);
select chk('el efectivo no ensucia el control del banco',
  (caja_del_dia((select token from ctx))->>'ingreso_efectivo')::int, 15000);

\echo ''
\echo '-- 2. Entró plata que nadie apuntó ----------------------------------'

insert into pagos (banco, valor_cop, fecha_pago, remitente, consumido)
values ('bancolombia', 50000, hoy_a_las(12), 'DESCONOCIDO', false);

select chk('sin identificar se va a +50.000',
  (caja_del_dia((select token from ctx))->'banco'->>'sin_identificar_cop')::int, 50000);

\echo ''
\echo '-- 3. Se apuntó plata que el banco nunca confirmó -------------------'
-- El caso caro: comprobante viejo o editado. La cajera lo cree, lo
-- registra, y el correo del banco no llega nunca.

select caja_registrar((select token from ctx), 'ingreso', 'cumpleanos',
                      250000, 'transferencia', 'comprobante que no existe');

select chk('sin identificar se pone en NEGATIVO',
  (caja_del_dia((select token from ctx))->'banco'->>'sin_identificar_cop')::int, -200000);
select chk('y es negativo de verdad, no solo distinto',
  ((caja_del_dia((select token from ctx))->'banco'->>'sin_identificar_cop')::int < 0), true);

\echo ''
\echo '-- 4. Pago de hoy por una clase del martes --------------------------'
-- La razón de que esto sea informativo y no bloqueante.

insert into pagos (id, banco, valor_cop, fecha_pago, remitente, consumido)
values ('bbbbbbbb-0000-4000-8000-000000000009', 'bancolombia', 15000,
        hoy_a_las(19), 'ADELANTADA', true);
insert into reservas (codigo, clase_id, nombre, telefono, estado, tipo, pago_id)
values ('TB-0009', 'aaaaaaaa-0000-4000-8000-000000000002', 'Adelantada',
        '3009998877', 'confirmada', 'suelta', 'bbbbbbbb-0000-4000-8000-000000000009');

select chk('el banco SÍ lo ve hoy',
  (caja_del_dia((select token from ctx))->'banco'->>'de_reservas_cop')::int, 30000);
-- `reservas_cop` va por fecha de CLASE: la del martes no cuenta hoy. Si
-- este número subiera, el cierre contra AdminGym se rompería, porque
-- AdminGym tampoco la cuenta hoy.
select chk('pero la caja del día NO lo cuenta (clase del martes)',
  (caja_del_dia((select token from ctx))->>'reservas_cop')::int, 15000);
select chk('por eso el descuadre del banco NO puede bloquear el cierre',
  ((caja_del_dia((select token from ctx))->'banco'->>'sin_identificar_cop')::int
   is distinct from 0), true);

\echo ''
\echo '-- 5. El cierre guarda la foto del banco ----------------------------'

select caja_cerrar((select token from ctx), 115000, 100000, null, 100000);

select chk('el cierre guardó lo que decía el banco',
  (select banco_cop from caja_cierres
    where dia = (now() at time zone 'America/Bogota')::date), 205000);
select chk('y guardó el descuadre del momento',
  (select banco_sin_ident_cop from caja_cierres
    where dia = (now() at time zone 'America/Bogota')::date), -200000);
-- Lo que de verdad manda en el cierre sigue siendo el efectivo.
select chk('cerró aunque el banco no cuadre',
  (caja_del_dia((select token from ctx))->>'cerrado')::boolean, true);
select chk('el arqueo del efectivo es el que decide',
  (caja_del_dia((select token from ctx))->'cierre'->>'diferencia_cop')::int, 0);

\echo ''
\echo '-- 6. Ayer no contamina hoy -----------------------------------------'

insert into pagos (banco, valor_cop, fecha_pago, remitente, consumido)
values ('bancolombia', 999000, hoy_a_las(10) - interval '1 day', 'DE AYER', false);

select chk('un pago de ayer no entra en el día de hoy',
  (caja_del_dia((select token from ctx))->'banco'->>'recibido_cop')::int, 205000);

\echo ''
select case when count(*) = 0 then 'todo en verde'
            else count(*) || ' FALLOS' end as resultado from fallos;
select * from fallos;
