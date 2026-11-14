-- ---------------------------------------------------------------------
-- Corte de producción — prueba de humo
--
-- LO QUE NO PUEDE PASAR
-- Que se esconda una reserva que todavía ocupa un cupo. Vaciar la
-- bandeja es cómodo; vaciarla escondiendo un cupo vendido es corrupción
-- silenciosa de datos — la clase sale llena y nadie sabe por quién.
--
-- Por eso el filtro va por la fecha de la CLASE y no por la de la
-- reserva: una reserva de julio de una clase de agosto tiene que seguir
-- viéndose. Eso es lo que se comprueba aquí, y es el caso que un filtro
-- por `created_at` —el obvio— habría roto.
--
--   psql -d tX -f humo-corte.sql
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
create or replace function cuantos() returns int language sql stable as
  $$ select jsonb_array_length(admin_pendientes(tk())->'reservas') $$;
create or replace function hay(cod text) returns boolean language sql stable as $$
  select exists (select 1 from jsonb_array_elements(admin_pendientes(tk())->'reservas') e
                  where e->>'codigo' = cod)
$$;

-- El corte se pone hace 3 días para poder tener cosas a los dos lados.
update ajustes set valor = ((now() at time zone 'America/Bogota')::date - 3)::text
 where clave = 'inicio_produccion';

select chk('el corte se lee', inicio_produccion(),
           (now() at time zone 'America/Bogota')::date - 3);

-- Tres clases: una anterior al corte, una posterior pero ya pasada, y
-- una futura.
insert into clases (id, nombre, profesor, fecha_hora, cupo_total, precio_cop)
values ('aaaaaaaa-0000-4000-8000-00000000000a', 'Clase de julio', 'Prof',
        now() - interval '10 days', 20, 15000),
       ('aaaaaaaa-0000-4000-8000-00000000000b', 'Clase de ayer', 'Prof',
        now() - interval '1 day', 20, 15000),
       ('aaaaaaaa-0000-4000-8000-00000000000c', 'Clase de mañana', 'Prof',
        now() + interval '1 day', 20, 15000);

\echo ''
\echo '-- 1. Lo de antes del corte desaparece ------------------------------'

insert into reservas (codigo, clase_id, nombre, telefono, estado, tipo, created_at)
values ('VIEJA-1', 'aaaaaaaa-0000-4000-8000-00000000000a', 'De julio', '3001110001',
        'pendiente_validacion', 'suelta', now() - interval '11 days');

select chk('una reserva a medias de una clase pasada no sale', hay('VIEJA-1'), false);
select chk('y la cola queda vacía', cuantos(), 0);
-- No se borró: la contabilidad de julio tiene que seguir entera.
select chk('pero la fila sigue en la base',
  (select count(*)::int from reservas where codigo = 'VIEJA-1'), 1);

\echo ''
\echo '-- 2. EL CASO PELIGROSO: reserva vieja, clase futura ----------------'
-- Esto es lo que un filtro por `created_at` habría escondido. La reserva
-- se creó antes del corte, pero ocupa un cupo de una clase que todavía
-- no ha pasado: esconderla sería vender ese cupo dos veces.

insert into reservas (codigo, clase_id, nombre, telefono, estado, tipo, created_at)
values ('VIEJA-VIVA', 'aaaaaaaa-0000-4000-8000-00000000000c', 'Ocupa cupo', '3001110002',
        'pendiente_validacion', 'suelta', now() - interval '11 days');

select chk('SÍ sale, aunque sea más vieja que el corte', hay('VIEJA-VIVA'), true);

\echo ''
\echo '-- 3. Lo de después del corte sale, pasado o no ---------------------'
-- Una clase de ayer pero posterior al corte: puede que la cajera todavía
-- tenga que cuadrarla, así que se muestra.

insert into reservas (codigo, clase_id, nombre, telefono, estado, tipo, created_at)
values ('NUEVA-1', 'aaaaaaaa-0000-4000-8000-00000000000b', 'De ayer', '3001110003',
        'pendiente_validacion', 'suelta', now() - interval '1 day');

select chk('lo posterior al corte sale', hay('NUEVA-1'), true);
select chk('en total quedan dos en la cola', cuantos(), 2);

\echo ''
\echo '-- 4. Si se borra el ajuste, se enseña todo --------------------------'
-- Fallar mostrando de más es recuperable; fallar escondiendo no se nota
-- hasta que alguien reclama un cupo que ya se vendió.

delete from ajustes where clave = 'inicio_produccion';
select chk('sin ajuste, el corte se va a 2000', inicio_produccion(), date '2000-01-01');
select chk('y vuelven a salir las tres', cuantos(), 3);

insert into ajustes (clave, valor)
values ('inicio_produccion', ((now() at time zone 'America/Bogota')::date - 3)::text);

\echo ''
\echo '-- 5. El banco tampoco arrastra lo de antes -------------------------'

create or replace function bco(k text) returns int language sql stable as
  $$ select (caja_del_dia(tk())->'banco'->>k)::int $$;

-- Dos depósitos sin reclamar: uno de antes del corte y otro de después.
insert into pagos (banco, valor_cop, fecha_pago, remitente, consumido)
values ('bancolombia', 900000, now() - interval '9 days', 'ANTES DEL CORTE', false),
       ('bancolombia',  40000, now() - interval '1 day',  'DESPUES', false);

select chk('el inventario solo cuenta lo de después del corte', bco('libre_cop'), 40000);
select chk('y es un solo depósito', bco('libre_n'), 1);
select chk('la lista para escoger tampoco ofrece el viejo',
  (select count(*)::int from jsonb_array_elements(caja_del_dia(tk())->'pagos_libres')), 1);
select chk('el de antes sigue en la base',
  (select count(*)::int from pagos where remitente = 'ANTES DEL CORTE'), 1);

\echo ''
select case when count(*) = 0 then 'todo en verde'
            else count(*) || ' FALLOS' end as resultado from fallos;
select * from fallos;
