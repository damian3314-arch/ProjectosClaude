-- ---------------------------------------------------------------------
-- Conciliar depósito por depósito — prueba de humo
--
-- EL CASO QUE MANDA
-- Transfiere el 3, llega el 5. Es lo que rompía el diseño anterior: la
-- resta día contra día daba negativo el 5 y gritaba "comprobante falso"
-- por algo perfectamente normal. Aquí se comprueba que el depósito del
-- 3 sigue disponible el 5, que la cajera lo puede adjudicar, y que
-- después de hacerlo no queda ninguna alarma encendida.
--
-- Lo demás que se comprueba:
--   · un depósito no se puede adjudicar dos veces
--   · el valor tiene que ser el del banco, no el que se tecleó
--   · anular devuelve el depósito a la lista
--   · una transferencia sin enlazar se cuenta aparte (Nequi, otra cuenta)
--   · lo que ya casó solo con una reserva no aparece como libre
--
-- Ojo: en Postgres `null <> 0` no es true, así que un dato nulo pasaría
-- de largo dando verde falso. Todo va con IS DISTINCT FROM.
--
--   psql -d t27 -f humo-banco.sql
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
create or replace function tk() returns text language sql stable as
  $$ select token from ctx $$;
create or replace function dia() returns jsonb language sql stable as
  $$ select caja_del_dia(tk()) $$;
create or replace function bco(k text) returns int language sql stable as
  $$ select (dia()->'banco'->>k)::int $$;

-- El corte de producción (0029) esconde del inventario todo depósito
-- anterior al estreno, y por defecto el estreno es hoy. Esta prueba usa
-- depósitos de hace días a propósito —el caso del lunes que aparece el
-- miércoles— así que se retrasa el corte. Sin esto los 8 casos de fecha
-- pasada dan cero, que es lo correcto pero no es lo que se mide aquí.
update ajustes set valor = ((now() at time zone 'America/Bogota')::date - 60)::text
 where clave = 'inicio_produccion';

insert into clases (id, nombre, profesor, fecha_hora, cupo_total, precio_cop)
values ('aaaaaaaa-0000-4000-8000-000000000001', 'Salsa hoy', 'Prof',
        (((now() at time zone 'America/Bogota')::date + time '18:00')
          at time zone 'America/Bogota'), 20, 15000);

\echo ''
\echo '-- 1. El depósito de hace dos días sigue estando ---------------------'

-- Camila transfirió el 3 y aparece el 5. Nadie ha reclamado esa plata.
insert into pagos (id, banco, valor_cop, fecha_pago, referencia, remitente, consumido)
values ('bbbbbbbb-0000-4000-8000-000000000001', 'bancolombia', 15000,
        now() - interval '2 days', 'REF-CAMILA', 'CAMILA ROJAS', false);

select chk('sale en la lista de libres',
  (select count(*)::int from jsonb_array_elements(dia()->'pagos_libres') e
    where e->>'id' = 'bbbbbbbb-0000-4000-8000-000000000001'), 1);
select chk('la lista dice de cuántos días es',
  (select (e->>'dias')::int from jsonb_array_elements(dia()->'pagos_libres') e
    where e->>'id' = 'bbbbbbbb-0000-4000-8000-000000000001'), 2);
select chk('el inventario libre son 15.000', bco('libre_cop'), 15000);
select chk('y es un solo depósito', bco('libre_n'), 1);
-- Lo que el diseño viejo hacía mal: hoy el banco no recibió nada, y eso
-- no significa absolutamente nada.
select chk('el banco no recibió nada HOY, y da igual', bco('recibido_cop'), 0);

\echo ''
\echo '-- 2. La cajera lo adjudica al cobrar --------------------------------'

select chk('adjudicar sale bien',
  (caja_registrar(tk(), 'ingreso', 'clase_suelta', 15000, 'transferencia',
                  'llegó hoy, transfirió el lunes',
                  'bbbbbbbb-0000-4000-8000-000000000001')->>'ok')::boolean, true);

