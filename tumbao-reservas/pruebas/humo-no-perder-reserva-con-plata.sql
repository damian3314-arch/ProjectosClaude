-- Humo de 0050: una reserva con plata real cerca no debe perderse, ni
-- al vencer ni al intentar recuperarla. Reproduce el incidente real de
-- Ludys Herazo de punta a punta, más los casos límite que ese incidente
-- dejó ver (cupo lleno al recuperar, y el bug de admin_rechazar).
\set ON_ERROR_STOP on
begin;

select (crear_token_admin('prueba-0050')->>'token') as v_token \gset

-- ═══ Caso 1: con plata cerca, NUNCA debería llegar a vencer ═══
insert into clases (id, nombre, profesor, fecha_hora, duracion_min, cupo_total, precio_cop, lugar, activa)
values ('a0000000-0000-0000-0000-000000000001', 'Salsa Suelta', 'Kevin',
        now() + interval '1 day', 60, 15, 15000, 'Sede Tumbao', true);

insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo,
                       origen, created_at, expira_en)
values ('a0000000-0000-0000-0000-000000000002', 'PRU001',
        'a0000000-0000-0000-0000-000000000001', 'Caso Uno', '3000000001',
        'pendiente_pago', 'suelta', 'formulario',
        now() - interval '20 minutes', now() - interval '5 minutes');
update clases set cupo_tomado = 1 where id = 'a0000000-0000-0000-0000-000000000001';

insert into pagos (id, banco, valor_cop, fecha_pago, referencia, remitente, ultimos_4, consumido)
values ('a0000000-0000-0000-0000-000000000003', 'bancolombia', 15000,
        now() - interval '18 minutes', '111', 'CASO UNO', '0001', false);

select liberar_cupos_de_clase('a0000000-0000-0000-0000-000000000001') as sueltos;
\echo '--- 1a. no debia vencer (0 sueltos), sigue pendiente_pago, cupo sigue en 1 ---'
select estado from reservas where codigo = 'PRU001';
select cupo_tomado from clases where id = 'a0000000-0000-0000-0000-000000000001';

\echo '--- 1b. y ya sale en la cola, marcada sin_aviso, NO vencida ---'
select (admin_pendientes(:'v_token')->'reservas'->0->>'codigo') as codigo,
       (admin_pendientes(:'v_token')->'reservas'->0->>'sin_aviso') as sin_aviso,
       (admin_pendientes(:'v_token')->'reservas'->0->>'vencida') as vencida;

-- ═══ Caso 2: SIN plata cerca, debe seguir venciendo normal (regresión) ═══
insert into clases (id, nombre, profesor, fecha_hora, duracion_min, cupo_total, precio_cop, lugar, activa)
values ('b0000000-0000-0000-0000-000000000001', 'Bachata Suelta', 'Laura',
        now() + interval '1 day', 60, 15, 15000, 'Sede Tumbao', true);
-- OJO: created_at bien lejos en el tiempo de los otros casos, para que
-- la ventana de -2h/+3h de este caso no se cruce con la plata de otro
-- caso de esta misma prueba y el resultado no dependa de en qué orden
-- ni qué tan rápido corran los inserts.
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo,
                       origen, created_at, expira_en)
values ('b0000000-0000-0000-0000-000000000002', 'PRU002',
        'b0000000-0000-0000-0000-000000000001', 'Caso Dos', '3000000002',
        'pendiente_pago', 'suelta', 'formulario',
        now() - interval '10 days', now() - interval '10 days' + interval '15 minutes');
update clases set cupo_tomado = 1 where id = 'b0000000-0000-0000-0000-000000000001';

select liberar_cupos_de_clase('b0000000-0000-0000-0000-000000000001') as sueltos;
\echo '--- 2. SIN plata cerca, debe vencer normal (1 suelto), cupo vuelve a 0 ---'
select estado from reservas where codigo = 'PRU002';
select cupo_tomado from clases where id = 'b0000000-0000-0000-0000-000000000001';

-- ═══ Caso 3: ya vencida (por lo que sea) + plata cerca + hay cupo → se confirma retomando el cupo ═══
insert into clases (id, nombre, profesor, fecha_hora, duracion_min, cupo_total, precio_cop, lugar, activa)
values ('c0000000-0000-0000-0000-000000000001', 'Salsa Suelta', 'Kevin',
        now() + interval '1 day', 60, 15, 15000, 'Sede Tumbao', true);
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo, origen, created_at)
values ('c0000000-0000-0000-0000-000000000002', 'PRU003',
        'c0000000-0000-0000-0000-000000000001', 'Caso Tres', '3000000003',
        'expirada', 'suelta', 'formulario', now() - interval '30 minutes');
