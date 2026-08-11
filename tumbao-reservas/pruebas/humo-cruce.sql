-- ---------------------------------------------------------------------
-- Cruzar en las dos direcciones — prueba de humo
--
-- EL CASO QUE MANDA (caso 1)
-- Es lo que pasó de verdad el 11 de agosto, cuatro veces de cinco:
--
--   15:48  reserva
--   15:49  transfiere → el correo se procesa 15:50, y la reserva
--          todavía está en pendiente_pago, así que no es candidata
--   15:5x  da "ya pagué" — y nadie vuelve a mirar
--
-- Si el caso 1 falla, esta migración no sirve para nada.
--
-- Lo demás:
--   · la hora declarada puede estar torcida 18 minutos y aun así cruza
--   · dos depósitos empatados NO se adivinan
--   · uno que ya cobró la caja no se ofrece dos veces
--   · la cola enseña la plata que no casó con nadie
--
-- Ojo: en Postgres `null <> x` no es true, así que un dato nulo pasaría
-- de largo dando verde falso. Todo va con IS DISTINCT FROM.
--
--   psql -d <base> -f humo-cruce.sql
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

-- Depósitos de horas pasadas: sin retrasar el corte, el filtro de
-- producción los escondería y estaríamos midiendo otra cosa.
update ajustes set valor = ((now() at time zone 'America/Bogota')::date - 60)::text
 where clave = 'inicio_produccion';

insert into clases (id, nombre, profesor, fecha_hora, cupo_total, precio_cop)
values ('cccccccc-0000-4000-8000-000000000001', 'Salsa de esta noche', 'Prof',
        (((now() at time zone 'America/Bogota')::date + time '18:00')
          at time zone 'America/Bogota'), 30, 15000);

-- Los códigos de reserva viajan entre bloques. Una temp table normal:
-- con `on commit drop` desaparece al terminar cada sentencia, porque
-- psql va en autocommit y cada DO es su propia transacción.
create temp table cods (k text primary key, cod text);

create or replace function limpiar() returns void language plpgsql as $$
begin
  delete from reservas where true;
  delete from pagos where true;
  update clases set cupo_tomado = 0 where true;
end $$;


\echo ''
\echo '-- 1. LA CARRERA: el dinero llega antes que el "ya pagué" ------------'

do $$
declare v_a jsonb; v_r jsonb; v_cod text;
begin
  perform limpiar();
  -- 15:48 — toma el cupo. Queda en pendiente_pago.
  select tomar_cupo('cccccccc-0000-4000-8000-000000000001', 'Yiraudis Diaz',
                    '3001110001', null, 'web', 'suelta') into v_a;
  delete from cods where k = 't1';
  insert into cods values ('t1', v_a->>'codigo');
end $$;

select chk('la reserva arranca en pendiente_pago',
  (select estado::text from reservas limit 1), 'pendiente_pago');

-- 15:49 — transfiere. El correo entra un minuto después, cuando la
-- persona todavía está escribiendo la referencia en el celular.
select chk('el correo no encuentra a nadie (así era, y está bien)',
  registrar_pago_y_conciliar('bancolombia', 15000, now() - interval '4 minutes',
    'LLAVE', 'YIRAUDIS MILENA DIAZ VARGAS', null, 1.0, null, 'correo-1')->>'accion',
  'sin_reserva_que_casar');

-- 15:5x — da "ya pagué". ANTES: se quedaba en "verificando" para siempre.
select chk('al declarar el pago, se cruza sola',
  registrar_aviso_pago((select cod from cods where k = 't1'), now() - interval '4 minutes',
                       'M14153097', null, null)->>'estado',
  'confirmada');

select chk('y la reserva quedó amarrada al depósito',
  (select pago_id is not null from reservas limit 1), true);
select chk('el depósito quedó marcado como usado',
  (select consumido from pagos limit 1), true);
