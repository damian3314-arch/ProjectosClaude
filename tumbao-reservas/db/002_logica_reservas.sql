-- =====================================================================
-- Tumbao — Reservas: vista de disponibilidad + funciones de negocio
--
-- Toda la lógica crítica vive aquí y NO en n8n, a propósito:
-- el control de cupo tiene que ser atómico. Si el "¿hay cupo?" y el
-- "inserta la reserva" son dos pasos separados en un workflow, dos
-- personas tocando el último cupo al mismo tiempo entran las dos.
-- =====================================================================


-- --- Vista de disponibilidad -----------------------------------------
-- Lo que la página muestra. Solo sesiones futuras y programadas.
CREATE OR REPLACE VIEW v_disponibilidad AS
SELECT
  s.id                AS sesion_id,
  s.tenant_id,
  t.slug              AS tenant_slug,
  t.timezone,
  c.name              AS clase,
  c.style             AS estilo,
  c.level             AS nivel,
  s.instructor_nombre AS instructor,
  s.start_at,
  s.end_at,
  s.capacity          AS cupo_total,
  GREATEST(
    s.capacity - COUNT(r.id) FILTER (WHERE r.status IN ('confirmed','attended')),
    0
  )::INT              AS cupos_disponibles
FROM sesiones_clase s
JOIN tenants t ON t.id = s.tenant_id
JOIN clases  c ON c.id = s.clase_id
LEFT JOIN reservas r ON r.sesion_id = s.id
WHERE s.status = 'scheduled'
  AND s.start_at > NOW()
GROUP BY s.id, t.slug, t.timezone, c.name, c.style, c.level;


-- --- crear_reserva ----------------------------------------------------
-- Devuelve SIEMPRE un JSON. Los errores de negocio (sin cupo, ya
-- reservado, datos malos) vuelven como {ok:false,...} y no como
-- excepción, para que n8n no tenga que distinguir tipos de fallo.
CREATE OR REPLACE FUNCTION crear_reserva(
  p_tenant_slug TEXT,
  p_sesion_id   BIGINT,
  p_first_name  TEXT,
  p_last_name   TEXT,
  p_phone       TEXT,
  p_email       TEXT,
  p_habeas_data BOOLEAN,
  p_source      TEXT DEFAULT 'web'
) RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_tenant_id  BIGINT;
  v_sesion     sesiones_clase%ROWTYPE;
  v_clase      TEXT;
  v_ocupados   INT;
  v_cliente_id BIGINT;
  v_reserva    reservas%ROWTYPE;
  v_codigo     TEXT;
  v_intentos   INT := 0;
BEGIN
  ------------------------------------------------------------------
  -- 1. Validación de entrada
  ------------------------------------------------------------------
  -- Ley 1581 de 2012 (habeas data). Sin autorización explícita no se
  -- guarda el dato de la persona, punto.
  IF p_habeas_data IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'error', 'habeas_data_requerido',
      'mensaje', 'Necesitamos tu autorización para tratar tus datos.');
  END IF;

  p_first_name := btrim(COALESCE(p_first_name, ''));
  IF length(p_first_name) < 2 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'nombre_invalido',
      'mensaje', 'Escribe tu nombre.');
  END IF;

  -- Normalizamos a solo dígitos y quitamos el indicativo 57 si viene.
  p_phone := regexp_replace(COALESCE(p_phone, ''), '[^0-9]', '', 'g');
  IF length(p_phone) = 12 AND left(p_phone, 2) = '57' THEN
    p_phone := substr(p_phone, 3);
  END IF;
  IF length(p_phone) <> 10 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'telefono_invalido',
      'mensaje', 'Escribe tu celular a 10 dígitos.');
  END IF;

  SELECT id INTO v_tenant_id
    FROM tenants WHERE slug = p_tenant_slug AND is_active;
  IF v_tenant_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'academia_no_encontrada');
  END IF;

  ------------------------------------------------------------------
  -- 2. Bloqueo de la sesión (esto es lo que evita sobreventa)
  ------------------------------------------------------------------
  SELECT * INTO v_sesion
    FROM sesiones_clase
   WHERE id = p_sesion_id AND tenant_id = v_tenant_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sesion_no_encontrada',
      'mensaje', 'Esa clase ya no está disponible.');
  END IF;

  IF v_sesion.status <> 'scheduled' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sesion_cancelada',
      'mensaje', 'Esa clase fue cancelada.');
  END IF;

  IF v_sesion.start_at <= NOW() THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sesion_ya_empezo',
      'mensaje', 'Esa clase ya empezó. Elige otro horario.');
  END IF;

  SELECT c.name INTO v_clase FROM clases c WHERE c.id = v_sesion.clase_id;

  ------------------------------------------------------------------
  -- 3. Cliente: upsert por teléfono
  ------------------------------------------------------------------
  INSERT INTO clientes (
    tenant_id, first_name, last_name, phone, email,
    signup_source, habeas_data_accepted, habeas_data_accepted_at
  )
  VALUES (
    v_tenant_id, p_first_name, NULLIF(btrim(COALESCE(p_last_name,'')), ''),
    p_phone, NULLIF(btrim(COALESCE(p_email,'')), ''),
    'web', true, NOW()
  )
  ON CONFLICT (tenant_id, phone) WHERE phone IS NOT NULL
  DO UPDATE SET
    first_name              = EXCLUDED.first_name,
    last_name               = COALESCE(EXCLUDED.last_name, clientes.last_name),
    email                   = COALESCE(EXCLUDED.email, clientes.email),
    habeas_data_accepted    = true,
    habeas_data_accepted_at = COALESCE(clientes.habeas_data_accepted_at, NOW())
  RETURNING id INTO v_cliente_id;

  ------------------------------------------------------------------
  -- 4. ¿Ya tenía reserva en esta sesión?
  ------------------------------------------------------------------
  SELECT * INTO v_reserva
    FROM reservas
   WHERE cliente_id = v_cliente_id AND sesion_id = v_sesion.id;

  IF FOUND AND v_reserva.status IN ('confirmed','attended') THEN
    -- Idempotente: si vuelve a enviar el formulario, le devolvemos el
    -- mismo código en vez de un error feo.
    RETURN jsonb_build_object(
      'ok', true, 'ya_existia', true,
      'reserva_id', v_reserva.id, 'codigo', v_reserva.codigo,
      'clase', v_clase, 'start_at', v_sesion.start_at,
      'mensaje', 'Ya tenías esta clase reservada.');
  END IF;

  ------------------------------------------------------------------
  -- 5. Cupo
  ------------------------------------------------------------------
  SELECT COUNT(*) INTO v_ocupados
    FROM reservas
   WHERE sesion_id = v_sesion.id AND status IN ('confirmed','attended');

  IF v_ocupados >= v_sesion.capacity THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin_cupo',
      'mensaje', 'Esa clase se llenó. Elige otro horario.');
  END IF;

  ------------------------------------------------------------------
  -- 6. Crear (o reactivar) la reserva
  ------------------------------------------------------------------
  IF FOUND AND v_reserva.status IN ('cancelled','no_show') THEN
    UPDATE reservas
       SET status = 'confirmed', source = p_source,
           cancelled_at = NULL, created_at = NOW()
     WHERE id = v_reserva.id
     RETURNING * INTO v_reserva;
  ELSE
    LOOP
      v_intentos := v_intentos + 1;
      -- md5 en hex: sin letras O/I, así que no hay ambigüedad al dictarlo.
      v_codigo := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
      BEGIN
        INSERT INTO reservas (tenant_id, cliente_id, sesion_id, status, source, codigo)
        VALUES (v_tenant_id, v_cliente_id, v_sesion.id, 'confirmed', p_source, v_codigo)
        RETURNING * INTO v_reserva;
        EXIT;
      EXCEPTION WHEN unique_violation THEN
        IF v_intentos >= 5 THEN RAISE; END IF;
      END;
    END LOOP;
  END IF;

  RETURN jsonb_build_object(
    'ok', true, 'ya_existia', false,
    'reserva_id', v_reserva.id,
    'codigo',     v_reserva.codigo,
    'cliente_id', v_cliente_id,
    'nombre',     p_first_name,
    'telefono',   p_phone,
    'clase',      v_clase,
    'start_at',   v_sesion.start_at,
    'cupos_restantes', v_sesion.capacity - v_ocupados - 1
  );