-- cupo_tomado se quedó en 0: ya se había soltado al vencer.
insert into pagos (id, banco, valor_cop, fecha_pago, referencia, remitente, ultimos_4, consumido)
values ('c0000000-0000-0000-0000-000000000003', 'bancolombia', 15000,
        now() - interval '28 minutes', '333', 'CASO TRES', '0003', false);

\echo '--- 3a. sale en la cola marcada vencida, con cupo_libre ---'
select (admin_pendientes(:'v_token')->'reservas'->0->>'sin_aviso') as sin_aviso,
       (admin_pendientes(:'v_token')->'reservas'->0->>'vencida') as vencida,
       (admin_pendientes(:'v_token')->'reservas'->0->>'cupo_libre') as cupo_libre;

\echo '--- 3b. Es este (con pago_id): retoma el cupo, queda confirmada ---'
select jsonb_pretty(admin_confirmar(:'v_token', 'PRU003', 'c0000000-0000-0000-0000-000000000003')) as respuesta;
select estado, pago_id from reservas where codigo = 'PRU003';
select cupo_tomado, cupo_total from clases where id = 'c0000000-0000-0000-0000-000000000001';
select consumido from pagos where id = 'c0000000-0000-0000-0000-000000000003';

-- ═══ Caso 4: vencida, pero la clase ya se llenó de verdad → CUPO_LLENO, no sobrevende ═══
insert into clases (id, nombre, profesor, fecha_hora, duracion_min, cupo_total, precio_cop, lugar, activa)
values ('d0000000-0000-0000-0000-000000000001', 'Salsa Suelta llena', 'Kevin',
        now() + interval '1 day', 60, 1, 15000, 'Sede Tumbao', true);
-- Otra persona sí tomó el único cupo después.
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo, origen, created_at)
values ('d0000000-0000-0000-0000-000000000004', 'PRU004B',
        'd0000000-0000-0000-0000-000000000001', 'La que si pago', '3000000009',
        'confirmada', 'suelta', 'formulario', now());
update clases set cupo_tomado = 1 where id = 'd0000000-0000-0000-0000-000000000001';

insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo, origen, created_at)
values ('d0000000-0000-0000-0000-000000000002', 'PRU004',
        'd0000000-0000-0000-0000-000000000001', 'Caso Cuatro', '3000000004',
        'expirada', 'suelta', 'formulario', now() - interval '30 minutes');
insert into pagos (id, banco, valor_cop, fecha_pago, referencia, remitente, ultimos_4, consumido)
values ('d0000000-0000-0000-0000-000000000003', 'bancolombia', 15000,
        now() - interval '28 minutes', '444', 'CASO CUATRO', '0004', false);

\echo '--- 4. la clase ya esta llena: CUPO_LLENO, no toca nada ---'
select jsonb_pretty(admin_confirmar(:'v_token', 'PRU004', 'd0000000-0000-0000-0000-000000000003')) as respuesta;
select estado from reservas where codigo = 'PRU004';
select cupo_tomado, cupo_total from clases where id = 'd0000000-0000-0000-0000-000000000001';
select consumido from pagos where id = 'd0000000-0000-0000-0000-000000000003';

-- ═══ Caso 5: el bug de admin_rechazar — rechazar una vencida no debe restar cupo de más ═══
insert into clases (id, nombre, profesor, fecha_hora, duracion_min, cupo_total, precio_cop, lugar, activa)
values ('e0000000-0000-0000-0000-000000000001', 'Salsa Suelta', 'Kevin',
        now() + interval '1 day', 60, 15, 15000, 'Sede Tumbao', true);
update clases set cupo_tomado = 3 where id = 'e0000000-0000-0000-0000-000000000001';
-- Una reserva de verdad activa (SI tiene el cupo tomado)...
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo, origen, created_at)
values ('e0000000-0000-0000-0000-000000000002', 'PRU005',
        'e0000000-0000-0000-0000-000000000001', 'Caso Cinco', '3000000005',
        'pendiente_validacion', 'suelta', 'formulario', now());
-- ...y una YA vencida de otra persona (NO tiene cupo tomado, ya se soltó).
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo, origen, created_at)
values ('e0000000-0000-0000-0000-000000000003', 'PRU006',
        'e0000000-0000-0000-0000-000000000001', 'Caso Seis', '3000000006',
        'expirada', 'suelta', 'formulario', now() - interval '1 hour');

select jsonb_pretty(admin_rechazar(:'v_token', 'PRU005')) as respuesta;
\echo '--- 5a. rechazar una pendiente de verdad SI resta su cupo: 3 -> 2 ---'
select cupo_tomado from clases where id = 'e0000000-0000-0000-0000-000000000001';

select jsonb_pretty(admin_rechazar(:'v_token', 'PRU006')) as respuesta;
\echo '--- 5b. rechazar una YA vencida NO resta nada mas: sigue en 2, no baja a 1 ---'
select cupo_tomado from clases where id = 'e0000000-0000-0000-0000-000000000001';

rollback;
