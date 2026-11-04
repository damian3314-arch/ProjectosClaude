-- ---------------------------------------------------------------------
-- La caja del día es la plata del día — prueba de humo
--
-- EL CASO REAL
-- El 11 de agosto la tirilla dijo "Reservas de la página: $45.000".
-- Ese día nueve personas pagaron reservas: $135.000. La caja contó
-- tres, porque sumaba las reservas por la fecha de la CLASE y las otras
-- seis habían pagado el 11 una clase del 12 y del 15.
--
-- Con el banco midiendo un día y la caja otro, el cierre no se puede
-- cuadrar contra nada.
--
-- Aquí se reconstruye ese día y se comprueba que ahora sí cuadra.
--
--   psql -d <base> -f humo-caja-del-dia.sql
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

-- HOY y PASADO MAÑANA en hora de Bogotá.
create or replace function hoy() returns date language sql stable as
  $$ select (now() at time zone 'America/Bogota')::date $$;
create or replace function caja(d date) returns jsonb language sql stable as
  $$ select caja_del_dia(tk(), d) $$;

update ajustes set valor = (hoy() - 60)::text where clave = 'inicio_produccion';

-- Dos clases: una HOY y otra PASADO MAÑANA.
insert into clases (id, nombre, profesor, fecha_hora, cupo_total, precio_cop)
values ('33333333-0000-4000-8000-000000000001', 'Clase de hoy', 'Prof',
        (hoy() + time '18:00') at time zone 'America/Bogota', 20, 15000),
       ('33333333-0000-4000-8000-000000000002', 'Clase de pasado', 'Prof',
        (hoy() + 2 + time '18:00') at time zone 'America/Bogota', 20, 15000);

-- Tres depósitos de HOY: uno paga la clase de hoy, dos la de pasado.
insert into pagos (id, banco, valor_cop, fecha_pago, remitente, referencia, hoja_fila)
values ('44444444-0000-4000-8000-000000000001', 'Bancolombia', 15000,
        (hoy() + time '10:00') at time zone 'America/Bogota', 'Ana Uno',  'R1', 'g1'),
       ('44444444-0000-4000-8000-000000000002', 'Bancolombia', 15000,
        (hoy() + time '11:00') at time zone 'America/Bogota', 'Ana Dos',  'R2', 'g2'),
       ('44444444-0000-4000-8000-000000000003', 'Bancolombia', 15000,
        (hoy() + time '12:00') at time zone 'America/Bogota', 'Ana Tres', 'R3', 'g3');

insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo, origen,
                      pago_id, created_at)
values ('55555555-0000-4000-8000-000000000001', 'PRB-001',
        '33333333-0000-4000-8000-000000000001', 'Ana Uno',  '3000000001',
        'confirmada', 'suelta', 'web', '44444444-0000-4000-8000-000000000001',
        (hoy() + time '10:00') at time zone 'America/Bogota'),
       ('55555555-0000-4000-8000-000000000002', 'PRB-002',
        '33333333-0000-4000-8000-000000000002', 'Ana Dos',  '3000000002',
        'confirmada', 'suelta', 'web', '44444444-0000-4000-8000-000000000002',
        (hoy() + time '11:00') at time zone 'America/Bogota'),
       ('55555555-0000-4000-8000-000000000003', 'PRB-003',
        '33333333-0000-4000-8000-000000000002', 'Ana Tres', '3000000003',
        'confirmada', 'suelta', 'web', '44444444-0000-4000-8000-000000000003',
        (hoy() + time '12:00') at time zone 'America/Bogota');


\echo ''
\echo '-- 1. Las tres reservas son plata de HOY -----------------------------'
-- Es el caso del 11 de agosto: dos de las tres son para una clase de
-- otro día, pero pagaron hoy. Antes la caja de hoy contaba $15.000.

select chk('la caja de hoy cuenta las tres',
  (caja(hoy())->>'reservas_cop')::int, 45000);
select chk('y el día de la clase ya no las cuenta otra vez',
  (caja(hoy() + 2)->>'reservas_cop')::int, 0);