END;
$$;


-- --- cancelar_reserva -------------------------------------------------
-- El alumno cancela con su código + su celular. Sin login.
CREATE OR REPLACE FUNCTION cancelar_reserva(
  p_tenant_slug TEXT,
  p_codigo      TEXT,
  p_phone       TEXT
) RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_tenant_id BIGINT;
  v_reserva   reservas%ROWTYPE;
  v_start_at  TIMESTAMPTZ;
BEGIN
  p_phone := regexp_replace(COALESCE(p_phone, ''), '[^0-9]', '', 'g');
  IF length(p_phone) = 12 AND left(p_phone, 2) = '57' THEN
    p_phone := substr(p_phone, 3);
  END IF;

  SELECT id INTO v_tenant_id FROM tenants WHERE slug = p_tenant_slug AND is_active;
  IF v_tenant_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'academia_no_encontrada');
  END IF;

  SELECT r.* INTO v_reserva
    FROM reservas r
    JOIN clientes cl ON cl.id = r.cliente_id
   WHERE r.tenant_id = v_tenant_id
     AND upper(btrim(r.codigo)) = upper(btrim(p_codigo))
     AND cl.phone = p_phone;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_encontrada',
      'mensaje', 'No encontramos esa reserva con ese celular.');
  END IF;

  IF v_reserva.status = 'cancelled' THEN
    RETURN jsonb_build_object('ok', true, 'mensaje', 'Esa reserva ya estaba cancelada.');
  END IF;

  SELECT start_at INTO v_start_at FROM sesiones_clase WHERE id = v_reserva.sesion_id;
  IF v_start_at <= NOW() THEN
    RETURN jsonb_build_object('ok', false, 'error', 'muy_tarde',
      'mensaje', 'Esa clase ya empezó, no se puede cancelar.');
  END IF;

  UPDATE reservas
     SET status = 'cancelled', cancelled_at = NOW()
   WHERE id = v_reserva.id;

  RETURN jsonb_build_object('ok', true, 'reserva_id', v_reserva.id,
    'mensaje', 'Reserva cancelada. El cupo queda libre para alguien más.');
END;
$$;


-- --- RLS --------------------------------------------------------------
-- Se activa RLS y NO se crean policies para anon/authenticated: nadie
-- entra con la anon key. El único que escribe es n8n, que se conecta
-- por Postgres directo (service role) y no pasa por RLS.
-- Cuando exista la PWA de Beat con login, aquí se añaden las policies
-- de tenant_isolation del modelo de datos de Notion.
ALTER TABLE tenants        ENABLE ROW LEVEL SECURITY;
ALTER TABLE clientes       ENABLE ROW LEVEL SECURITY;
ALTER TABLE clases         ENABLE ROW LEVEL SECURITY;
ALTER TABLE sesiones_clase ENABLE ROW LEVEL SECURITY;
ALTER TABLE reservas       ENABLE ROW LEVEL SECURITY;