select chk('el depósito desaparece de los libres', bco('libre_cop'), 0);
select chk('no queda nada sin respaldo', bco('sin_respaldo_cop'), 0);
select chk('el movimiento queda marcado como respaldado',
  (select (e->>'con_banco')::boolean from jsonb_array_elements(dia()->'movimientos') e
    limit 1), true);
-- Y la conciliación automática ya no puede tocarlo.
select chk('el pago queda consumido',
  (select consumido from pagos where id = 'bbbbbbbb-0000-4000-8000-000000000001'), true);

\echo ''
\echo '-- 3. Lo que no se puede hacer ---------------------------------------'

insert into pagos (id, banco, valor_cop, fecha_pago, remitente, consumido)
values ('bbbbbbbb-0000-4000-8000-000000000002', 'bancolombia', 125000,
        now() - interval '1 hour', 'LUIS PEREZ', false);

select chk('no se adjudica un depósito ya usado',
  caja_registrar(tk(), 'ingreso', 'clase_suelta', 15000, 'transferencia', null,
                 'bbbbbbbb-0000-4000-8000-000000000001')->>'error', 'PAGO_YA_USADO');
-- Antes, cualquier valor distinto al del depósito se rechazaba: si no
-- calzaba, era que se había escogido el depósito equivocado.
--
-- Desde la 0039 eso ya no es cierto por arriba NI por abajo. Un depósito
-- de $30.000 puede pagar dos clases de $15.000, asi que un valor MENOR
-- es legítimo. Lo que sigue siendo imposible es sacar más de lo que hay:
-- ese es el limite que cuida la plata, y ahora es sobre el saldo, no
-- sobre el valor original.
--
-- El cuidado de "¿escogiste el depósito correcto?" se mudó a la
-- pantalla, que dice cuánto vale el depósito y cuánto va a quedar. Ver
-- prueba-caja.
select chk('no se puede sacar más de lo que tiene el depósito',
  caja_registrar(tk(), 'ingreso', 'mensualidad', 130000, 'transferencia', null,
                 'bbbbbbbb-0000-4000-8000-000000000002')->>'error', 'VALOR_NO_COINCIDE');
select chk('un egreso no puede enlazarse a un depósito',
  caja_registrar(tk(), 'egreso', 'profesores', 125000, 'transferencia', null,
                 'bbbbbbbb-0000-4000-8000-000000000002')->>'error', 'ENLACE_NO_APLICA');
select chk('el efectivo tampoco',
  caja_registrar(tk(), 'ingreso', 'mensualidad', 125000, 'efectivo', null,
                 'bbbbbbbb-0000-4000-8000-000000000002')->>'error', 'ENLACE_NO_APLICA');
select chk('tras los rechazos el depósito sigue libre', bco('libre_cop'), 125000);

\echo ''
\echo '-- 4. Transferencia sin depósito: se cuenta aparte, no grita ---------'
-- Nequi, otra cuenta, o un comprobante que no era real. La pantalla no
-- puede distinguirlos, así que los muestra y no acusa a nadie.

select caja_registrar(tk(), 'ingreso', 'clase_suelta', 15000, 'transferencia',
                      'dice que pagó por Nequi', null);

select chk('queda contada como sin respaldo', bco('sin_respaldo_cop'), 15000);
select chk('y se sabe cuántas son', bco('sin_respaldo_n'), 1);
select chk('no toca el inventario de libres', bco('libre_cop'), 125000);

\echo ''
\echo '-- 5. Anular devuelve el depósito a la lista -------------------------'

select caja_registrar(tk(), 'ingreso', 'mensualidad', 125000, 'transferencia', null,
                      'bbbbbbbb-0000-4000-8000-000000000002');
select chk('al adjudicarlo, el inventario baja a cero', bco('libre_cop'), 0);

select chk('anular funciona',
  (caja_anular(tk(), (select id from caja_movimientos
                       where pago_id = 'bbbbbbbb-0000-4000-8000-000000000002'))
   ->>'libero_pago')::boolean, true);
