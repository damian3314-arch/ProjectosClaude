-- =====================================================================
-- Tumbao — Reservas: datos de arranque
--
-- ⚠️ EL HORARIO DE ABAJO ES INVENTADO. Sirve para que la página
-- funcione hoy mismo y se pueda probar de punta a punta. Antes de
-- mostrarle esto a un alumno real hay que reemplazarlo por el horario
-- de verdad de Tumbao (ver "Qué necesito de ti" en el README).
--
-- Genera sesiones para los próximos 28 días. Re-ejecutable: borra y
-- vuelve a crear las sesiones futuras que no tengan reservas.
-- =====================================================================

-- --- Academia ---------------------------------------------------------
INSERT INTO tenants (name, slug, timezone, currency)
VALUES ('Tumbao', 'tumbao', 'America/Bogota', 'COP')
ON CONFLICT (slug) DO NOTHING;


-- --- Catálogo de clases ----------------------------------------------
WITH t AS (SELECT id FROM tenants WHERE slug = 'tumbao')
INSERT INTO clases (tenant_id, name, style, level, duration_minutes, default_capacity)
SELECT t.id, v.name, v.style, v.level::class_level, v.dur, v.cap
FROM t, (VALUES
  ('Salsa Principiante',   'Salsa',   'beginner',      60, 20),
  ('Salsa Intermedio',     'Salsa',   'intermediate',  60, 20),
  ('Bachata Principiante', 'Bachata', 'beginner',      60, 20),
  ('Bachata Intermedio',   'Bachata', 'intermediate',  60, 18),
  ('Rueda de Casino',      'Salsa',   'intermediate',  90, 25)
) AS v(name, style, level, dur, cap)
WHERE NOT EXISTS (
  SELECT 1 FROM clases c WHERE c.tenant_id = t.id AND c.name = v.name
);


-- --- Limpieza de sesiones futuras sin reservas ------------------------
DELETE FROM sesiones_clase s
WHERE s.tenant_id = (SELECT id FROM tenants WHERE slug = 'tumbao')
  AND s.start_at > NOW()
  AND NOT EXISTS (SELECT 1 FROM reservas r WHERE r.sesion_id = s.id);


-- --- Sesiones de los próximos 28 días --------------------------------
-- dow: 0=domingo … 6=sábado
WITH t AS (SELECT id, timezone FROM tenants WHERE slug = 'tumbao'),
horario AS (
  SELECT * FROM (VALUES
    ('Salsa Principiante',   ARRAY[1,3], '19:00'::TIME, 'Kevin'),
    ('Bachata Intermedio',   ARRAY[1,3], '20:00'::TIME, 'Kevin'),
    ('Salsa Intermedio',     ARRAY[2,4], '19:00'::TIME, 'Laura'),
    ('Bachata Principiante', ARRAY[2,4], '20:00'::TIME, 'Laura'),
    ('Rueda de Casino',      ARRAY[6],   '10:00'::TIME, 'Kevin')
  ) AS h(clase, dows, hora, instructor)
),
dias AS (
  SELECT d::DATE AS dia
  FROM generate_series(CURRENT_DATE, CURRENT_DATE + INTERVAL '28 days', INTERVAL '1 day') d
)
INSERT INTO sesiones_clase
  (tenant_id, clase_id, instructor_nombre, start_at, end_at, capacity, status)
SELECT
  t.id,
  c.id,
  h.instructor,
  (dias.dia + h.hora) AT TIME ZONE t.timezone,
  (dias.dia + h.hora) AT TIME ZONE t.timezone + (c.duration_minutes || ' minutes')::INTERVAL,
  c.default_capacity,
  'scheduled'
FROM t
JOIN clases c   ON c.tenant_id = t.id
JOIN horario h  ON h.clase = c.name
CROSS JOIN dias
WHERE EXTRACT(DOW FROM dias.dia)::INT = ANY(h.dows)
  AND (dias.dia + h.hora) AT TIME ZONE t.timezone > NOW()
-- Las sesiones que sobrevivieron al DELETE (porque ya tienen reservas)
-- no se duplican.
ON CONFLICT (tenant_id, clase_id, start_at) DO NOTHING;


-- --- Verificación -----------------------------------------------------
-- Debe devolver filas con cupos_disponibles = cupo_total.
-- SELECT clase, start_at, cupo_total, cupos_disponibles
--   FROM v_disponibilidad ORDER BY start_at LIMIT 10;
