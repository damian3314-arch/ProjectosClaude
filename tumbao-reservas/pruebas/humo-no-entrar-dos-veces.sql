-- ---------------------------------------------------------------------
-- La misma persona no entra dos veces a la misma clase — humo (0063)
--
-- El caso real: el 31 de agosto Eliana Pulgarín reservó dos veces para
-- la clase de las 19:00 con cuatro minutos de diferencia. La primera se
-- concilió sola contra su depósito de $15.000; la segunda se confirmó a
-- mano tres horas después con la referencia "018000931987", que no es
-- una referencia sino el teléfono de atención de Bancolombia. Dos
-- entradas, un pago, y el cierre contando 6 donde entraron 5.
--
-- Lo que esta prueba defiende, y lo que NO debe romper:
--   · la misma persona (mismo teléfono y mismo nombre) no se confirma
--     dos veces en la misma clase
--   · pero un GRUPO sí: dos personas de verdad reservando desde un
--     mismo móvil, que es como entraron Andrea y Elayne ese mismo día
--   · y dos tocayas con teléfonos distintos también entran
--   · y la misma persona en OTRA clase, por supuesto
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

create temp table ctx (token text);
insert into ctx select crear_token_admin('cajera de prueba 0063')->>'token';
create or replace function tk() returns text language sql stable as $$ select token from ctx $$;
create or replace function hoy() returns date language sql stable as
  $$ select (now() at time zone 'America/Bogota')::date $$;
update ajustes set valor = (hoy() - 60)::text where clave = 'inicio_produccion';

insert into clases (id, nombre, profesor, fecha_hora, cupo_total, precio_cop)
values ('b1111111-0000-4000-8000-000000000001','Salsa de las 7','Prof',
        (hoy() + 1 + time '19:00') at time zone 'America/Bogota', 30, 15000),
       ('b1111111-0000-4000-8000-000000000002','Bachata de las 8','Prof',
        (hoy() + 1 + time '20:00') at time zone 'America/Bogota', 30, 15000);

-- ── el caso de Eliana: la misma persona, dos veces, misma clase ──────
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo, origen, created_at)
values ('b2222222-0000-4000-8000-000000000001','ELI-01','b1111111-0000-4000-8000-000000000001',
        'Eliana Pulgarín','3186762998','verificando','suelta','formulario', now()),
       ('b2222222-0000-4000-8000-000000000002','ELI-02','b1111111-0000-4000-8000-000000000001',
        'Eliana Pulgarín','3186762998','verificando','suelta','formulario', now());

\echo ''
\echo '-- La primera entra normal ----------------------------------------------'
select chk('la primera se confirma',
  admin_confirmar(tk(), 'ELI-01', null, 'M18066236')->>'estado', 'confirmada');

\echo ''
\echo '-- LA SEGUNDA NO. Este es el fallo del 31 de agosto ---------------------'
-- El cupo se anota ANTES para poder comprobar que el intento fallido no
-- lo movió. Comparar contra un número fijo no diría nada: lo que importa
-- es que rechazar no deje rastro.
create temp table cupo_antes as
  select cupo_tomado from clases where id='b1111111-0000-4000-8000-000000000001';

select chk('la misma persona no entra dos veces a la misma clase',
  admin_confirmar(tk(), 'ELI-02', null, '018000931987')->>'error', 'YA_ENTRO');
select chk('y se queda como estaba, sin confirmar',
  (select estado from reservas where codigo='ELI-02'), 'verificando');
select chk('el intento fallido no movió el cupo',
  (select cupo_tomado from clases where id='b1111111-0000-4000-8000-000000000001'),
  (select cupo_tomado from cupo_antes));

\echo ''
\echo '-- El mensaje tiene que decirle a la cajera qué hacer -------------------'
select chk('explica la salida si de verdad son dos',
  (admin_confirmar(tk(), 'ELI-02', null, 'X999')->>'mensaje') like '%pon el nombre%', true);

