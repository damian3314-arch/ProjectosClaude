-- ---------------------------------------------------------------------
-- Quince minutos de gracia — prueba de humo
--
-- EL CASO
-- Son las 7:00 en punto. La persona mira la página para la clase de las
-- 7:00 y no la ve. No entiende "ya empezó": entiende "no hay cupo", y se
-- va. En la vida real esa misma persona llega a las 7:10 y entra.
--
-- Lo que se comprueba:
--   · a los 5 y a los 14 minutos todavía se puede reservar
--   · a los 16 ya no, y el mensaje lo dice
--   · el aforo sigue mandando: la gracia no es un pase para sobrevender
--   · reservar de a varios se comporta igual
--   · el número se puede cambiar sin migración
--
--   psql -d <base> -f humo-gracia.sql
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

-- Clases colocadas relativas a AHORA, no a una hora del reloj: así la
-- prueba mide los minutos de gracia y no la hora a la que se corra.
insert into clases (id, nombre, profesor, fecha_hora, cupo_total, precio_cop)
values ('22222222-0000-4000-8000-000000000001', 'Empezó hace 5 min',  'Prof',
        now() - interval '5 minutes',  20, 15000),
       ('22222222-0000-4000-8000-000000000002', 'Empezó hace 14 min', 'Prof',
        now() - interval '14 minutes', 20, 15000),
       ('22222222-0000-4000-8000-000000000003', 'Empezó hace 16 min', 'Prof',
        now() - interval '16 minutes', 20, 15000),
       ('22222222-0000-4000-8000-000000000004', 'Empezó hace 3 horas', 'Prof',
        now() - interval '3 hours',    20, 15000),
       ('22222222-0000-4000-8000-000000000005', 'Llena y recién empezada', 'Prof',
        now() - interval '5 minutes',   1, 15000);

update clases set cupo_tomado = 1
 where id = '22222222-0000-4000-8000-000000000005';


\echo ''
\echo '-- 1. El ajuste ------------------------------------------------------'

select chk('la gracia son 15 minutos', minutos_de_gracia(), 15);


\echo ''
\echo '-- 2. Dentro de los quince ------------------------------------------'

select chk('a los 5 minutos todavía se reserva',
  (tomar_cupo('22222222-0000-4000-8000-000000000001', 'Llego Tarde',
              '3001110001', null, 'web', 'suelta')->>'ok')::boolean, true);
select chk('a los 14 también',
  (tomar_cupo('22222222-0000-4000-8000-000000000002', 'Justo Justo',
              '3001110002', null, 'web', 'suelta')->>'ok')::boolean, true);


\echo ''
\echo '-- 3. Pasados los quince -------------------------------------------'
-- Aquí sí tiene sentido decir que no: la clase ya va por la mitad.

select chk('a los 16 ya no',
  tomar_cupo('22222222-0000-4000-8000-000000000003', 'Muy Tarde',
             '3001110003', null, 'web', 'suelta')->>'error', 'CLASE_YA_PASO');
select chk('ni a las 3 horas',
  tomar_cupo('22222222-0000-4000-8000-000000000004', 'Al Otro Dia',
             '3001110004', null, 'web', 'suelta')->>'error', 'CLASE_YA_PASO');
select chk('y el mensaje se entiende',
  tomar_cupo('22222222-0000-4000-8000-000000000003', 'Muy Tarde',
             '3001110003', null, 'web', 'suelta')->>'mensaje',
  'Esa clase ya empezó. Elige otro horario.');


\echo ''
\echo '-- 3b. Y la clase se SIGUE OFRECIENDO ---------------------------------'
-- El sitio que la persona ve. Sin esto, la clase de las 7:00 desaparece
-- del listado a las 7:00:01 aunque tomar_cupo la aceptara: no hay nada
-- donde hacer clic, y lo que se entiende no es "ya empezó" sino "no hay
-- cupo".

select chk('la de hace 5 minutos sale en el listado',
  (select count(*)::int from clases_para('suelta')
    where id = '22222222-0000-4000-8000-000000000001'), 1);
select chk('la de hace 14 también',
  (select count(*)::int from clases_para('suelta')
    where id = '22222222-0000-4000-8000-000000000002'), 1);
select chk('la de hace 16 ya no',
  (select count(*)::int from clases_para('suelta')
    where id = '22222222-0000-4000-8000-000000000003'), 0);
select chk('ni la de hace 3 horas',
  (select count(*)::int from clases_para('suelta')
    where id = '22222222-0000-4000-8000-000000000004'), 0);


\echo ''
\echo '-- 4. La gracia NO es un pase para sobrevender -----------------------'
-- Lo único que se movió es cuándo deja de ofrecerse una clase. El aforo
-- manda igual que siempre.

select chk('una clase llena sigue llena aunque acabe de empezar',
  tomar_cupo('22222222-0000-4000-8000-000000000005', 'No Cabe',
             '3001110005', null, 'web', 'suelta')->>'error', 'SIN_CUPO');


\echo ''
\echo '-- 5. Reservar de a varios se comporta igual -------------------------'

select chk('un grupo entra dentro de los quince',
  (tomar_cupos('22222222-0000-4000-8000-000000000001',
               array['Ana Perez','Beto Perez'], '3001110006', null, 'web')
   ->>'ok')::boolean, true);
select chk('y no entra pasados los quince',
  tomar_cupos('22222222-0000-4000-8000-000000000003',
              array['Caro Perez','Dani Perez'], '3001110007', null, 'web')->>'error',
  'CLASE_YA_PASO');


\echo ''
\echo '-- 6. El número se cambia sin migración ------------------------------'

update ajustes set valor = '30' where clave = 'minutos_de_gracia';
select chk('ahora son 30', minutos_de_gracia(), 30);
select chk('y el listado lo sigue sin tocar nada más',
  (select count(*)::int from clases_para('suelta')
    where id = '22222222-0000-4000-8000-000000000003'), 1);
select chk('y la de hace 16 minutos ya entra',
  (tomar_cupo('22222222-0000-4000-8000-000000000003', 'Ahora Si',
              '3001110008', null, 'web', 'suelta')->>'ok')::boolean, true);

update ajustes set valor = '0' where clave = 'minutos_de_gracia';
select chk('con cero vuelve a ser como antes',
  tomar_cupo('22222222-0000-4000-8000-000000000001', 'Sin Gracia',
             '3001110009', null, 'web', 'suelta')->>'error', 'CLASE_YA_PASO');

-- Y si alguien borra la fila o escribe cualquier cosa, se cae a cero:
-- ser estricto de más se arregla por WhatsApp; ser permisivo de más mete
-- gente a una clase que ya va por la mitad.
update ajustes set valor = 'quince' where clave = 'minutos_de_gracia';
select chk('un valor que no es número se trata como cero', minutos_de_gracia(), 0);
delete from ajustes where clave = 'minutos_de_gracia';
select chk('y sin la fila, también', minutos_de_gracia(), 0);


\echo ''
select case when count(*) = 0 then 'todo en verde'
            else count(*) || ' FALLOS' end as resultado from fallos;
select * from fallos;
