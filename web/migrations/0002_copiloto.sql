-- Copiloto de leads: brief para Damián, seguimiento del estado y embudo de la página
ALTER TABLE leads ADD COLUMN brief        TEXT;     -- JSON: resumen, necesidad, apertura, preguntas, alertas, frente_sugerido
ALTER TABLE leads ADD COLUMN brief_at     TEXT;
ALTER TABLE leads ADD COLUMN owner_note   TEXT;     -- nota privada de Damián (máx. 1000)
ALTER TABLE leads ADD COLUMN contacted_at TEXT;     -- primera vez que pasó a contactado/agendado/cliente (mide el tiempo de respuesta)
ALTER TABLE leads ADD COLUMN status_at    TEXT;     -- último cambio de estado
ALTER TABLE leads ADD COLUMN nudged_at    TEXT;     -- empujón a Damián por lead sin contactar (máx. 1 por lead)

-- Embudo: un evento por etapa y sesión (sesiones únicas se cuentan en /api/stats)
CREATE TABLE IF NOT EXISTS events (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  session_id  TEXT NOT NULL,
  ip_hash     TEXT,
  type        TEXT NOT NULL,            -- visit | start | intent | q_budget | q_timing | q_decider | contact_form | lead
  intent      TEXT,
  utm         TEXT                      -- JSON con utm_source, utm_medium, ...
);
CREATE INDEX IF NOT EXISTS idx_events_type_time ON events(type, created_at);
CREATE INDEX IF NOT EXISTS idx_events_session ON events(session_id);
CREATE INDEX IF NOT EXISTS idx_events_ip_time ON events(ip_hash, created_at);

-- Resumen diario a Damián: un registro por día (hora de Bogotá) para no enviarlo dos veces
CREATE TABLE IF NOT EXISTS owner_digest (
  day      TEXT PRIMARY KEY,
  sent_at  TEXT NOT NULL DEFAULT (datetime('now'))
);
