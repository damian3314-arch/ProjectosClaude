-- ---------------------------------------------------------------------
-- Pagó y no vino: clases por disfrutar — prueba de humo
--
-- EL CASO
-- Alguien paga y no aparece. Al día siguiente escribe diciendo que pagó
-- y tiene razón. Hoy no hay dónde mirarlo: en la puerta o se marca que
-- entró o se queda sin marcar, igual que quien todavía no ha llegado.
--
-- Lo que se comprueba:
--   · marcarlo NO borra el pago (esa plata entró y la caja ya cuadró)
--   · el plazo se cuenta desde la clase perdida, no desde el día que
--     alguien se acordó de marcarlo
--   · reprogramar da cupo sin volver a cobrar, y no sobrevende
--   · pasados los tres días se cae de la lista pero no se borra
--
--   psql -d <base> -f humo-disfrutar.sql
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
create or replace function lista() returns jsonb language sql stable as
  $$ select admin_por_disfrutar(tk()) $$;

update ajustes set valor = ((now() at time zone 'America/Bogota')::date - 60)::text
 where clave = 'inicio_produccion';

-- La de AYER es la que se perdió; la de MAÑANA es a la que se reprograma.
insert into clases (id, nombre, profesor, fecha_hora, cupo_total, precio_cop)
values ('11111111-0000-4000-8000-000000000001', 'La que se perdió', 'Prof',
        (((now() at time zone 'America/Bogota')::date - 1 + time '18:00')
          at time zone 'America/Bogota'), 20, 15000),
       ('11111111-0000-4000-8000-000000000002', 'La de mañana', 'Prof',
        (((now() at time zone 'America/Bogota')::date + 1 + time '18:00')
          at time zone 'America/Bogota'), 2, 15000);

create temp table cods (k text primary key, cod text);

-- Una reserva confirmada y pagada en la clase de ayer.
do $$
declare v_id uuid; v_pago uuid;
begin
  insert into pagos (banco, valor_cop, fecha_pago, remitente, consumido)
  values ('bancolombia', 15000, now() - interval '1 day', 'CAMILA ROJAS', true)
  returning id into v_pago;
  insert into reservas (codigo, clase_id, nombre, telefono, estado, tipo, pago_id)
  values ('FALTO1', '11111111-0000-4000-8000-000000000001', 'Camila Rojas',
          '3001110001', 'confirmada', 'suelta', v_pago)
  returning id into v_id;
  update clases set cupo_tomado = 1
   where id = '11111111-0000-4000-8000-000000000001';
end $$;


\echo ''
\echo '-- 1. Marcar que no vino -------------------------------------------'

select chk('la lista arranca vacía', (select jsonb_array_length(lista()->'gente')), 0);

select chk('se marca',
  (admin_marcar_no_vino(tk(), '11111111-0000-4000-8000-000000000001', 'r:FALTO1')
    ->>'no_vino')::boolean, true);

-- LO IMPORTANTE: la plata no se toca. La caja de ayer ya cuadró y ya se
-- imprimió la tirilla; mover ese ingreso ahora descuadraría un cierre
-- que está archivado.
select chk('la reserva sigue confirmada',
  (select estado::text from reservas where codigo = 'FALTO1'), 'confirmada');
select chk('y sigue apuntando a su pago',
  (select pago_id is not null from reservas where codigo = 'FALTO1'), true);
select chk('el depósito sigue consumido',
  (select consumido from pagos limit 1), true);

select chk('el plazo se cuenta desde la clase, no desde hoy',
  (select credito_vence from reservas where codigo = 'FALTO1'),
  ((now() at time zone 'America/Bogota')::date - 1 + 3));


\echo ''
\echo '-- 2. Sale en la lista, con lo que hace falta para llamarla ---------'

select chk('una persona en la lista', (select jsonb_array_length(lista()->'gente')), 1);
select chk('con su nombre',    (select lista()->'gente'->0->>'nombre'), 'Camila Rojas');
select chk('con su celular',   (select lista()->'gente'->0->>'telefono'), '3001110001');
select chk('y los días que le quedan',
  (select (lista()->'gente'->0->>'dias')::int), 2);
select chk('dice qué clase se perdió',
  (select lista()->'gente'->0->>'clase'), 'La que se perdió');


\echo ''
\echo '-- 3. No se marca cualquier cosa ------------------------------------'

do $$
begin
  insert into reservas (codigo, clase_id, nombre, telefono, estado, tipo)
  values ('SINPAG', '11111111-0000-4000-8000-000000000001', 'Nunca Pago',
          '3001110002', 'pendiente_validacion', 'suelta'),
         ('MIEMBR', '11111111-0000-4000-8000-000000000001', 'Con Plan',
          '3001110003', 'confirmada', 'miembro');
end $$;

select chk('quien no pagó no genera crédito',
  admin_marcar_no_vino(tk(), '11111111-0000-4000-8000-000000000001', 'r:SINPAG')->>'error',
  'NO_PAGO');
select chk('quien viene por mensualidad tampoco',
  admin_marcar_no_vino(tk(), '11111111-0000-4000-8000-000000000001', 'r:MIEMBR')->>'error',
  'ES_MIEMBRO');
select chk('ni alguien de otra clase',
  admin_marcar_no_vino(tk(), '11111111-0000-4000-8000-000000000002', 'r:FALTO1')->>'error',
  'NO_EXISTE');