select chk('la cola de por validar queda vacía',
  (select jsonb_array_length(cola()->'reservas')), 0);


\echo ''
\echo '-- 2. La hora declarada puede estar torcida --------------------------'
-- El 11 de agosto una reserva declaró 15:52 y el depósito entró 16:10.
-- Dieciocho minutos. Con la ventana vieja de ±15 se perdía por tres.

do $$
declare v_a jsonb;
begin
  perform limpiar();
  select tomar_cupo('cccccccc-0000-4000-8000-000000000001', 'Johanna Diaz',
                    '3001110002', null, 'web', 'suelta') into v_a;
  delete from cods where k = 't2';
  insert into cods values ('t2', v_a->>'codigo');
  insert into pagos (banco, valor_cop, fecha_pago, referencia, remitente, consumido)
  values ('bancolombia', 15000, now(), 'LLAVE', 'DORIS JOHANNA DIAZ RUEDA', false);
end $$;

select chk('18 minutos de diferencia: cruza',
  registrar_aviso_pago((select cod from cods where k = 't2'), now() - interval '18 minutes',
                       'REF-2', null, null)->>'estado',
  'confirmada');

\echo ''
\echo '-- 3. Noventa minutos ya es demasiado -------------------------------'
-- No se adivina, pero tampoco se esconde: tiene que salir como candidato
-- en la cola para que alguien decida con los ojos.

do $$
declare v_a jsonb;
begin
  perform limpiar();
  select tomar_cupo('cccccccc-0000-4000-8000-000000000001', 'Lejana Perez',
                    '3001110003', null, 'web', 'suelta') into v_a;
  delete from cods where k = 't3';
  insert into cods values ('t3', v_a->>'codigo');
  insert into pagos (banco, valor_cop, fecha_pago, referencia, remitente, consumido)
  values ('bancolombia', 15000, now(), 'LLAVE', 'LEJANA PEREZ', false);
end $$;

select chk('a 90 minutos no se cruza sola',
  registrar_aviso_pago((select cod from cods where k = 't3'), now() - interval '90 minutes',
                       'REF-3', null, null)->>'estado',
  'verificando');
select chk('pero sí sale como candidato en la cola',
  (select jsonb_array_length(cola()->'reservas'->0->'pagos_sueltos')), 1);
select chk('marcado como que cuadra el valor',
  (select (cola()->'reservas'->0->'pagos_sueltos'->0->>'cuadra')::boolean), true);


\echo ''
\echo '-- 4. Dos depósitos empatados no se adivinan ------------------------'

do $$
declare v_a jsonb;
begin
  perform limpiar();
  select tomar_cupo('cccccccc-0000-4000-8000-000000000001', 'Ana Torres',
                    '3001110004', null, 'web', 'suelta') into v_a;
  delete from cods where k = 't4';
  insert into cods values ('t4', v_a->>'codigo');
  -- Ninguno se parece a "Ana Torres": los dos dan 0.
  insert into pagos (banco, valor_cop, fecha_pago, referencia, remitente, consumido)
  values ('bancolombia', 15000, now() - interval '3 minutes', 'L1', 'PEDRO GOMEZ', false),
         ('bancolombia', 15000, now() - interval '6 minutes', 'L2', 'LUIS PEÑA',  false);
end $$;

select chk('con dos iguales no se amarra ninguno',
  registrar_aviso_pago((select cod from cods where k = 't4'), now() - interval '4 minutes',
                       'REF-4', null, null)->>'estado',
  'verificando');
select chk('los dos quedan libres',
  (select count(*)::int from pagos where not consumido), 2);
select chk('y los dos se ofrecen en la cola',
  (select jsonb_array_length(cola()->'reservas'->0->'pagos_sueltos')), 2);


\echo ''
\echo '-- 5. Cuando un nombre gana claro, sí ------------------------------'

