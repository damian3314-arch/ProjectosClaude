-- ---------------------------------------------------------------------
-- Varios cupos con un solo pago — prueba de humo
--
-- EL CASO QUE MANDA
-- Alguien reserva para seis y manda UN giro de $90.000. Hoy eso no cruza
-- con nada: el sistema busca $15.000. Y si cruzara mal, cinco personas
-- se quedarían sin cupo o entrarían seis pagando una.
--
-- Lo que se comprueba, en orden de lo que dolería:
--   · el aforo cuenta seis, no uno
--   · o entran los seis o no entra ninguno (nada de medio grupo)
--   · el banco busca 90.000 y confirma a los seis de una
--   · rechazar suelta los seis cupos
--   · la cola enseña UNA tarjeta, no seis
--   · una reserva sola sigue comportándose exactamente igual que antes
--
-- Ojo: en Postgres `null <> x` no es true, así que un dato nulo pasaría
-- de largo dando verde falso. Todo va con IS DISTINCT FROM.
--
--   psql -d <base> -f humo-grupo.sql
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
insert into ctx select crear_token_admin('recepcion de prueba')->>'token';
create or replace function tk() returns text language sql stable as $$ select token from ctx $$;
create or replace function cola() returns jsonb language sql stable as
  $$ select admin_pendientes(tk()) $$;

update ajustes set valor = ((now() at time zone 'America/Bogota')::date - 60)::text
 where clave = 'inicio_produccion';

insert into clases (id, nombre, profesor, fecha_hora, cupo_total, precio_cop)
-- Mañana, no hoy: corriendo esto después de las 6 de la tarde la clase
-- ya habría pasado y todo fallaría con CLASE_YA_PASO, que no es lo que
-- se está midiendo.
values ('eeeeeeee-0000-4000-8000-000000000001', 'Salsa de mañana', 'Prof',
        (((now() at time zone 'America/Bogota')::date + 1 + time '18:00')
          at time zone 'America/Bogota'), 10, 15000);

create temp table cods (k text primary key, cod text);

create or replace function limpiar() returns void language plpgsql as $$
begin
  delete from reservas where true;
  delete from pagos where true;
  update clases set cupo_tomado = 0 where true;
end $$;

create or replace function tomadas() returns int language sql stable as
  $$ select cupo_tomado from clases where id = 'eeeeeeee-0000-4000-8000-000000000001' $$;


\echo ''
\echo '-- 1. Seis cupos ocupan seis, no uno ---------------------------------'

do $$
declare v_r jsonb;
begin
  perform limpiar();
  select tomar_cupos('eeeeeeee-0000-4000-8000-000000000001',
    array['Ana Perez','Beto Perez','Caro Perez','Dani Perez','Eva Perez','Fabio Perez'],
    '3001110001', null, 'web') into v_r;
  delete from cods where k in ('g6','g6ok','g6tot','g6n');
  insert into cods values ('g6',    v_r->>'codigo'),
                          ('g6ok',  v_r->>'ok'),
                          ('g6tot', v_r->>'total_cop'),
                          ('g6n',   v_r->>'cupos');
end $$;

select chk('la reserva de seis sale bien',  (select cod from cods where k='g6ok'),  'true');
select chk('dice que son seis',             (select cod from cods where k='g6n'),   '6');
select chk('y que hay que pagar 90.000',    (select cod from cods where k='g6tot'), '90000');
select chk('el aforo cuenta seis', tomadas(), 6);
select chk('se crearon seis filas', (select count(*)::int from reservas), 6);
select chk('las seis comparten grupo',
  (select count(distinct coalesce(grupo_id, id))::int from reservas), 1);
select chk('cada una con su nombre',
  (select count(distinct nombre)::int from reservas), 6);
select chk('y un solo celular',
  (select count(distinct telefono)::int from reservas), 1);
select chk('el precio del grupo son 90.000',
  precio_del_grupo((select id from reservas where grupo_id = id)), 90000);


\echo ''
\echo '-- 2. O entran todos, o no entra ninguno -----------------------------'
-- Con cuatro libres y seis pidiendo, lo peor posible sería meter cuatro
-- y dejar dos afuera con el pago hecho.

do $$
begin
  perform limpiar();
  update clases set cupo_tomado = 6
   where id = 'eeeeeeee-0000-4000-8000-000000000001';   -- quedan 4 de 10
end $$;

select chk('no mete medio grupo',
  tomar_cupos('eeeeeeee-0000-4000-8000-000000000001',
    array['A A','B B','C C','D D','E E','F F'], '3001110002', null, 'web')->>'error',
  'NO_CABEN_TANTOS');
select chk('y lo dice con números',
  tomar_cupos('eeeeeeee-0000-4000-8000-000000000001',
    array['A A','B B','C C','D D','E E','F F'], '3001110002', null, 'web')->>'libres', '4');
