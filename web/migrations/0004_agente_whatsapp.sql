-- Agente de WhatsApp: en qué paso del formulario va cada persona que le escribe al número de HolaDami.
-- id = su teléfono (solo dígitos) o, si WhatsApp no lo muestra, su ID de usuario (BSUID).
CREATE TABLE IF NOT EXISTS wa_sessions (
  id          TEXT PRIMARY KEY,
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at  TEXT NOT NULL DEFAULT (datetime('now')),
  state       TEXT NOT NULL DEFAULT 'new',   -- new | need_problem | q_budget | q_timing | q_decider | need_phone | done | optout
  name        TEXT,
  phone       TEXT,
  problem     TEXT,
  intent      TEXT,
  budget      TEXT,
  timing      TEXT,
  decider     TEXT,
  lead_id     TEXT,
  last_msg_id TEXT,                          -- evita procesar dos veces el mismo mensaje si Kapso reintenta
  day         TEXT,                          -- día del conteo de mensajes (tope diario por persona)
  msg_count   INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_wa_sessions_created ON wa_sessions(created_at);