do $$
declare v_a jsonb;
begin
  perform limpiar();
  select tomar_cupo('cccccccc-0000-4000-8000-000000000001', 'Johanna Diaz',
                    '3001110005', null, 'web', 'suelta') into v_a;
  delete from cods where k = 't5';
  insert into cods values ('t5', v_a->>'codigo');
  insert into pagos (id, banco, valor_cop, fecha_pago, referencia, remitente, consumido)
  values ('dddddddd-0000-4000-8000-000000000001', 'bancolombia', 15000,
          now() - interval '3 minutes', 'L1', 'DORIS JOHANNA DIAZ RUEDA', false),
         ('dddddddd-0000-4000-8000-000000000002', 'bancolombia', 15000,
          now() - interval '6 minutes', 'L2', 'YIRAUDIS MILENA DIAZ VARGAS', false);
end $$;

select chk('gana el que se parece más, no el más cercano en hora',
  registrar_aviso_pago((select cod from cods where k = 't5'), now() - interval '5 minutes',
                       'REF-5', null, null)->>'estado',
  'confirmada');
select chk('y es el depósito correcto',
  (select pago_id from reservas limit 1),
  'dddddddd-0000-4000-8000-000000000001'::uuid);


\echo ''
\echo '-- 6. Lo que ya cobró la caja no se ofrece dos veces ----------------'
-- El agujero: admin_pendientes miraba si algún RESERVA lo usaba, pero la
-- caja marca `consumido`. Un depósito cobrado en el mostrador se seguía
-- ofreciendo en la cola: dos cobros, un solo dinero.

do $$
declare v_a jsonb;
begin
  perform limpiar();
  select tomar_cupo('cccccccc-0000-4000-8000-000000000001', 'Otra Persona',
                    '3001110006', null, 'web', 'suelta') into v_a;
  delete from cods where k = 't6';
  insert into cods values ('t6', v_a->>'codigo');
  insert into pagos (banco, valor_cop, fecha_pago, referencia, remitente, consumido)
  values ('bancolombia', 15000, now() - interval '2 minutes', 'L1', 'OTRA PERSONA', true);
end $$;

select chk('un depósito ya cobrado no cruza',
  registrar_aviso_pago((select cod from cods where k = 't6'), now() - interval '2 minutes',
                       'REF-6', null, null)->>'estado',
  'verificando');
select chk('ni se ofrece en la cola',
  (select jsonb_array_length(cola()->'reservas'->0->'pagos_sueltos')), 0);


\echo ''
\echo '-- 7. La plata que no casó con nadie se ve --------------------------'
-- El 11 de agosto había $60.000 de una señora sin reclamar y en "Por
-- validar" no aparecía ni una señal. Solo se veía dentro de Caja.

do $$
begin
  perform limpiar();
  insert into pagos (banco, valor_cop, fecha_pago, referencia, remitente, consumido)
  values ('bancolombia', 60000, now() - interval '20 minutes', 'L1',
          'Elayne Leonor Jiménez Becerra', false);
end $$;

select chk('sale en la lista de plata sin dueño',
  (select jsonb_array_length(cola()->'pagos_libres')), 1);
select chk('con el nombre de quien la mandó',
  (select cola()->'pagos_libres'->0->>'remitente'), 'Elayne Leonor Jiménez Becerra');
select chk('y el valor',
  (select (cola()->'pagos_libres'->0->>'valor_cop')::int), 60000);


\echo ''
\echo '-- 8. El que no cuadra se enseña, marcado y de último ---------------'
-- Quien paga 30.000 por dos personas antes no aparecía nunca al lado de
-- su reserva. Esconder al que no cuadra es esconder el caso que
-- justamente necesita ojos.