select chk('la lista sigue teniendo una sola',
  (select jsonb_array_length(lista()->'gente')), 1);


\echo ''
\echo '-- 4. Reprogramar ---------------------------------------------------'

select chk('no se reprograma a la misma clase',
  admin_reprogramar(tk(), 'FALTO1', '11111111-0000-4000-8000-000000000001')->>'error',
  'MISMA_CLASE');

do $$
declare v_r jsonb;
begin
  select admin_reprogramar(tk(), 'FALTO1', '11111111-0000-4000-8000-000000000002') into v_r;
  delete from cods where k in ('nueva','ok');
  insert into cods values ('nueva', v_r->>'codigo'), ('ok', v_r->>'ok');
end $$;

select chk('reprograma bien', (select cod from cods where k='ok'), 'true');
select chk('la nueva nace confirmada',
  (select estado::text from reservas where codigo = (select cod from cods where k='nueva')),
  'confirmada');
select chk('y SIN pago propio: la plata ya entró con la vieja',
  (select pago_id from reservas where codigo = (select cod from cods where k='nueva')),
  null::uuid);
select chk('se ve de dónde viene',
  (select viene_de is not null from reservas where codigo = (select cod from cods where k='nueva')),
  true);
select chk('ocupa cupo en la clase nueva',
  (select cupo_tomado from clases where id = '11111111-0000-4000-8000-000000000002'), 1);
select chk('y se cae de la lista de por disfrutar',
  (select jsonb_array_length(lista()->'gente')), 0);
select chk('no se puede reprogramar dos veces',
  admin_reprogramar(tk(), 'FALTO1', '11111111-0000-4000-8000-000000000002')->>'error',
  'YA_REPROGRAMADA');


\echo ''
\echo '-- 5. Reprogramar no sobrevende -------------------------------------'
-- La clase de mañana tiene 2 cupos y ya se usó 1. Con dos personas más
-- pidiendo, la segunda tiene que rebotar: un crédito no es un pase por
-- encima del aforo.

do $$
declare v_p uuid;
begin
  for i in 1..2 loop
    -- Horas distintas: el índice pagos_unicos es
    -- (banco, valor, fecha_pago, referencia), y dos pagos iguales en el
    -- mismo minuto se pisan. Es una limitación real del sistema, no de
    -- la prueba, y está anotada en ESTRENO.md.
    insert into pagos (banco, valor_cop, fecha_pago, remitente, consumido)
    values ('bancolombia', 15000, now() - interval '1 day' - (i || ' hours')::interval,
            'OTRA', true)
    returning id into v_p;
    insert into reservas (codigo, clase_id, nombre, telefono, estado, tipo,
                          pago_id, no_vino_at, credito_vence)
    values ('FALT0' || i, '11111111-0000-4000-8000-000000000001',
            'Falto ' || i, '300111000' || (3 + i), 'confirmada', 'suelta',
            v_p, now(), (now() at time zone 'America/Bogota')::date + 2);
  end loop;
end $$;

select chk('la primera entra',
  (admin_reprogramar(tk(), 'FALT01', '11111111-0000-4000-8000-000000000002')->>'ok')::boolean,
  true);
select chk('la segunda rebota, la clase está llena',
  admin_reprogramar(tk(), 'FALT02', '11111111-0000-4000-8000-000000000002')->>'error',
  'SIN_CUPO');
select chk('y sigue con su crédito para otro día',
  (select jsonb_array_length(lista()->'gente')), 1);


\echo ''
\echo '-- 6. Al vencer se cae de la lista, pero no se borra ----------------'

do $$
begin
  update reservas set credito_vence = (now() at time zone 'America/Bogota')::date - 1
   where codigo = 'FALT02';
end $$;

select chk('ya no sale en la lista', (select jsonb_array_length(lista()->'gente')), 0);
select chk('pero la fila sigue ahí, con su marca',
  (select no_vino_at is not null from reservas where codigo = 'FALT02'), true);
select chk('y no se reprograma una vencida',
  admin_reprogramar(tk(), 'FALT02', '11111111-0000-4000-8000-000000000002')->>'error',
  'VENCIDA');


\echo ''
\echo '-- 7. La lista de la puerta dice quién no vino ----------------------'

select chk('la fila trae la marca',
  (select (e->>'no_vino')::boolean
     from jsonb_array_elements(
            admin_lista_clase(tk(), '11111111-0000-4000-8000-000000000001')->'reservas') e
    where e->>'codigo' = 'FALT02'),
  true);
select chk('y quien sí vino no la trae',
  (select (e->>'no_vino')::boolean
     from jsonb_array_elements(
            admin_lista_clase(tk(), '11111111-0000-4000-8000-000000000001')->'reservas') e
    where e->>'codigo' = 'MIEMBR'),
  false);

-- Quitar la marca por si se tocó sin querer.
select chk('se puede desmarcar',
  (admin_marcar_no_vino(tk(), '11111111-0000-4000-8000-000000000001', 'r:FALT02', false)
    ->>'no_vino')::boolean, false);
select chk('y deja de tener crédito',
  (select credito_vence from reservas where codigo = 'FALT02'), null::date);


\echo ''
select case when count(*) = 0 then 'todo en verde'
            else count(*) || ' FALLOS' end as resultado from fallos;
select * from fallos;
