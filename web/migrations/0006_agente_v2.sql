-- Agente conversacional (v2): historial de la conversación y lo que se va sabiendo de cada persona.
-- chat_key = teléfono (solo dígitos) o BSUID si WhatsApp no muestra el número.
CREATE TABLE IF NOT EXISTS agent_log (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  chat_key    TEXT NOT NULL,
  role        TEXT NOT NULL,                 -- user | assistant
  content     TEXT NOT NULL,
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_agent_log_chat ON agent_log(chat_key, id);

CREATE TABLE IF NOT EXISTS agent_chats (
  chat_key     TEXT PRIMARY KEY,
  source       TEXT NOT NULL DEFAULT 'holadami',   -- holadami | loggro
  stage        TEXT,                               -- qualifying | wants_demo | wants_quote | not_now | not_fit | support | chitchat | optout
  hot          INTEGER NOT NULL DEFAULT 0,
  product      TEXT,
  facts        TEXT,                               -- JSON: negocio, tamaño, sistema actual, dolor, urgencia, teléfono
  summary      TEXT,
  meeting_pref TEXT,                               -- hora que la persona propuso para la demo
  videos_sent  TEXT,                               -- productos cuyo video ya se envió (separados por coma)
  agenda_sent  INTEGER NOT NULL DEFAULT 0,
  paused_until TEXT,                               -- si Damián escribe a mano, el agente calla hasta esta fecha
  turns        INTEGER NOT NULL DEFAULT 0,
  created_at   TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at   TEXT NOT NULL DEFAULT (datetime('now'))
);

ALTER TABLE loggro_leads ADD COLUMN campaign TEXT;  -- primer_contacto | rescate | retomar | recordatorio_demo
