-- Leads de Loggro a los que Damián les escribe el primer mensaje (lo registra la rutina horaria ANTES de enviar).
-- phone = WhatsApp del lead, solo dígitos con indicativo (57…). Si el lead responde, atiende el flujo de Loggro, no el de HolaDami.
CREATE TABLE IF NOT EXISTS loggro_leads (
  phone          TEXT PRIMARY KEY,
  deal_id        TEXT,                      -- negocio en HubSpot
  contact_id     TEXT,
  name           TEXT,                      -- solo el primer nombre, para saludar
  state          TEXT NOT NULL DEFAULT 'pending',  -- pending | sent | q_pn | q_size | q_system | q_when | done | optout
  product        TEXT,                      -- restobar | pos | alojamientos | pymes | nomina
  size           TEXT,                      -- s1 | s2 | s3
  system         TEXT,                      -- sw | manual | none
  urgency        TEXT,                      -- now | month | later
  hot            INTEGER NOT NULL DEFAULT 0,
  wamid          TEXT,                      -- id del primer mensaje enviado (evidencia)
  sent_at        TEXT,
  last_msg_id    TEXT,                      -- evita procesar dos veces el mismo mensaje
  msg_count      INTEGER NOT NULL DEFAULT 0,
  alerted_at     TEXT,                      -- cuándo se le avisó a Damián que está caliente
  reply_alert_at TEXT,                      -- último aviso por una respuesta posterior (máx. 1 cada 30 min)
  summary        TEXT,                      -- resumen para la nota de HubSpot
  synced_state   TEXT,                      -- último estado que ya quedó escrito en HubSpot
  created_at     TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at     TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_loggro_state ON loggro_leads(state, hot, alerted_at);
