-- ---------------------------------------------------------------------
-- Quien se apunta a mano en recepción también entró — humo (0054)
--
-- El caso real: llega alguien, en recepción lo apuntan como clase suelta
-- y no registran el cobro en Caja. Esa persona entró —al cuaderno de la
-- puerta sí cuenta— pero la tirilla no la veía por ningún lado. En el
-- histórico son 23 personas y $345.000.
--
-- Lo que esta prueba defiende sobre todo es la frontera contra el doble
-- conteo: si el cobro SÍ se registró, la reserva queda ligada a su
-- movimiento y no debe volver a contarse.
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
insert into ctx select crear_token_admin('cajera de prueba 0054')->>'token';
create or replace function tk() returns text language sql stable as $$ select token from ctx $$;
create or replace function hoy() returns date language sql stable as
  $$ select (now() at time zone 'America/Bogota')::date $$;
create or replace function caja(d date) returns jsonb language sql stable as
  $$ select caja_del_dia(tk(), d) $$;

update ajustes set valor = (hoy() - 60)::text where clave = 'inicio_produccion';

insert into clases (id, nombre, profesor, fecha_hora, cupo_total, precio_cop)
values ('81111111-0000-4000-8000-000000000001', 'Clase de hoy', 'Prof',
        (hoy() + time '18:00') at time zone 'America/Bogota', 40, 15000);

\echo ''
\echo '-- Sin nadie apuntado a mano, la casilla es cero ----------------------'
select chk('a_mano arranca en cero', (caja(hoy())->'entradas'->>'a_mano_cop')::int, 0);
select chk('y sin personas',        (caja(hoy())->'entradas'->>'a_mano_n')::int, 0);

\echo ''
\echo '-- Dos apuntados a mano, sin cobro registrado -------------------------'
-- El caso de Monica Duran y Rossana Tellez el 20 de agosto: apuntadas en
-- recepcion, sin movimiento de caja y sin pago del banco.
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo, origen, created_at) values
  ('82222222-0000-4000-8000-000000000001','AM-1','81111111-0000-4000-8000-000000000001',
   'Apuntada Una','3300000001','confirmada','suelta','recepcion', now()),
  ('82222222-0000-4000-8000-000000000002','AM-2','81111111-0000-4000-8000-000000000001',
   'Apuntada Dos','3300000002','confirmada','suelta','recepcion', now());

select chk('cuenta las dos personas', (caja(hoy())->'entradas'->>'a_mano_n')::int, 2);
select chk('y su plata, $30.000',     (caja(hoy())->'entradas'->>'a_mano_cop')::int, 30000);

\echo ''
\echo '-- SIN DOBLE CONTEO: si el cobro si se registro, no se repite ---------'
-- Es la frontera que hace valido sumar la casilla. Cuando recepcion
-- registra el cobro, la reserva queda ligada por cobro_mov_id y ese
-- movimiento ya cuenta en la casilla de efectivo.
select chk('se registra el cobro en Caja',
  (caja_registrar(tk(), 'ingreso', 'clase_suelta', 15000, 'efectivo', 'cobro del mostrador')->>'ok')::boolean, true);

insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo, origen,
                      cobro_mov_id, created_at)
values ('82222222-0000-4000-8000-000000000003','AM-3','81111111-0000-4000-8000-000000000001',
        'Cobrada Bien','3300000003','confirmada','suelta','recepcion',
        (select id from caja_movimientos where concepto='clase_suelta'
          and medio='efectivo' and not anulado order by created_at desc limit 1), now());

select chk('la cobrada NO entra en a_mano', (caja(hoy())->'entradas'->>'a_mano_n')::int, 2);
select chk('a_mano sigue en $30.000',       (caja(hoy())->'entradas'->>'a_mano_cop')::int, 30000);
select chk('su cobro si esta en efectivo',
  (caja(hoy())->'entradas'->>'efectivo_cop')::int, 15000);

\echo ''
\echo '-- Lo de la pagina tampoco se cuela -----------------------------------'
insert into pagos (id, banco, valor_cop, fecha_pago, remitente, referencia, hoja_fila)
values ('83333333-0000-4000-8000-000000000001','Bancolombia',15000,now(),'Pag','PP','hh');
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo, origen, pago_id, created_at)
values ('82222222-0000-4000-8000-000000000004','AM-4','81111111-0000-4000-8000-000000000001',
        'Por La Pagina','3300000004','confirmada','suelta','web',
        '83333333-0000-4000-8000-000000000001', now());

select chk('la de la pagina no entra en a_mano', (caja(hoy())->'entradas'->>'a_mano_n')::int, 2);
select chk('y si en la casilla de pagina',
  (caja(hoy())->'entradas'->>'pagina_transferencia_cop')::int, 15000);

\echo ''
\echo '-- Una reserva de recepcion CANCELADA no cuenta -----------------------'
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo, origen, created_at)
values ('82222222-0000-4000-8000-000000000005','AM-5','81111111-0000-4000-8000-000000000001',
        'Se Cancelo','3300000005','expirada','suelta','recepcion', now());
select chk('solo cuentan las confirmadas', (caja(hoy())->'entradas'->>'a_mano_n')::int, 2);

\echo ''
\echo '-- El total de clase suelta suma las cuatro casillas ------------------'
select chk('efectivo + recepcion_tr + pagina + a_mano = $60.000',
  (caja(hoy())->'entradas'->>'efectivo_cop')::int
  + (caja(hoy())->'entradas'->>'recepcion_transferencia_cop')::int
  + (caja(hoy())->'entradas'->>'pagina_transferencia_cop')::int
  + (caja(hoy())->'entradas'->>'a_mano_cop')::int, 60000);

\echo ''
select case when count(*) = 0 then 'todo en verde'
            else count(*) || ' FALLOS' end as resultado from fallos;
select * from fallos;