select chk('no ocupó nada al fallar', tomadas(), 6);
select chk('los cuatro que sí caben, entran',
  (tomar_cupos('eeeeeeee-0000-4000-8000-000000000001',
    array['A A','B B','C C','D D'], '3001110003', null, 'web')->>'ok')::boolean, true);
select chk('y ahora la clase está llena', tomadas(), 10);


\echo ''
\echo '-- 3. Un cero de más en el contador no se lleva la clase -------------'

select chk('más de ocho no',
  tomar_cupos('eeeeeeee-0000-4000-8000-000000000001',
    array['a a','b b','c c','d d','e e','f f','g g','h h','i i'],
    '3001110004', null, 'web')->>'error', 'CANTIDAD_INVALIDA');
select chk('cero tampoco',
  tomar_cupos('eeeeeeee-0000-4000-8000-000000000001',
    array[]::text[], '3001110004', null, 'web')->>'error', 'CANTIDAD_INVALIDA');
select chk('un nombre en blanco se frena antes de ocupar nada',
  tomar_cupos('eeeeeeee-0000-4000-8000-000000000001',
    array['Ana Perez','','Caro Perez'], '3001110004', null, 'web')->>'error', 'FALTA_NOMBRE');


\echo ''
\echo '-- 4. EL CASO: un giro de 90.000 confirma a los seis -----------------'

do $$
declare v_r jsonb;
begin
  perform limpiar();
  select tomar_cupos('eeeeeeee-0000-4000-8000-000000000001',
    array['Ana Perez','Beto Perez','Caro Perez','Dani Perez','Eva Perez','Fabio Perez'],
    '3001110005', null, 'web') into v_r;
  delete from cods where k = 'g4';
  insert into cods values ('g4', v_r->>'codigo');
  -- El correo del banco entra antes de que termine de llenar el formulario.
  perform registrar_pago_y_conciliar('bancolombia', 90000, now() - interval '3 minutes',
    'LLAVE', 'ANA PEREZ', null, 1.0, null, 'correo-g');
end $$;

select chk('el correo por sí solo no casa con una reserva de 15.000',
  (select consumido from pagos limit 1), false);

select chk('al decir "ya pagué" se confirma el grupo',
  registrar_aviso_pago((select cod from cods where k='g4'), now() - interval '3 minutes',
                       'REF-G', null, null)->>'estado',
  'confirmada');
select chk('las seis quedan confirmadas',
  (select count(*)::int from reservas where estado = 'confirmada'), 6);
select chk('las seis apuntan al mismo depósito',
  (select count(distinct pago_id)::int from reservas where pago_id is not null), 1);
select chk('y el depósito quedó usado', (select consumido from pagos limit 1), true);
select chk('el aforo sigue en seis', tomadas(), 6);
select chk('la cola queda vacía', (select jsonb_array_length(cola()->'reservas')), 0);


\echo ''
\echo '-- 5. Un pago de 15.000 NO confirma un grupo de seis -----------------'
-- Sería lo peor: seis entrando por el precio de una.

do $$
declare v_r jsonb;
begin
  perform limpiar();
  select tomar_cupos('eeeeeeee-0000-4000-8000-000000000001',
    array['Ana Perez','Beto Perez','Caro Perez','Dani Perez','Eva Perez','Fabio Perez'],
    '3001110006', null, 'web') into v_r;
  delete from cods where k = 'g5';
  insert into cods values ('g5', v_r->>'codigo');
  insert into pagos (banco, valor_cop, fecha_pago, referencia, remitente, consumido)
  values ('bancolombia', 15000, now() - interval '2 minutes', 'L', 'ANA PEREZ', false);
end $$;

select chk('un pago de una clase no confirma seis',
  registrar_aviso_pago((select cod from cods where k='g5'), now() - interval '2 minutes',
                       'REF-G5', null, null)->>'estado',
  'verificando');
select chk('el depósito de 15.000 sigue libre',
  (select consumido from pagos limit 1), false);
select chk('sale en la cola como que NO cuadra',
  (select (cola()->'reservas'->0->'pagos_sueltos'->0->>'cuadra')::boolean), false);
select chk('y la tarjeta dice el precio del grupo, no el de una clase',
  (select (cola()->'reservas'->0->>'precio_cop')::int), 90000);


\echo ''
\echo '-- 6. La cola enseña UNA tarjeta, no seis ---------------------------'

select chk('una sola tarjeta', (select jsonb_array_length(cola()->'reservas')), 1);
select chk('que dice que son seis',
  (select (cola()->'reservas'->0->>'cupos')::int), 6);
select chk('con los nombres de los otros cinco',
  (select jsonb_array_length(cola()->'reservas'->0->'acompanantes')), 5);


