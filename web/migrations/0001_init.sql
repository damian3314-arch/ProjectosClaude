-- Leads que llegan desde la página
CREATE TABLE IF NOT EXISTS leads (
  id          TEXT PRIMARY KEY,
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  session_id  TEXT,
  name        TEXT NOT NULL,
  phone       TEXT NOT NULL,            -- formato internacional sin "+", ej. 573001234567
  intent      TEXT,                     -- nomina | software | ia | procesos | datos | NULL
  problem     TEXT,
  budget      TEXT,                     -- b1 | b2 | b3
  timing      TEXT,                     -- now | month | later
  decider     TEXT,                     -- solo | with | other
  points      INTEGER NOT NULL,
  tier        TEXT NOT NULL,            -- A | B | C
  action      TEXT NOT NULL,            -- contact | nurture
  calendar    TEXT NOT NULL,            -- loggro | personal
  consent     INTEGER NOT NULL DEFAULT 0,
  utm         TEXT,                     -- JSON
  page        TEXT,
  status      TEXT NOT NULL DEFAULT 'nuevo',  -- nuevo | contactado | agendado | cliente | descartado
  notified_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_leads_created ON leads(created_at);
CREATE INDEX IF NOT EXISTS idx_leads_tier_status ON leads(tier, status);

-- Conversación del chat de la página (para mejorar el bot y por límite de uso)
CREATE TABLE IF NOT EXISTS chat_messages (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  session_id  TEXT NOT NULL,
  ip_hash     TEXT,
  role        TEXT NOT NULL,            -- user | assistant
  content     TEXT NOT NULL,
  intent      TEXT
);
CREATE INDEX IF NOT EXISTS idx_chat_session ON chat_messages(session_id);
CREATE INDEX IF NOT EXISTS idx_chat_ip_time ON chat_messages(ip_hash, created_at);