\echo ''
\echo '-- PERO UN GRUPO SÍ: dos personas, un móvil -----------------------------'
-- Andrea y Elayne, el mismo 31 de agosto: entraron juntas con un
-- depósito de $30.000 desde un mismo teléfono. Son dos de verdad.
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo, origen, grupo_id, created_at)
values ('b3333333-0000-4000-8000-000000000001','GRU-01','b1111111-0000-4000-8000-000000000001',
        'Andrea Ospino','3008013550','verificando','suelta','formulario',
        'b3333333-0000-4000-8000-000000000001', now()),
       ('b3333333-0000-4000-8000-000000000002','GRU-02','b1111111-0000-4000-8000-000000000001',
        'Elayne Jiménez','3008013550','verificando','suelta','formulario',
        'b3333333-0000-4000-8000-000000000001', now());

select chk('el grupo entero se confirma de una',
  (admin_confirmar(tk(), 'GRU-01', null, '50906185520310483634953761565881950')->>'cupos')::int, 2);
select chk('y las dos quedan confirmadas',
  (select count(*)::int from reservas where codigo in ('GRU-01','GRU-02') and estado='confirmada'), 2);

\echo ''
\echo '-- Dos tocayas con teléfonos distintos son dos personas -----------------'
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo, origen, created_at)
values ('b4444444-0000-4000-8000-000000000001','TOC-01','b1111111-0000-4000-8000-000000000001',
        'Maria Gomez','3009990001','verificando','suelta','formulario', now()),
       ('b4444444-0000-4000-8000-000000000002','TOC-02','b1111111-0000-4000-8000-000000000001',
        'Maria Gomez','3009990002','verificando','suelta','formulario', now());

select chk('la primera tocaya entra',
  admin_confirmar(tk(), 'TOC-01', null, 'REF-TOC-1')->>'estado', 'confirmada');
select chk('y la segunda TAMBIÉN, que no es la misma persona',
  admin_confirmar(tk(), 'TOC-02', null, 'REF-TOC-2')->>'estado', 'confirmada');

\echo ''
\echo '-- La misma persona en otra clase, sin problema -------------------------'
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo, origen, created_at)
values ('b5555555-0000-4000-8000-000000000001','ELI-03','b1111111-0000-4000-8000-000000000002',
        'Eliana Pulgarín','3186762998','verificando','suelta','formulario', now());

select chk('Eliana sí puede ir a la clase de las 8',
  admin_confirmar(tk(), 'ELI-03', null, 'REF-OTRA-CLASE')->>'estado', 'confirmada');

\echo ''
\echo '-- Tildes y mayúsculas no sirven para colarse ---------------------------'
-- Si el freno mirara el nombre tal cual, escribirlo sin tilde lo
-- saltaría. Es justo el error que se comete tecleando deprisa.
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo, origen, created_at)
values ('b6666666-0000-4000-8000-000000000001','ELI-04','b1111111-0000-4000-8000-000000000002',
        'ELIANA PULGARIN','3186762998','verificando','suelta','formulario', now());

select chk('sin tilde y en mayúsculas sigue siendo la misma',
  admin_confirmar(tk(), 'ELI-04', null, 'REF-SIN-TILDE')->>'error', 'YA_ENTRO');

\echo ''
\echo '-- Una rechazada no bloquea: la persona puede volver a entrar -----------'
-- Si se rechazó por error, tiene que poder confirmarse otra vez.
update reservas set estado='rechazada' where codigo='TOC-01';
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo, origen, created_at)
values ('b7777777-0000-4000-8000-000000000001','TOC-03','b1111111-0000-4000-8000-000000000001',
        'Maria Gomez','3009990001','verificando','suelta','formulario', now());

select chk('lo rechazado no cuenta como que ya entró',
  admin_confirmar(tk(), 'TOC-03', null, 'REF-TOC-3')->>'estado', 'confirmada');

\echo ''
\echo '-- Los permisos siguen cerrados -----------------------------------------'
select chk('anon no puede ejecutar admin_confirmar',
  has_function_privilege('anon',
    'admin_confirmar(text,text,uuid,text)', 'execute'), false);
select chk('service_role sí',
  has_function_privilege('service_role',
    'admin_confirmar(text,text,uuid,text)', 'execute'), true);

\echo ''
select case when count(*) = 0 then 'TODO EN VERDE'
            else count(*) || ' FALLO(S)' end as resultado from fallos;
select * from fallos;