\echo ''
\echo '-- 7. Rechazar suelta los seis cupos ---------------------------------'

select chk('rechaza el grupo entero',
  (admin_rechazar(tk(), (select cod from cods where k='g5'))->>'cupos')::int, 6);
select chk('y la clase queda vacía otra vez', tomadas(), 0);
select chk('las seis quedaron rechazadas',
  (select count(*)::int from reservas where estado = 'rechazada'), 6);

select chk('deshacer las devuelve todas',
  (admin_deshacer(tk(), (select cod from cods where k='g5'))->>'cupos')::int, 6);
select chk('y el aforo vuelve a seis', tomadas(), 6);


\echo ''
\echo '-- 8. Confirmar a mano, con su depósito -----------------------------'

do $$
declare v_r jsonb;
begin
  perform limpiar();
  select tomar_cupos('eeeeeeee-0000-4000-8000-000000000001',
    array['Ana Perez','Beto Perez'], '3001110007', null, 'web') into v_r;
  delete from cods where k = 'g8';
  insert into cods values ('g8', v_r->>'codigo');
  update reservas set estado = 'pendiente_validacion' where true;
  insert into pagos (id, banco, valor_cop, fecha_pago, referencia, remitente, consumido)
  values ('ffffffff-0000-4000-8000-000000000001', 'bancolombia', 30000,
          now(), 'L', 'QUIEN SEA', false);
end $$;

select chk('confirma las dos de una',
  (admin_confirmar(tk(), (select cod from cods where k='g8'),
                   'ffffffff-0000-4000-8000-000000000001')->>'cupos')::int, 2);
select chk('las dos con el depósito puesto',
  (select count(*)::int from reservas where pago_id = 'ffffffff-0000-4000-8000-000000000001'), 2);
select chk('y el depósito quedó usado',
  (select consumido from pagos where id = 'ffffffff-0000-4000-8000-000000000001'), true);


\echo ''
\echo '-- 9. Una reserva sola no cambia en nada -----------------------------'
-- La mayoría de las reservas son de una persona. Si algo de esto tocara
-- ese camino, sería un cambio malo aunque los grupos funcionaran.

do $$
declare v_r jsonb;
begin
  perform limpiar();
  select tomar_cupos('eeeeeeee-0000-4000-8000-000000000001',
    array['Sola Solita'], '3001110008', null, 'web') into v_r;
  delete from cods where k = 'g9';
  insert into cods values ('g9', v_r->>'codigo');
end $$;

select chk('una sola no es grupo', (select grupo_id from reservas limit 1), null::uuid);
select chk('ocupa un cupo', tomadas(), 1);
select chk('y su precio es el de la clase',
  precio_del_grupo((select id from reservas limit 1)), 15000);

do $$
begin
  insert into pagos (banco, valor_cop, fecha_pago, referencia, remitente, consumido)
  values ('bancolombia', 15000, now() - interval '2 minutes', 'L', 'SOLA SOLITA', false);
end $$;

select chk('cruza con su pago de 15.000 como siempre',
  registrar_aviso_pago((select cod from cods where k='g9'), now() - interval '2 minutes',
                       'REF-G9', null, null)->>'estado',
  'confirmada');


\echo ''
\echo '-- 10. Un mismo depósito no sirve para dos grupos --------------------'

do $$
declare v_a jsonb; v_b jsonb;
begin
  perform limpiar();
  select tomar_cupos('eeeeeeee-0000-4000-8000-000000000001',
    array['Uno Uno','Dos Dos'], '3001110009', null, 'web') into v_a;
  select tomar_cupos('eeeeeeee-0000-4000-8000-000000000001',
    array['Tres Tres','Cuatro Cuatro'], '3001110010', null, 'web') into v_b;
  delete from cods where k in ('gA','gB');
  insert into cods values ('gA', v_a->>'codigo'), ('gB', v_b->>'codigo');
  update reservas set estado = 'pendiente_validacion' where true;
  insert into pagos (id, banco, valor_cop, fecha_pago, referencia, remitente, consumido)
  values ('ffffffff-0000-4000-8000-000000000002', 'bancolombia', 30000,
          now(), 'L', 'QUIEN SEA', false);
end $$;

select chk('el primero se lo lleva',
  (admin_confirmar(tk(), (select cod from cods where k='gA'),
                   'ffffffff-0000-4000-8000-000000000002')->>'ok')::boolean, true);
select chk('el segundo no puede',
  admin_confirmar(tk(), (select cod from cods where k='gB'),
                  'ffffffff-0000-4000-8000-000000000002')->>'error', 'PAGO_YA_USADO');


\echo ''
select case when count(*) = 0 then 'todo en verde'
            else count(*) || ' FALLOS' end as resultado from fallos;
select * from fallos;
