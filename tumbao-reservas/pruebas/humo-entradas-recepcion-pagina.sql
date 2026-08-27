-- ---------------------------------------------------------------------
-- Entradas: efectivo de clase suelta, y transferencia por recepción y
-- por página — prueba de humo (0051)
--
-- El caso real: Tania cuenta en su cuaderno cuántas personas de clase
-- suelta entraron hoy. El efectivo no distingue recepción de un botón
-- genérico —los dos pasan por caja_movimientos igual—, así que va como
-- un solo número. La transferencia sí distingue, porque siempre queda
-- una fila en reservas con su origen.
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
insert into ctx select crear_token_admin('cajera de prueba 0051')->>'token';
create or replace function tk() returns text language sql stable as $$ select token from ctx $$;

create or replace function hoy() returns date language sql stable as
  $$ select (now() at time zone 'America/Bogota')::date $$;
create or replace function caja(d date) returns jsonb language sql stable as
  $$ select caja_del_dia(tk(), d) $$;

update ajustes set valor = (hoy() - 60)::text where clave = 'inicio_produccion';

insert into clases (id, nombre, profesor, fecha_hora, cupo_total, precio_cop)
values ('61111111-0000-4000-8000-000000000001', 'Clase de hoy', 'Prof',
        (hoy() + time '18:00') at time zone 'America/Bogota', 20, 15000);

\echo ''
\echo '-- Efectivo: el botón genérico de Caja, SIN ninguna reserva detrás ----'
-- Es justo el caso confirmado: a veces se cobra directo en Caja, sin
-- pasar por "apuntar a mano". No hay fila en reservas y aun así tiene
-- que contar.
select chk('se registra el efectivo sin reserva',
  (caja_registrar(tk(), 'ingreso', 'clase_suelta', 15000, 'efectivo', 'botón genérico')->>'ok')::boolean, true);

\echo ''
\echo '-- Efectivo: una "apuntada a mano" SÍ deja reserva, y el cobro va igual'
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo,
                      origen, pago_id, created_at)
values ('62222222-0000-4000-8000-000000000001', 'ENT-001',
        '61111111-0000-4000-8000-000000000001', 'Recep Efectivo', '3000000001',
        'confirmada', 'suelta', 'recepcion', null, now());
select chk('se registra el efectivo de la apuntada a mano',
  (caja_registrar(tk(), 'ingreso', 'clase_suelta', 15000, 'efectivo', 'Reserva ENT-001')->>'ok')::boolean, true);

\echo ''
\echo '-- Efectivo: OTRO concepto (mensualidad) NO se cuela aquí -------------'
select chk('se registra una mensualidad en efectivo',
  (caja_registrar(tk(), 'ingreso', 'mensualidad', 125000, 'efectivo', 'Mensualidad Marzo')->>'ok')::boolean, true);

\echo ''
\echo '-- Transferencia por recepción -----------------------------------------'
insert into pagos (id, banco, valor_cop, fecha_pago, remitente, referencia, hoja_fila)
values ('63333333-0000-4000-8000-000000000001', 'Bancolombia', 15000,
        now(), 'Recep Transf', 'RT1', 'gg1');
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo,
                      origen, pago_id, created_at)
values ('62222222-0000-4000-8000-000000000002', 'ENT-002',
        '61111111-0000-4000-8000-000000000001', 'Recep Transf', '3000000002',
        'confirmada', 'suelta', 'recepcion', '63333333-0000-4000-8000-000000000001', now());

\echo ''
\echo '-- Transferencia por página, y un grupo de 2 (cada quien aparte) ------'
insert into pagos (id, banco, valor_cop, fecha_pago, remitente, referencia, hoja_fila)
values ('63333333-0000-4000-8000-000000000002', 'Bancolombia', 15000,
        now(), 'Pagina Transf', 'PT1', 'gg2');
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo,
                      origen, pago_id, created_at)
values ('62222222-0000-4000-8000-000000000003', 'ENT-003',
        '61111111-0000-4000-8000-000000000001', 'Pagina Transf', '3000000003',
        'confirmada', 'suelta', 'formulario', '63333333-0000-4000-8000-000000000002', now());

insert into pagos (id, banco, valor_cop, fecha_pago, remitente, referencia, hoja_fila)
values ('63333333-0000-4000-8000-000000000003', 'Bancolombia', 30000,
        now(), 'Grupo Transf', 'GT1', 'gg3');
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo,
                      origen, pago_id, grupo_id, created_at)
values ('62222222-0000-4000-8000-000000000004', 'ENT-004',
        '61111111-0000-4000-8000-000000000001', 'Grupo Uno', '3000000004',
        'confirmada', 'suelta', 'web', '63333333-0000-4000-8000-000000000003',
        '62222222-0000-4000-8000-000000000004', now()),
       ('62222222-0000-4000-8000-000000000005', 'ENT-005',
        '61111111-0000-4000-8000-000000000001', 'Grupo Dos', '3000000005',
        'confirmada', 'suelta', 'web', '63333333-0000-4000-8000-000000000003',
        '62222222-0000-4000-8000-000000000004', now());

\echo ''
\echo '-- Los tres números ----------------------------------------------------'
select chk('efectivo clase suelta: los dos cobros (botón + apuntada), $30.000',
  (caja(hoy())->'entradas'->>'efectivo_cop')::int, 30000);
select chk('efectivo clase suelta: n=2',
  (caja(hoy())->'entradas'->>'efectivo_n')::int, 2);
select chk('la mensualidad NO se cuela en el efectivo de clase suelta',
  (caja(hoy())->'entradas'->>'efectivo_cop')::int <> 155000, true);

select chk('transferencia por recepción: $15.000',
  (caja(hoy())->'entradas'->>'recepcion_transferencia_cop')::int, 15000);
select chk('transferencia por recepción: n=1',
  (caja(hoy())->'entradas'->>'recepcion_transferencia_n')::int, 1);

select chk('transferencia por página: la suelta ($15.000) + el grupo (2×$15.000) = $45.000',
  (caja(hoy())->'entradas'->>'pagina_transferencia_cop')::int, 45000);
select chk('transferencia por página: n=3 (cada quien del grupo cuenta aparte)',
  (caja(hoy())->'entradas'->>'pagina_transferencia_n')::int, 3);

\echo ''
select case when count(*) = 0 then 'todo en verde'
            else count(*) || ' FALLOS' end as resultado from fallos;
select * from fallos;
