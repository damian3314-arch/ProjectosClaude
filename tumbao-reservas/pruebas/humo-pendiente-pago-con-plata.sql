-- Humo de 0049: una reserva en pendiente_pago, con plata real sin
-- consumir cerca, tiene que salir en admin_pendientes() y dejarse
-- confirmar con "Confirmar igual" — el caso real de Ludys Herazo.
\set ON_ERROR_STOP on
begin;

\pset tuples_only off

-- Token de admin para las llamadas.
select (crear_token_admin('prueba-0049')->>'token') as v_token \gset

-- Una clase de suelta, mañana.
insert into clases (id, nombre, profesor, fecha_hora, duracion_min, cupo_total, precio_cop, lugar, activa)
values ('11111111-1111-1111-1111-111111111111', 'Salsa Suelta', 'Kevin',
        now() + interval '1 day', 60, 20, 15000, 'Sede Tumbao', true);

-- La reserva de "Ludys": pendiente_pago, nunca llego a verificando.
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo,
                       origen, created_at)
values ('22222222-2222-2222-2222-222222222222', 'F5CAUS',
        '11111111-1111-1111-1111-111111111111', 'Ludys Herazo', '3118708421',
        'pendiente_pago', 'suelta', 'formulario', now() - interval '5 minutes');

-- Su plata real, sin consumir, 4 minutos despues de la reserva.
insert into pagos (id, banco, valor_cop, fecha_pago, referencia, remitente, ultimos_4, consumido)
values ('33333333-3333-3333-3333-333333333333', 'bancolombia', 15000,
        now() - interval '1 minute', '1096803067', 'LUDYS MARIA HERAZO HERAZO',
        '4619', false);

\echo '--- 1. Antes de 0049 haria falta, aqui debe SALIR en admin_pendientes ---'
select jsonb_pretty(admin_pendientes(:'v_token')) as respuesta;

\echo '--- 2. Confirmar igual (el boton de siempre, pago_id null) ---'
select jsonb_pretty(admin_confirmar(:'v_token', 'F5CAUS', null)) as respuesta;

\echo '--- 3. Ya no debe salir en pendientes ---'
select jsonb_pretty(admin_pendientes(:'v_token')) as respuesta;

\echo '--- 4. Y debe quedar confirmada en reservas ---'
select codigo, nombre, estado from reservas where codigo = 'F5CAUS';

rollback;
