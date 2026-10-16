-- ---------------------------------------------------------------------
-- La identidad de un cliente — prueba de humo
--
-- LA REGLA, que la fijó Damián el 12 de septiembre de 2026:
-- «la identificación es el número de celular + el nombre del cliente».
--
-- POR QUÉ ESTA PRUEBA ES LA QUE IMPORTA
-- Un ranking equivocado no se nota: se cree. Y todo el ranking cuelga de
-- una sola decisión —qué filas son la misma persona— que se toma sobre
-- datos escritos a mano en el mostrador. Medido contra producción:
--
--   · 173 teléfonos y 268 escrituras de nombre
--   · 69 teléfonos con MÁS DE UN NOMBRE (grupos que comparten número)
--   · 15 nombres en DOS teléfonos (la misma persona desde el celular
--     de una amiga y desde el suyo)
--
-- Así que ninguna de las dos llaves sirve sola, y cada una falla hacia
-- un lado distinto. Lo que se comprueba aquí es que la combinación de
-- las dos hace lo que debe en los casos de verdad, con los nombres
-- reales que provocaron cada decisión.
--
--   psql -d <base> -f humo-identidad-cliente.sql
--
-- No escribe nada: el token de prueba va dentro de una transacción que
-- se deshace al final.
-- ---------------------------------------------------------------------
\set ON_ERROR_STOP on
set client_min_messages = notice;

begin;

create temp table fallos (que text, esperado text, obtenido text) on commit drop;

create or replace function pg_temp.chk(que text, obtenido anyelement, esperado anyelement)
returns void language plpgsql as $$
begin
  if obtenido is distinct from esperado then
    insert into fallos values (que, esperado::text, coalesce(obtenido::text, '(null)'));
    raise notice '  x %  (esperaba %, llegó %)', que, esperado, coalesce(obtenido::text, 'null');
  else
    raise notice '  v %', que;
  end if;
end $$;

-- ¿Son la misma persona? Es la pregunta entera.
create or replace function pg_temp.misma(n1 text, t1 text, n2 text, t2 text)
returns boolean language sql stable as $$
  select cliente_clave(n1, t1) = cliente_clave(n2, t2);
$$;

\echo ''
\echo '-- 1. La misma persona escrita de otra manera -----------------------'
-- El mostrador teclea el nombre cada vez. Si cada escritura fuera una
-- clienta, la que más viene saldría repartida en cinco fichas de dos
-- días y el ranking coronaría a cualquiera.

select pg_temp.chk('mayúsculas y minúsculas no hacen dos personas',
  pg_temp.misma('Andrea Ospino', '3001112233', 'ANDREA OSPINO', '3001112233'), true);
select pg_temp.chk('ni las tildes',
  pg_temp.misma('Mónica Niño', '3001112233', 'Monica Nino', '3001112233'), true);
select pg_temp.chk('ni el orden del nombre y el apellido',
  pg_temp.misma('Silvia Ayala', '3001112233', 'Ayala Silvia', '3001112233'), true);
select pg_temp.chk('ni los espacios de más',
  pg_temp.misma('Paula  Bohórquez', '3001112233', 'Paula Bohorquez', '3001112233'), true);
-- «de», «la», «y» se caen: el mismo nombre escrito con y sin partículas
-- tiene que cuadrar, y esas palabras no distinguen a nadie.
select pg_temp.chk('ni las partículas del apellido',
  pg_temp.misma('Martha Gomez de Ramirez', '3001112233',
                'Martha Gomez Ramirez', '3001112233'), true);

\echo ''
\echo '-- 2. Personas distintas siguen distintas --------------------------'
-- Este es el lado peligroso. 69 de 173 teléfonos tienen varios nombres
-- porque quien reserva para el grupo pone su número. Si el teléfono
-- mandara solo, el ranking mediría «quién organiza al grupo».

select pg_temp.chk('dos amigas con el mismo teléfono son dos clientas',
  pg_temp.misma('Karen Yepes', '3024327694', 'Jessica Paba', '3024327694'), false);
