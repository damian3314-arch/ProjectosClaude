-- ---------------------------------------------------------------------
-- "Transferencia, recepción" se lee de caja — prueba de humo (0052)
--
-- Lo que esta prueba defiende: que la casilla no vuelva a mirar donde la
-- plata no está.
--
-- 0051 la hacía leer de `reservas` con origen='recepcion' y pago_id. En
-- producción esa fila no existe —25 reservas de recepción, las 25 con
-- pago_id nulo— así que la casilla salía en cero todos los días mientras
-- $285.000 reales vivían en caja_movimientos sin aparecer en Entradas.
-- La prueba de 0051 no lo detectó porque inventaba el caso: insertaba a
-- mano una reserva con origen='recepcion' Y pago_id.
--
-- Por eso aquí se prueba al revés: se crea el caso irreal a propósito y
-- se exige que NO mueva ninguna casilla.
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
insert into ctx select crear_token_admin('cajera de prueba 0052')->>'token';
create or replace function tk() returns text language sql stable as $$ select token from ctx $$;

create or replace function hoy() returns date language sql stable as
  $$ select (now() at time zone 'America/Bogota')::date $$;
create or replace function caja(d date) returns jsonb language sql stable as
  $$ select caja_del_dia(tk(), d) $$;

update ajustes set valor = (hoy() - 60)::text where clave = 'inicio_produccion';

insert into clases (id, nombre, profesor, fecha_hora, cupo_total, precio_cop)
values ('64111111-0000-4000-8000-000000000001', 'Clase de hoy', 'Prof',
        (hoy() + time '18:00') at time zone 'America/Bogota', 30, 15000);

\echo ''
\echo '-- Recepción cobra en el momento: caja, sin reserva --------------------'
-- El caso real. La persona llega, paga por transferencia, entra. No hay
-- cupo que apartar, así que no se crea reserva: se registra el cobro.
select chk('se registra la transferencia del mostrador',
  (caja_registrar(tk(), 'ingreso', 'clase_suelta', 15000, 'transferencia', 'llegó y pagó')->>'ok')::boolean, true);
select chk('y otra más',
  (caja_registrar(tk(), 'ingreso', 'clase_suelta', 15000, 'transferencia', 'llegó y pagó')->>'ok')::boolean, true);

select chk('transferencia por recepción: los dos cobros, $30.000',
  (caja(hoy())->'entradas'->>'recepcion_transferencia_cop')::int, 30000);
select chk('transferencia por recepción: n=2',
  (caja(hoy())->'entradas'->>'recepcion_transferencia_n')::int, 2);

\echo ''
\echo '-- Otro concepto por transferencia NO se cuela -------------------------'
select chk('se registra una mensualidad por transferencia',
  (caja_registrar(tk(), 'ingreso', 'mensualidad', 125000, 'transferencia', 'Mensualidad')->>'ok')::boolean, true);
select chk('la mensualidad no infla la casilla de recepción',
  (caja(hoy())->'entradas'->>'recepcion_transferencia_cop')::int, 30000);

\echo ''
\echo '-- REGRESIÓN: el caso irreal de 0051 no debe mover nada ----------------'
-- Una reserva con origen='recepcion' Y pago_id. Nunca ha ocurrido en
-- producción, pero es exactamente lo que 0051 daba por supuesto. Si
-- alguien vuelve a leer la casilla desde `reservas`, esta fila la infla
-- y la prueba lo caza.
insert into pagos (id, banco, valor_cop, fecha_pago, remitente, referencia, hoja_fila)
values ('65333333-0000-4000-8000-000000000001', 'Bancolombia', 15000,
        now(), 'Recep Con Pago', 'RC1', 'kk1');
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo,
                      origen, pago_id, created_at)
values ('66222222-0000-4000-8000-000000000001', 'R52-001',
        '64111111-0000-4000-8000-000000000001', 'Recep Con Pago', '3100000001',
        'confirmada', 'suelta', 'recepcion', '65333333-0000-4000-8000-000000000001', now());

select chk('una reserva recepción+pago NO infla la casilla de recepción',
  (caja(hoy())->'entradas'->>'recepcion_transferencia_cop')::int, 30000);
select chk('y tampoco se cuela en la de página',
  (caja(hoy())->'entradas'->>'pagina_transferencia_cop')::int, 0);

\echo ''
\echo '-- REGRESIÓN: una reprogramada no es plata que entró hoy ---------------'
-- Alguien que ya pagó antes y movió su clase. 0051 la mandaba a "página"
-- (contaba todo origen distinto de recepcion), inflando el total con
-- plata de otro día.
insert into pagos (id, banco, valor_cop, fecha_pago, remitente, referencia, hoja_fila)
values ('65333333-0000-4000-8000-000000000002', 'Bancolombia', 15000,
        now(), 'Reprogramada', 'RP1', 'kk2');
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo,
                      origen, pago_id, created_at)
values ('66222222-0000-4000-8000-000000000002', 'R52-002',
        '64111111-0000-4000-8000-000000000001', 'Reprogramada', '3100000002',
        'confirmada', 'suelta', 'reprogramada', '65333333-0000-4000-8000-000000000002', now());

select chk('una reprogramada no cuenta como página',
  (caja(hoy())->'entradas'->>'pagina_transferencia_cop')::int, 0);

\echo ''
\echo '-- La página sí cuenta, y sigue siendo la única fuente de esa casilla --'
insert into pagos (id, banco, valor_cop, fecha_pago, remitente, referencia, hoja_fila)
values ('65333333-0000-4000-8000-000000000003', 'Bancolombia', 15000,
        now(), 'Por La Pagina', 'PP1', 'kk3');
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo,
                      origen, pago_id, created_at)
values ('66222222-0000-4000-8000-000000000003', 'R52-003',
        '64111111-0000-4000-8000-000000000001', 'Por La Pagina', '3100000003',
        'confirmada', 'suelta', 'web', '65333333-0000-4000-8000-000000000003', now());

select chk('transferencia por página: $15.000',
  (caja(hoy())->'entradas'->>'pagina_transferencia_cop')::int, 15000);
select chk('transferencia por página: n=1',
  (caja(hoy())->'entradas'->>'pagina_transferencia_n')::int, 1);

\echo ''
\echo '-- SIN DOBLE CONTEO: es lo que hace válido sumar las tres --------------'
-- Recepción sale de caja_movimientos y página de reservas. Si algún día
-- un cobro del mostrador empezara a dejar reserva con pago_id, el mismo
-- dinero caería en las dos casillas y el total mentiría. Esto lo caza.
select chk('total de entradas = 30.000 (recepción) + 15.000 (página), sin repetir',
  (caja(hoy())->'entradas'->>'efectivo_cop')::int
  + (caja(hoy())->'entradas'->>'recepcion_transferencia_cop')::int
  + (caja(hoy())->'entradas'->>'pagina_transferencia_cop')::int, 45000);
select chk('ningún movimiento de clase suelta tiene reserva que le corresponda',
  (select count(*) from caja_movimientos m
     join reservas r on r.pago_id = m.pago_id
    where not m.anulado and m.concepto = 'clase_suelta'
      and r.estado = 'confirmada' and r.tipo = 'suelta')::int, 0);

\echo ''
select case when count(*) = 0 then 'todo en verde'
            else count(*) || ' FALLOS' end as resultado from fallos;
select * from fallos;
