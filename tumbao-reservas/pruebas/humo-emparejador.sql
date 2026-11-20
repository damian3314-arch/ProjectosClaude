-- ---------------------------------------------------------------------
-- El emparejador de depósitos — prueba de humo
--
-- EL CASO REAL, del 11 de septiembre de 2026:
--
--   16:31  Xiomara Hoyos reserva el sábado 9:00 am
--   16:47  Ludys Herazo reserva el viernes 7:00 pm
--   16:49  entra un depósito de LUDYS MARIA HERAZO HERAZO por $15.000
--          → el sistema se lo dio a XIOMARA
--
--   similitud('Xiomara Hoyos', 'LUDYS MARIA HERAZO HERAZO') = 0.00
--   similitud('Ludys Herazo',  'LUDYS MARIA HERAZO HERAZO') = 1.00
--
-- El depósito se lo llevó la reserva con parecido CERO mientras la
-- coincidencia perfecta esperaba, porque `buscar_deposito_libre` aceptaba
-- al único candidato sin mirar el nombre y `conciliar_pendientes` recorre
-- por orden de llegada. La 0080 puso la regla que lo impide.
--
-- Medido contra producción cuando se encontró: de 316 reservas enlazadas
-- solas, 104 tenían parecido cero y 13 de esas estaban probablemente mal
-- asignadas. Las otras 91 son legítimas —paga la mamá, la pareja— y por
-- eso la regla NO exige que el nombre cuadre siempre: solo prohíbe
-- quitarle el depósito a quien le calza mejor.
--
-- Esta prueba monta los tres escenarios con datos de mentira y DESHACE
-- todo al final. No toca ni una fila de verdad.
--
--   psql -d <base> -f humo-emparejador.sql
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

-- ── el decorado ──────────────────────────────────────────────────────
insert into clases (id, nombre, profesor, fecha_hora, duracion_min, cupo_total,
                    precio_cop, lugar, aforo, activa)
values ('cccccccc-0000-4000-8000-00000000c001','Clase de prueba','X',
        now() + interval '2 days', 60, 20, 15000, 'Sede Tumbao', 35, true);

\echo ''
\echo '-- 1. El caso del 11 de septiembre ----------------------------------'

insert into pagos (id, banco, valor_cop, fecha_pago, referencia, remitente, consumido)
values ('dddddddd-0000-4000-8000-00000000d001','Bancolombia',15000,
        now() - interval '5 minutes','REF-PRUEBA','LUDYS MARIA HERAZO HERAZO', false);
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo, origen,
                      expira_en, created_at)
values
 ('eeeeeeee-0000-4000-8000-00000000e001','XIOTST','cccccccc-0000-4000-8000-00000000c001',
  'Xiomara Hoyos','3000000001','pendiente_pago','suelta','formulario',
  now() + interval '25 minutes', now() - interval '21 minutes'),
 ('eeeeeeee-0000-4000-8000-00000000e002','LUDTST','cccccccc-0000-4000-8000-00000000c001',
  'Ludys Herazo','3000000002','pendiente_pago','suelta','formulario',
  now() + interval '25 minutes', now() - interval '5 minutes');

-- Xiomara reservó ANTES, así que el bucle la evalúa primero. Antes de la
-- 0080 se llevaba el depósito; ahora tiene que cederlo.
select pg_temp.chk('la reserva que no se llama así NO se lleva el depósito',
  buscar_deposito_libre('eeeeeeee-0000-4000-8000-00000000e001'), null::uuid);
select pg_temp.chk('y sí se lo lleva quien se llama igual',
  buscar_deposito_libre('eeeeeeee-0000-4000-8000-00000000e002'),
  'dddddddd-0000-4000-8000-00000000d001'::uuid);

\echo ''
\echo '-- 2. La mamá que paga sigue funcionando ----------------------------'
-- 91 de las 104 con parecido cero eran de este tipo. Si la regla las
-- bloqueara, un tercio de las reservas iría a confirmación manual y la
-- cajera se ahogaría: sería peor la cura que la enfermedad.