-- Y el caso fino: comparten teléfono Y comparten el nombre de pila.
select pg_temp.chk('aunque compartan el nombre de pila',
  pg_temp.misma('Karen Yepes', '3024327694', 'Karen Herrera', '3024327694'), false);
select pg_temp.chk('y tres del mismo grupo son tres',
  (select count(distinct cliente_clave(n, '3024327694'))
     from (values ('Karen Yepes'), ('Jessica Paba'), ('Karen Julieth Herrera')) v(n)),
  3::bigint);

\echo ''
\echo '-- 3. Donde entra el celular ---------------------------------------'
-- Un nombre de una sola palabra no distingue a nadie: puede haber dos
-- Palomas. Ahí el número es lo único que queda, así que se le pega.

select pg_temp.chk('dos «Paloma» con distinto teléfono son dos personas',
  pg_temp.misma('Paloma', '3001112233', 'Paloma', '3009998877'), false);
select pg_temp.chk('la misma «Paloma» con su teléfono es una',
  pg_temp.misma('Paloma', '3001112233', 'PALOMA', '3001112233'), true);

-- Y al contrario: un nombre de dos palabras ya identifica, así que la
-- misma persona reservando desde el celular de una amiga NO se parte.
-- Son 15 casos reales, y sin esto el trío de los jueves desaparece del
-- ranking con 2 y 3 días en vez de 5.
select pg_temp.chk('un nombre completo aguanta el cambio de teléfono',
  pg_temp.misma('Karen Yepes', '3024327694', 'Karen yepes', '3132213122'), true);

\echo ''
\echo '-- 4. El teléfono se lee aunque venga escrito de otra forma ---------'

select pg_temp.chk('los guiones y espacios del número no cuentan',
  pg_temp.misma('Paloma', '300 111 2233', 'Paloma', '300-111-2233'), true);
select pg_temp.chk('ni el indicativo de país delante',
  pg_temp.misma('Paloma', '+57 3001112233', 'Paloma', '3001112233'), true);

\echo ''
\echo '-- 5. El ranking, contra los datos de verdad -----------------------'

create temp table ctx (token text) on commit drop;
insert into ctx select crear_token_admin('ranking de prueba')->>'token';
update admin_tokens set rol = 'propietario'
 where token_hash = hash_token((select token from ctx));
create or replace function pg_temp.tk() returns text language sql stable as
  $$ select token from ctx $$;

create temp table r as
  select admin_clientes_ranking(pg_temp.tk(), null, 50) as j;

select pg_temp.chk('contesta que sí', (select j->>'ok' from r), 'true');
-- Dicho en la respuesta y no solo en el panel: quien lea esto por la API
-- tiene que enterarse de que las afiliadas no están.
select pg_temp.chk('y avisa de que solo mide clase suelta',
  (select j->>'solo_clase_suelta' from r), 'true');

-- Nadie puede salir dos veces. Si la fusión dejara dos fichas con el
-- mismo jefe, una persona aparecería repetida y sus días contados dos
-- veces sin que nada fallara.
select pg_temp.chk('nadie aparece dos veces en la lista',
  (select count(*) - count(distinct (x->>'nombre') || '|' || (x->>'telefono'))
     from r, jsonb_array_elements(r.j->'clientes') x), 0::bigint);

-- Está ordenado por días. Un ranking desordenado se lee igual de bien y
-- dice otra cosa.
select pg_temp.chk('viene ordenado de más a menos días',
  (select bool_and(d >= seg)
     from (select (x->>'dias')::int as d,
                  lead((x->>'dias')::int) over (order by (x->>'puesto')::int) as seg
             from r, jsonb_array_elements(r.j->'clientes') x) t
    where seg is not null), true);

-- Los días de una persona no pueden pasar de los días que hubo clase.
select pg_temp.chk('nadie viene más días de los que hubo clase',
  (select count(*) from r, jsonb_array_elements(r.j->'clientes') x
    where (x->>'dias')::int >
          (select count(distinct (c.fecha_hora at time zone 'America/Bogota')::date)
             from clases c where c.fecha_hora <= now())), 0::bigint);

