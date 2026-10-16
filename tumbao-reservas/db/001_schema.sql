-- =====================================================================
-- Tumbao — Reservas: schema base
-- Postgres / Supabase. Ejecutar en el SQL Editor de Supabase.
--
-- Subconjunto del "Modelo de datos inicial" de Notion, recortado a lo
-- que la página de reservas necesita. Los nombres de tabla/columna se
-- mantienen idénticos al modelo completo para que planes, membresías,
-- pagos y caja se puedan añadir después sin migrar nada de esto.
-- =====================================================================

-- --- Enums ------------------------------------------------------------
-- DO $$ para que el script sea re-ejecutable sin explotar.
DO $$ BEGIN
  CREATE TYPE signup_source AS ENUM ('walk_in','instagram','referido','whatsapp','web','otro');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE class_level AS ENUM ('beginner','intermediate','advanced');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE session_status AS ENUM ('scheduled','completed','cancelled');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE reservation_status AS ENUM ('confirmed','cancelled','no_show','attended');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- --- 1. tenants -------------------------------------------------------
CREATE TABLE IF NOT EXISTS tenants (
  id         BIGSERIAL PRIMARY KEY,
  name       TEXT NOT NULL,
  slug       TEXT UNIQUE NOT NULL,
  timezone   TEXT NOT NULL DEFAULT 'America/Bogota',
  currency   TEXT NOT NULL DEFAULT 'COP',
  is_active  BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW()
);


-- --- 2. clientes ------------------------------------------------------
CREATE TABLE IF NOT EXISTS clientes (
  id                      BIGSERIAL PRIMARY KEY,
  tenant_id               BIGINT NOT NULL REFERENCES tenants(id),
  first_name              TEXT NOT NULL,
  last_name               TEXT,
  phone                   TEXT,
  email                   TEXT,
  birth_date              DATE,
  signup_source           signup_source DEFAULT 'walk_in',
  habeas_data_accepted    BOOLEAN DEFAULT false,
  habeas_data_accepted_at TIMESTAMPTZ,
  notes                   TEXT,
  created_at              TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT phone_or_email_required CHECK (phone IS NOT NULL OR email IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_clientes_tenant_phone ON clientes(tenant_id, phone);
CREATE INDEX IF NOT EXISTS idx_clientes_tenant_name  ON clientes(tenant_id, first_name, last_name);

-- Necesario para el upsert por teléfono que hace la reserva web.
-- Un teléfono identifica a una persona dentro de una academia.
CREATE UNIQUE INDEX IF NOT EXISTS uq_clientes_tenant_phone
  ON clientes(tenant_id, phone) WHERE phone IS NOT NULL;


-- --- 3. clases (catálogo) --------------------------------------------
CREATE TABLE IF NOT EXISTS clases (
  id               BIGSERIAL PRIMARY KEY,
  tenant_id        BIGINT NOT NULL REFERENCES tenants(id),
  name             TEXT NOT NULL,
  style            TEXT,
  level            class_level,
  duration_minutes INTEGER NOT NULL,
  default_capacity INTEGER NOT NULL,
  is_active        BOOLEAN DEFAULT true
);


-- --- 4. sesiones_clase (instancias en el calendario) ------------------
CREATE TABLE IF NOT EXISTS sesiones_clase (
  id            BIGSERIAL PRIMARY KEY,
  tenant_id     BIGINT NOT NULL REFERENCES tenants(id),
  clase_id      BIGINT NOT NULL REFERENCES clases(id),
  instructor_id UUID,                      -- FK a profiles cuando exista auth
  instructor_nombre TEXT,                  -- provisional mientras no hay profiles
  start_at      TIMESTAMPTZ NOT NULL,
  end_at        TIMESTAMPTZ NOT NULL,
  capacity      INTEGER NOT NULL,
  status        session_status DEFAULT 'scheduled',
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT sesion_rango_valido CHECK (end_at > start_at)
);

CREATE INDEX IF NOT EXISTS idx_sesiones_tenant_start ON sesiones_clase(tenant_id, start_at);

-- Una misma clase no puede existir dos veces a la misma hora. Evita que
-- re-generar el horario duplique sesiones que ya tienen alumnos inscritos.
CREATE UNIQUE INDEX IF NOT EXISTS uq_sesion_clase_inicio
  ON sesiones_clase(tenant_id, clase_id, start_at);


-- --- 5. reservas ------------------------------------------------------
CREATE TABLE IF NOT EXISTS reservas (
  id           BIGSERIAL PRIMARY KEY,
  tenant_id    BIGINT NOT NULL REFERENCES tenants(id),
  cliente_id   BIGINT NOT NULL REFERENCES clientes(id),
  sesion_id    BIGINT NOT NULL REFERENCES sesiones_clase(id),
  status       reservation_status DEFAULT 'confirmed',
  source       TEXT,                       -- 'web' | 'whatsapp' | 'front_desk'
  codigo       TEXT NOT NULL,              -- código corto que el alumno muestra en recepción
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  cancelled_at TIMESTAMPTZ,
  UNIQUE (cliente_id, sesion_id)
);

CREATE INDEX IF NOT EXISTS idx_reservas_sesion_status ON reservas(sesion_id, status);
CREATE UNIQUE INDEX IF NOT EXISTS uq_reservas_tenant_codigo ON reservas(tenant_id, codigo);