insert into pagos (id, banco, valor_cop, fecha_pago, referencia, remitente, consumido)
values ('dddddddd-0000-4000-8000-00000000d002','Bancolombia',15000,
        now() - interval '5 minutes','REF-MAMA','MARTHA CECILIA GOMEZ DE RAMIREZ', false);
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo, origen,
                      expira_en, created_at)
values ('eeeeeeee-0000-4000-8000-00000000e003','MAMTST','cccccccc-0000-4000-8000-00000000c001',
        'Sofia Ramirez','3000000003','pendiente_pago','suelta','formulario',
        now() + interval '25 minutes', now() - interval '6 minutes');

select pg_temp.chk('con un apellido distinto, si nadie más lo reclama, se enlaza igual',
  buscar_deposito_libre('eeeeeeee-0000-4000-8000-00000000e003'),
  'dddddddd-0000-4000-8000-00000000d002'::uuid);

\echo ''
\echo '-- 3. El grupo no se bloquea a sí mismo -----------------------------'
-- Tres amigas que pagan juntas son varias filas del MISMO grupo y
-- comparten un depósito. Si contaran como «otra reserva», se estorbarían
-- entre ellas y no cobraría ninguna.

insert into pagos (id, banco, valor_cop, fecha_pago, referencia, remitente, consumido)
values ('dddddddd-0000-4000-8000-00000000d003','Bancolombia',30000,
        now() - interval '4 minutes','REF-GRUPO','ANA LUCIA PEREZ', false);
insert into reservas (id, codigo, clase_id, nombre, telefono, estado, tipo, origen,
                      expira_en, created_at, grupo_id)
values
 ('eeeeeeee-0000-4000-8000-00000000e004','GRPTS1','cccccccc-0000-4000-8000-00000000c001',
  'Ana Lucia Perez','3000000004','pendiente_pago','suelta','formulario',
  now() + interval '25 minutes', now() - interval '5 minutes',
  'eeeeeeee-0000-4000-8000-00000000e004'),
 ('eeeeeeee-0000-4000-8000-00000000e005','GRPTS2','cccccccc-0000-4000-8000-00000000c001',
  'Beatriz Moreno','3000000005','pendiente_pago','suelta','formulario',
  now() + interval '25 minutes', now() - interval '5 minutes',
  'eeeeeeee-0000-4000-8000-00000000e004');

select pg_temp.chk('la cabeza del grupo cobra su depósito',
  buscar_deposito_libre('eeeeeeee-0000-4000-8000-00000000e004'),
  'dddddddd-0000-4000-8000-00000000d003'::uuid);
select pg_temp.chk('y la compañera del mismo grupo también lo ve',
  buscar_deposito_libre('eeeeeeee-0000-4000-8000-00000000e005'),
  'dddddddd-0000-4000-8000-00000000d003'::uuid);

\echo ''
\echo '-- 4. El bloqueo se cura solo --------------------------------------'
-- Si la que calzaba mejor vence sin pagar, el depósito tiene que volver
-- a quedar disponible. Sin esto, una reserva podría quedarse esperando
-- para siempre a alguien que nunca llegó.

update reservas set expira_en = now() - interval '1 minute'
 where id = 'eeeeeeee-0000-4000-8000-00000000e002';

select pg_temp.chk('vencida la que calzaba mejor, el depósito se libera',
  buscar_deposito_libre('eeeeeeee-0000-4000-8000-00000000e001'),
  'dddddddd-0000-4000-8000-00000000d001'::uuid);

\echo ''
select case when count(*) = 0 then 'todo en verde'
            else count(*) || ' FALLOS' end as resultado from fallos;
select * from fallos;

-- NADA DE ESTO SE GUARDA. Es la única forma de probar el emparejador
-- contra la base de verdad sin ensuciarla con clientas de mentira.
rollback;