-- `afiliada` tiene que corresponder con una membresía viva de verdad:
-- marcar de más haría que se dejara de llamar a quien sí hay que llamar.
select pg_temp.chk('la marca de «ya tiene plan» cuadra con membresias',
  (select coalesce(string_agg(x->>'nombre', '; '), '(cuadran todas)')
     from r, jsonb_array_elements(r.j->'clientes') x
    where (x->>'afiliada')::boolean
      <> exists (select 1 from membresias m
                  where similitud_nombre(x->>'nombre', m.afiliado) >= 0.999
                    and m.fin >= (now() at time zone 'America/Bogota')::date)),
  '(cuadran todas)');

\echo ''
\echo '-- 6. La ventana de días ------------------------------------------'
-- Pedir 30 días no puede devolver a alguien que no vino en 30 días.

select pg_temp.chk('en 30 días no sale nadie de hace más de 30',
  (select count(*) from jsonb_array_elements(
            (admin_clientes_ranking(pg_temp.tk(), 30, 50))->'clientes') x
    where (x->>'hace_dias')::int > 30), 0::bigint);

-- Y la ventana corta nunca puede dar más días que la larga.
select pg_temp.chk('treinta días no da más que todo el historial',
  (select coalesce(max((x->>'dias')::int), 0) from jsonb_array_elements(
            (admin_clientes_ranking(pg_temp.tk(), 30, 50))->'clientes') x)
  <= (select coalesce(max((x->>'dias')::int), 0) from r,
        jsonb_array_elements(r.j->'clientes') x), true);

-- Un p_dias de cero o negativo no debe devolver una ventana vacía por
-- accidente: se trata como «todo», igual que null.
select pg_temp.chk('un plazo de cero se porta como «todo»',
  (admin_clientes_ranking(pg_temp.tk(), 0, 3))->'clientes'->0->>'nombre',
  (select r.j->'clientes'->0->>'nombre' from r));

\echo ''
\echo '-- 7. Quien no debe verlo, no lo ve -------------------------------'
-- Aquí van nombres, teléfonos y cuánto paga cada quien.

create temp table ctx2 (token text) on commit drop;
insert into ctx2 select crear_token_admin('cajera de prueba')->>'token';
update admin_tokens set rol = 'cajero'
 where token_hash = hash_token((select token from ctx2));

select pg_temp.chk('un cajero no ve el ranking',
  (admin_clientes_ranking((select token from ctx2)))->>'error', 'SIN_PERMISO');
select pg_temp.chk('y un token inventado tampoco',
  (admin_clientes_ranking('esto-no-es-un-token'))->>'error', 'NO_AUTORIZADO');

\echo ''
\echo '-- 8. Lo que la regla NO puede arreglar, dicho en voz alta ---------'
-- Una errata parte a la persona, y ninguna regla honesta lo impide:
-- «LUDIS» y «LUDYS» no se parecen más que «KAREN YEPES» y «KAREN
-- HERRERA», que sí son dos personas. Lo que el ranking hace es AVISAR.

select pg_temp.chk('una errata en el nombre sí parte a la persona',
  pg_temp.misma('Ludys Herazo', '3118708421', 'ludis herazo', '3118708421'), false);

select pg_temp.chk('y por eso el ranking dice cuántas fichas hay por teléfono',
  (select count(*) from r, jsonb_array_elements(r.j->'clientes') x
    where x->'fichas_del_telefono' is null), 0::bigint);

do $$
declare r2 record; n int := 0;
begin
  for r2 in select x->>'telefono' as tel, x->>'nombres' as nombres, x->>'cuantas' as c
              from (select admin_clientes_ranking(pg_temp.tk(), null, 50) as j) q,
                   jsonb_array_elements(q.j->'telefonos_compartidos') x
             order by (x->>'cuantas')::int desc limit 6
  loop
    n := n + 1;
    raise notice '  · % → % fichas: %', r2.tel, r2.c, r2.nombres;
  end loop;
  if n = 0 then raise notice '  (ningún teléfono con varias fichas)'; end if;
end $$;

\echo ''
select case when count(*) = 0 then 'todo en verde'
            else count(*) || ' FALLOS' end as resultado from fallos;
select * from fallos;

-- Los dos tokens de prueba se van con esto.
rollback;
