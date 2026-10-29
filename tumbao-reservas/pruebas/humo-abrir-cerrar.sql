-- ---------------------------------------------------------------------
-- Abrir la caja y cerrarla de verdad — prueba de humo
--
-- EL CASO QUE MANDA ESTA NOCHE
-- Esto se aplica con el día empezado: hoy ya hay movimientos y no hay
-- apertura. Lo primero que se comprueba es que eso siga funcionando. Un
-- cambio que dejara la caja tiesa a mitad del turno sería peor que no
-- hacerlo.
--
-- Lo demás:
--   · la base del día sale de lo que se CONTÓ al abrir, no del papel
--   · cerrado es cerrado: no se registra nada encima
--   · rehacer el cierre se puede, pero deja rastro y exige motivo
--
--   psql -d <base> -f humo-abrir-cerrar.sql
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
create or replace function tk() returns text language sql stable as $$ select token from ctx $$;
create or replace function dia() returns jsonb language sql stable as
  $$ select caja_del_dia(tk()) $$;

update ajustes set valor = ((now() at time zone 'America/Bogota')::date - 60)::text
 where clave = 'inicio_produccion';

\echo ''
\echo '-- 1. Un día que ya empezó sin apertura sigue funcionando ------------'
-- Exactamente el estado de esta noche. Si esto falla, el cambio no se
-- puede aplicar hoy.

select chk('sin apertura, la caja NO está abierta', (dia()->>'abierta')::boolean, false);
select chk('y la base cae al comportamiento viejo', (dia()->>'base_cop')::int, 100000);
select chk('se puede registrar igual',
  (caja_registrar(tk(), 'ingreso', 'clase_suelta', 15000, 'efectivo', null)->>'ok')::boolean, true);
select chk('y el esperado cuenta esa venta', (dia()->>'esperado_efectivo')::int, 115000);

\echo ''
\echo '-- 2. Abrir a media tarde también vale ------------------------------'
-- No se exige abrir antes del primer movimiento: hoy ya se vendió.

select chk('abrir funciona con el día empezado',
  (caja_abrir(tk(), 95000, 'faltaban 5 mil de anoche')->>'ok')::boolean, true);
select chk('la caja queda abierta', (dia()->>'abierta')::boolean, true);
select chk('guarda lo que se esperaba', (dia()->'apertura'->>'esperado_cop')::int, 100000);
select chk('y la diferencia contra el papel de ayer',
  (dia()->'apertura'->>'diferencia_cop')::int, -5000);

-- LO IMPORTANTE: la base pasa a ser lo contado, no lo heredado. Si no,
-- el faltante de anoche se arrastra al arqueo de esta noche y ya no hay
-- forma de saber de qué turno fue.
select chk('la base del día pasa a ser lo CONTADO', (dia()->>'base_cop')::int, 95000);
select chk('y el esperado se recalcula sobre eso', (dia()->>'esperado_efectivo')::int, 110000);

select chk('no se abre dos veces',
  caja_abrir(tk(), 95000, null)->>'error', 'YA_ABIERTA');
-- El tope de valor se mira ANTES que "ya abierta": si alguien teclea un
-- cero de más conviene decirle eso, que es lo que puede arreglar, y no
-- que la caja ya estaba abierta.
select chk('un cero de más se frena antes que nada',
  caja_abrir(tk(), 9000000, null)->>'error', 'VALOR_SOSPECHOSO');

\echo ''
\echo '-- 3. Cerrar ---------------------------------------------------------'

select chk('cierra',
  (caja_cerrar(tk(), 110000, 100000, 'todo bien', 100000)->>'ok')::boolean, true);
select chk('el arqueo cuadra', (dia()->'cierre'->>'diferencia_cop')::int, 0);
select chk('y usó la base de la apertura, no la que mandó el panel',
  (dia()->'cierre'->>'esperado_cop')::int, 110000);
select chk('dice quién cerró', (dia()->'cierre'->>'quien'), 'cajera de prueba');

\echo ''
\echo '-- 4. CERRADO ES CERRADO --------------------------------------------'
-- El agujero que había: se podía cerrar a las 9, vender a las 9:05, y el
-- papel impreso quedaba mintiendo sin que nadie se enterara.

select chk('no se registra nada sobre un día cerrado',
  caja_registrar(tk(), 'ingreso', 'clase_suelta', 15000, 'efectivo', null)->>'error',
  'DIA_CERRADO');
select chk('el total no se movió', (dia()->>'ingreso_efectivo')::int, 15000);
select chk('tampoco se abre un día cerrado',
  caja_abrir(tk(), 50000, null)->>'error', 'DIA_CERRADO');

\echo ''
\echo '-- 5. Rehacer el cierre deja rastro ---------------------------------'
-- Antes era un upsert silencioso: el segundo intento borraba el primero
-- y con él la prueba de que hubo un descuadre.

select chk('cerrar otra vez sin pedirlo se rechaza',
  caja_cerrar(tk(), 999, 100000, null, 100)->>'error', 'DIA_YA_CERRADO');
select chk('pedirlo sin motivo tampoco vale',
  caja_cerrar(tk(), 111000, 100000, null, 100000, true, '')->>'error', 'MOTIVO_REQUERIDO');
select chk('con motivo sí',
  (caja_cerrar(tk(), 111000, 100000, null, 100000, true,
               'conté mal los billetes de 10')->>'ok')::boolean, true);
select chk('y queda contado', (dia()->'cierre'->>'rehecho_n')::int, 1);
select chk('con el motivo guardado',
  (dia()->'cierre'->>'rehecho_motivo'), 'conté mal los billetes de 10');
select chk('el arqueo nuevo manda', (dia()->'cierre'->>'contado_cop')::int, 111000);
select chk('y la diferencia se recalculó', (dia()->'cierre'->>'diferencia_cop')::int, 1000);

\echo ''
\echo '-- 6. Lo que necesita la tirilla ------------------------------------'
-- Una tirilla con solo totales obliga a volver a la pantalla para saber
-- de qué eran, y entonces no reemplaza a la pantalla.

select chk('viaja el resumen por concepto',
  (select count(*)::int from jsonb_array_elements(dia()->'resumen_conceptos')), 1);
select chk('con su concepto y su medio',
  (select e->>'concepto' || '/' || (e->>'medio')
     from jsonb_array_elements(dia()->'resumen_conceptos') e limit 1),
  'clase_suelta/efectivo');
select chk('la apertura viaja con hora y quién',
  (dia()->'apertura'->>'quien'), 'cajera de prueba');
select chk('y el cierre con su hora',
  (dia()->'cierre'->>'hora') ~ '^\d{2}:\d{2}$', true);

\echo ''
select case when count(*) = 0 then 'todo en verde'
            else count(*) || ' FALLOS' end as resultado from fallos;
select * from fallos;