\echo ''
\echo '-- 1b. Y separado: cuánto de eso es un anticipo para otro día --------'
-- El 24 de agosto esto fue justo lo que faltaba: $105.000 del banco
-- parecían perdidos comparados con AdminGym, y eran dos personas que
-- pagaron ese día por clases del día siguiente. La plata sí es de hoy
-- para el arqueo -no se resta de nada-, pero hay que poder decir
-- aparte cuánto de lo recibido es anticipo y cuánto es de un cliente
-- que disfrutó algo hoy mismo.

select chk('de esos 45.000, 30.000 son anticipo de otro día',
  (caja(hoy())->>'reservas_futuras_cop')::int, 30000);
select chk('dos reservas de las tres',
  (caja(hoy())->>'reservas_futuras_n')::int, 2);
select chk('pasado mañana no hay anticipos: ese día ya se pagó',
  (caja(hoy() + 2)->>'reservas_futuras_cop')::int, 0);


\echo ''
\echo '-- 2. Y cuadra con lo que dice el banco ------------------------------'
-- Esto es lo que hace que un cierre se pueda cuadrar: las dos mitades
-- del panel hablan por fin del mismo día.

select chk('el banco confirmó lo mismo que entró en reservas',
  (caja(hoy())->'banco'->>'recibido_cop')::int, 45000);


\echo ''
\echo '-- 3. Lo dictado hoy sigue disponible, pero aparte -------------------'
-- El número viejo no se pierde: responde a otra pregunta —cuánto valió
-- la operación del día— y por eso va en su propia línea.

select chk('hoy se dictó una sola clase reservada',
  (caja(hoy())->>'reservas_dictadas_n')::int, 1);
select chk('y vale quince mil',
  (caja(hoy())->>'reservas_dictadas_cop')::int, 15000);
select chk('pasado mañana se dictan dos',
  (caja(hoy() + 2)->>'reservas_dictadas_n')::int, 2);


\echo ''
\echo '-- 4. La plata de la puerta no se toca -------------------------------'
-- Lo que se recibe en efectivo en la entrada entra por caja_movimientos
-- y se cuenta el día en que se registra, como siempre.

select chk('una venta en efectivo entra',
  (caja_registrar(tk(), 'ingreso', 'clase_suelta', 15000, 'efectivo', 'en la puerta')->>'ok')::boolean, true);
select chk('y suma al efectivo de hoy',
  (caja(hoy())->>'ingreso_efectivo')::int, 15000);
select chk('sin mezclarse con las reservas',
  (caja(hoy())->>'reservas_cop')::int, 45000);
select chk('el total de hoy es lo uno más lo otro',
  (caja(hoy())->>'total_ingresos')::int, 60000);


\echo ''
\echo '-- 5. Una reserva a mano cuenta cuando se confirmó -------------------'
-- Sin depósito no hay fecha de banco, así que manda cuándo la confirmó
-- la persona del mostrador.

insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo, origen,
                      pago_id, created_at)
values ('55555555-0000-4000-8000-000000000004', 'PRB-004',
        '33333333-0000-4000-8000-000000000002', 'Ana Cuatro', '3000000004',
        'confirmada', 'suelta', 'mostrador', null,
        (hoy() + time '13:00') at time zone 'America/Bogota');

select chk('sale en la caja de hoy, no en la de la clase',
  (caja(hoy())->>'reservas_a_mano_n')::int, 1);
select chk('el día de la clase no la cuenta',
  (caja(hoy() + 2)->>'reservas_a_mano_n')::int, 0);
select chk('y no se cuela en el total, que ya la contó el mostrador',
  (caja(hoy())->>'total_ingresos')::int, 60000);


\echo ''
\echo '-- 6. Ayer no se movió -----------------------------------------------'
-- Un día sin nada sigue en cero: el cambio no reparte plata hacia atrás.

select chk('ayer sigue vacío', (caja(hoy() - 1)->>'reservas_cop')::int, 0);
select chk('y sin clases dictadas', (caja(hoy() - 1)->>'reservas_dictadas_cop')::int, 0);


\echo ''
select case when count(*) = 0 then 'todo en verde'
            else count(*) || ' FALLOS' end as resultado from fallos;
select * from fallos;
