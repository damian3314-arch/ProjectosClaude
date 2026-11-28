-- ---------------------------------------------------------------------
-- Cruzar la reserva que no alcanzó a avisar el pago — humo (0055)
--
-- El caso real, con el chat de la clienta como prueba: "reservé dos
-- cupos para las 8 am / pero se me salió de la página / y no pude
-- terminar". Reservaron a las 15:52, transfirieron $30.000 a las 15:58 y
-- la reserva expiraba a las 16:22. La plata estaba en el banco, con el
-- nombre y el monto exactos, dentro de la ventana — y el sistema no la
-- miró, porque solo conciliaba reservas donde alguien ya había pulsado
-- "ya pagué".
--
-- Lo que esta prueba defiende, además del caso feliz, es la frontera:
-- una reserva ya vencida NO se revive. Ahí el cupo pudo soltarse y
-- venderse a otra persona, y confirmarla sería sobrevender.
-- ---------------------------------------------------------------------
\set ON_ERROR_STOP on
set client_min_messages = notice;

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

create or replace function hoy() returns date language sql stable as
  $$ select (now() at time zone 'America/Bogota')::date $$;
update ajustes set valor = (hoy() - 60)::text where clave = 'inicio_produccion';

insert into clases (id, nombre, profesor, fecha_hora, cupo_total, precio_cop)
values ('91111111-0000-4000-8000-000000000001','Clase de manana','Prof',
        (hoy() + 1 + time '08:00') at time zone 'America/Bogota', 30, 15000);

\echo ''
\echo '-- Se le salio la pagina: dos cupos, en pendiente_pago, y pagaron --------'
-- Es el caso de Duvis y Laury. Nunca pulsaron "ya pagué", así que la
-- reserva se quedó en pendiente_pago; el depósito llegó seis minutos
-- después, dentro de su ventana.
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo, origen,
                      grupo_id, created_at, expira_en)
values ('92222222-0000-4000-8000-000000000001','PP-1','91111111-0000-4000-8000-000000000001',
        'Duvis pena','3400000001','pendiente_pago','suelta','web',
        '92222222-0000-4000-8000-000000000001', now() - interval '6 minutes',
        now() + interval '24 minutes'),
       ('92222222-0000-4000-8000-000000000002','PP-2','91111111-0000-4000-8000-000000000001',
        'Laury gomez','3400000002','pendiente_pago','suelta','web',
        '92222222-0000-4000-8000-000000000001', now() - interval '6 minutes',
        now() + interval '24 minutes');

insert into pagos (id, banco, valor_cop, fecha_pago, remitente, referencia, hoja_fila)
values ('93333333-0000-4000-8000-000000000001','Bancolombia',30000,
        now() - interval '1 minute','DUVIS ROCIO PEA','1096803067','g-pp-1');

select chk('el barrido la cruza sola',
  (conciliar_pendientes()->>'cruzadas')::int, 1);
select chk('y quedan las dos confirmadas',
  (select count(*)::int from reservas
    where grupo_id = '92222222-0000-4000-8000-000000000001' and estado='confirmada'), 2);
select chk('las dos con su deposito',
  (select count(distinct pago_id)::int from reservas
    where grupo_id = '92222222-0000-4000-8000-000000000001'), 1);
select chk('y el deposito queda consumido',
  (select consumido from pagos where id='93333333-0000-4000-8000-000000000001'), true);

\echo ''
\echo '-- FRONTERA: una ya vencida NO se revive --------------------------------'
-- El cupo ya se pudo soltar y vender a otra persona. Confirmarla seria
-- sobrevender, asi que se deja para la cola humana.
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo, origen,
                      created_at, expira_en)
values ('92222222-0000-4000-8000-000000000003','PP-3','91111111-0000-4000-8000-000000000001',
        'Tarde Vencida','3400000003','pendiente_pago','suelta','web',
        now() - interval '2 hours', now() - interval '90 minutes');
insert into pagos (id, banco, valor_cop, fecha_pago, remitente, referencia, hoja_fila)
values ('93333333-0000-4000-8000-000000000002','Bancolombia',15000,
        now() - interval '100 minutes','TARDE VENCIDA','1096803067','g-pp-2');

select chk('la vencida no se cruza', (conciliar_pendientes()->>'cruzadas')::int, 0);
select chk('sigue en pendiente_pago',
  (select estado::text from reservas where id='92222222-0000-4000-8000-000000000003'),
  'pendiente_pago');
select chk('y su deposito sigue libre',
  (select consumido from pagos where id='93333333-0000-4000-8000-000000000002'), false);

\echo ''
\echo '-- Con dos depositos iguales, el nombre desempata -----------------------'
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo, origen,
                      created_at, expira_en)
values ('92222222-0000-4000-8000-000000000004','PP-4','91111111-0000-4000-8000-000000000001',
        'Wendy Agresot','3400000004','pendiente_pago','suelta','web',
        now() - interval '5 minutes', now() + interval '25 minutes');
insert into pagos (id, banco, valor_cop, fecha_pago, remitente, referencia, hoja_fila) values
  ('93333333-0000-4000-8000-000000000003','Bancolombia',15000,
   now() - interval '2 minutes','WENDY AGRESOT GOMEZ','1096803067','g-pp-3'),
  ('93333333-0000-4000-8000-000000000004','Bancolombia',15000,
   now() - interval '3 minutes','OTRA PERSONA DISTINTA','1096803067','g-pp-4');

select chk('se cruza con el del nombre parecido',
  (conciliar_pendientes()->>'cruzadas')::int, 1);
select chk('y es el correcto, no el otro',
  (select pago_id from reservas where id='92222222-0000-4000-8000-000000000004'),
  '93333333-0000-4000-8000-000000000003'::uuid);
select chk('el ajeno sigue libre',
  (select consumido from pagos where id='93333333-0000-4000-8000-000000000004'), false);

\echo ''
\echo '-- Sin nombre que desempate, se deja para la cola humana ----------------'
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo, origen,
                      created_at, expira_en)
values ('92222222-0000-4000-8000-000000000005','PP-5','91111111-0000-4000-8000-000000000001',
        'Nadie Parecido','3400000005','pendiente_pago','suelta','web',
        now() - interval '5 minutes', now() + interval '25 minutes');
insert into pagos (id, banco, valor_cop, fecha_pago, remitente, referencia, hoja_fila) values
  ('93333333-0000-4000-8000-000000000005','Bancolombia',17000,
   now() - interval '2 minutes','AJENO UNO','1096803067','g-pp-5'),
  ('93333333-0000-4000-8000-000000000006','Bancolombia',17000,
   now() - interval '3 minutes','AJENO DOS','1096803067','g-pp-6');
update clases set precio_cop = 17000 where id='91111111-0000-4000-8000-000000000001';

select chk('con dos ajenos iguales no adivina',
  (conciliar_pendientes()->>'cruzadas')::int, 0);
select chk('la reserva se queda esperando',
  (select estado::text from reservas where id='92222222-0000-4000-8000-000000000005'),
  'pendiente_pago');

\echo ''
select case when count(*) = 0 then 'todo en verde'
            else count(*) || ' FALLOS' end as resultado from fallos;
select * from fallos;