do $$
declare v_a jsonb;
begin
  perform limpiar();
  select tomar_cupo('cccccccc-0000-4000-8000-000000000001', 'Dos Puestos',
                    '3001110007', null, 'web', 'suelta') into v_a;
  update reservas set estado = 'verificando', pagado_en = now() - interval '5 minutes'
   where codigo = v_a->>'codigo';
  insert into pagos (banco, valor_cop, fecha_pago, referencia, remitente, consumido)
  values ('bancolombia', 30000, now() - interval '5 minutes', 'L1', 'DOS PUESTOS', false),
         ('bancolombia', 15000, now() - interval '9 minutes', 'L2', 'NADIE CONOCIDO', false);
end $$;

select chk('se ofrecen los dos, cuadre o no',
  (select jsonb_array_length(cola()->'reservas'->0->'pagos_sueltos')), 2);
select chk('primero el que cuadra',
  (select (cola()->'reservas'->0->'pagos_sueltos'->0->>'cuadra')::boolean), true);
select chk('el de 30.000 va de último y marcado',
  (select (cola()->'reservas'->0->'pagos_sueltos'->1->>'cuadra')::boolean), false);
select chk('con su valor real, no el de la clase',
  (select (cola()->'reservas'->0->'pagos_sueltos'->1->>'valor_cop')::int), 30000);


\echo ''
\echo '-- 9. La barrida recoge lo que quedó a medias -----------------------'
-- La persona declaró una hora que no cuadraba con nada. Media hora
-- después entra otro depósito y ya el panorama es claro. La barrida
-- corre en la misma ejecución del correo: no cuesta una de n8n.

do $$
declare v_a jsonb;
begin
  perform limpiar();
  select tomar_cupo('cccccccc-0000-4000-8000-000000000001', 'Tardia Lopez',
                    '3001110008', null, 'web', 'suelta') into v_a;
  -- Declara sin que haya un peso todavía: se queda esperando.
  perform registrar_aviso_pago(v_a->>'codigo', now() - interval '5 minutes',
                               'REF-9', null, null);
end $$;

select chk('se quedó esperando, como debe',
  (select estado::text from reservas limit 1), 'verificando');

-- Ahora sí entra el dinero.
select chk('el correo por sí solo tampoco casa (hora declarada vieja)',
  registrar_pago_y_conciliar('bancolombia', 15000, now() + interval '20 minutes',
    'LLAVE', 'TARDIA LOPEZ', null, 1.0, null, 'correo-9')->>'accion',
  'sin_reserva_que_casar');

select chk('pero la barrida la recoge',
  (conciliar_pendientes()->>'cruzadas')::int, 1);
select chk('y queda confirmada',
  (select estado::text from reservas limit 1), 'confirmada');
select chk('la barrida sobre una cola limpia no hace nada',
  (conciliar_pendientes()->>'cruzadas')::int, 0);


\echo ''
\echo '-- 10. Un depósito no alcanza para dos reservas ---------------------'

do $$
declare v_a jsonb; v_b jsonb;
begin
  perform limpiar();
  select tomar_cupo('cccccccc-0000-4000-8000-000000000001', 'Primera Enfila',
                    '3001110009', null, 'web', 'suelta') into v_a;
  select tomar_cupo('cccccccc-0000-4000-8000-000000000001', 'Segunda Enfila',
                    '3001110010', null, 'web', 'suelta') into v_b;
  update reservas set estado = 'verificando', pagado_en = now() - interval '5 minutes'
   where true;
  insert into pagos (banco, valor_cop, fecha_pago, referencia, remitente, consumido)
  values ('bancolombia', 15000, now() - interval '5 minutes', 'L1', 'ALGUIEN', false);
end $$;

select chk('la barrida amarra una sola',
  (conciliar_pendientes()->>'cruzadas')::int, 1);
select chk('la otra sigue esperando',
  (select count(*)::int from reservas where estado = 'verificando'), 1);
select chk('y no hay dinero de sobra',
  (select count(*)::int from pagos where not consumido), 0);


\echo ''
select case when count(*) = 0 then 'todo en verde'
            else count(*) || ' FALLOS' end as resultado from fallos;
select * from fallos;
