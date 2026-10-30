-- Bandeja de salida de mensajes de plantilla a leads de Loggro.
-- La rutina de Claude (que sí tiene acceso a HubSpot) solo escribe aquí; el servidor envía en horario, con tope diario y sin esperar la siguiente rutina.
CREATE TABLE IF NOT EXISTS outbox (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  phone       TEXT NOT NULL,                 -- WhatsApp del lead, solo dígitos con indicativo (57…)
  name        TEXT,                          -- primer nombre, solo si es claramente de una persona
  deal_id     TEXT,
  contact_id  TEXT,
  kind        TEXT NOT NULL,                 -- primer_contacto | rescate | retomar | recordatorio
  template    TEXT NOT NULL,                 -- nombre de la plantilla aprobada en Meta
  params      TEXT NOT NULL DEFAULT '[]',    -- JSON con los parámetros del cuerpo, en orden
  draft       TEXT,                          -- el mensaje completo, para leerlo y aprobarlo
  reason      TEXT,                          -- por qué se le escribe (nota de HubSpot, etapa, fecha)
  status      TEXT NOT NULL DEFAULT 'queued',-- review (espera aprobación de Damián) | queued | sent | failed | skipped
  send_after  TEXT NOT NULL DEFAULT (datetime('now')),   -- UTC; no sale antes
  expires_at  TEXT,                          -- UTC; si ya pasó, se omite (por ejemplo un recordatorio vencido)
  sent_at     TEXT,
  wamid       TEXT,
  error       TEXT,
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_outbox_due ON outbox(status, send_after);
CREATE UNIQUE INDEX IF NOT EXISTS idx_outbox_once ON outbox(phone, kind, deal_id);
