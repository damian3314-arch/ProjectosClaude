-- ═══════════════════════════════════════════════════════════════
--
--   TUMBAO — BORRAR LAS RESERVAS DE PRUEBA
--
--   Opcional. Corre esto ANTES de la prueba de mañana si quieres
--   arrancar con los cupos limpios.
--
--   Hoy hay reservas de prueba ocupando cupo: la clase del martes
--   a las 7am y la de las 6pm tienen 1 cada una. Si no se borran,
--   mañana los números van a estar corridos en uno.
--
--   Primero MIRA lo que hay, y borra solo si reconoces que son
--   pruebas tuyas. Ejecuta las dos partes por separado.
--
-- ═══════════════════════════════════════════════════════════════

-- ── PARTE 1: mirar antes de borrar ──────────────────────────────
select r.codigo, r.nombre, r.telefono, r.estado,
       c.nombre as clase,
       to_char(c.fecha_hora at time zone 'America/Bogota', 'Dy DD Mon HH12:MI am') as cuando,
       to_char(r.created_at at time zone 'America/Bogota', 'DD Mon HH24:MI') as reservada
  from reservas r
  join clases c on c.id = r.clase_id
 order by r.created_at desc;


-- ── PARTE 2: borrar ─────────────────────────────────────────────
-- Descomenta y corre SOLO si arriba confirmaste que todas son pruebas.
-- Devuelve el cupo a cada clase antes de borrar la reserva.
--
-- begin;
--
--   update clases c
--      set cupo_tomado = greatest(c.cupo_tomado - (
--            select count(*) from reservas r
--             where r.clase_id = c.id
--               and r.estado in ('pendiente_pago','verificando','pendiente_validacion','confirmada')
--          ), 0)
--    where exists (select 1 from reservas r where r.clase_id = c.id);
--
--   delete from reservas where true;
--   delete from pagos where true;
--
--   select recalcular_cupos();
--
-- commit;
--
-- Si algo se ve raro despues del begin, escribe  rollback;  y no pasa nada.