select chk('y el depósito vuelve a estar libre', bco('libre_cop'), 125000);
select chk('se puede volver a adjudicar',
  (caja_registrar(tk(), 'ingreso', 'mensualidad', 125000, 'transferencia', null,
                  'bbbbbbbb-0000-4000-8000-000000000002')->>'ok')::boolean, true);

\echo ''
\echo '-- 6. Lo que casó solo con una reserva no sale como libre ------------'

insert into pagos (id, banco, valor_cop, fecha_pago, remitente, consumido)
values ('bbbbbbbb-0000-4000-8000-000000000003', 'bancolombia', 15000,
        now() - interval '3 hours', 'PAGO WEB', true);
insert into reservas (codigo, clase_id, nombre, telefono, estado, tipo, pago_id)
values ('TB-0003', 'aaaaaaaa-0000-4000-8000-000000000001', 'Pago Web',
        '3001112233', 'confirmada', 'suelta', 'bbbbbbbb-0000-4000-8000-000000000003');

select chk('la reserva de la página no aparece como libre', bco('libre_cop'), 0);
select chk('pero sí cuenta como recibido hoy', bco('recibido_cop'), 15000 + 125000);

\echo ''
\echo '-- 7. Muy viejo deja de ofrecerse -----------------------------------'
-- La ventana son 20 días. Sin tope, la lista se vuelve un basurero y la
-- cajera escoge cualquier cosa con tal de que el valor coincida.

insert into pagos (banco, valor_cop, fecha_pago, remitente, consumido)
values ('bancolombia', 777000, now() - interval '40 days', 'MUY VIEJO', false);

select chk('un depósito de hace 40 días no se ofrece', bco('libre_cop'), 0);
select chk('la pantalla dice cuál es la ventana',
  (dia()->'banco'->>'ventana_dias')::int, 20);

\echo ''
\echo '-- 7b. La alarma es la de hoy; el arrastre va aparte ------------------'
-- En producción hay 75 depósitos sin reclamar de antes de que existiera
-- este módulo. Si el titular contara esos, la tarjeta viviría en ámbar
-- para siempre y dejaría de significar algo. Se separan.

-- Este es de hoy y nadie lo ha reclamado: eso sí exige buscar a alguien.
insert into pagos (banco, valor_cop, fecha_pago, remitente, consumido)
values ('bancolombia', 40000, now() - interval '30 minutes', 'DE HOY', false);
-- Y estos dos son la cola vieja.
insert into pagos (banco, valor_cop, fecha_pago, remitente, consumido)
values ('bancolombia', 300000, now() - interval '6 days',  'VIEJO 1', false),
       ('bancolombia', 200000, now() - interval '11 days', 'VIEJO 2', false);

select chk('lo sin identificar DE HOY son 40.000', bco('libre_hoy_cop'), 40000);
select chk('y es un solo depósito de hoy', bco('libre_hoy_n'), 1);
select chk('el arrastre viejo va aparte: 500.000', bco('atras_cop'), 500000);
select chk('y son dos depósitos viejos', bco('atras_n'), 2);
select chk('el inventario total sigue siendo la suma', bco('libre_cop'), 540000);
-- Los viejos siguen ofreciéndose para escoger: es lo que permite cobrar
-- el miércoles a quien transfirió el lunes.
select chk('los viejos siguen en la lista para escoger',
  (select count(*)::int from jsonb_array_elements(dia()->'pagos_libres')), 3);

\echo ''
\echo '-- 7c. El mes -------------------------------------------------------'
select chk('el mes suma lo que va del mes, no solo hoy',
  (bco('mes_cop') >= bco('recibido_cop')), true);

\echo ''
\echo '-- 8. Nada de esto impide cerrar el día ------------------------------'

select caja_cerrar(tk(), 100000, 100000, null, 100000);
select chk('cierra aunque haya cosas sin identificar',
  (dia()->>'cerrado')::boolean, true);
select chk('el arqueo lo sigue mandando el efectivo',
  (dia()->'cierre'->>'diferencia_cop')::int, 0);

\echo ''
select case when count(*) = 0 then 'todo en verde'
            else count(*) || ' FALLOS' end as resultado from fallos;
select * from fallos;
