-- Avisos para Damián que no pudieron salir como texto (ventana de 24 h cerrada). Se guardan aquí y se entregan completos apenas él
-- responde a la plantilla "avisos_pendientes" (o escribe cualquier mensaje al número): así la plantilla es solo una notificación y el contenido va gratis.
CREATE TABLE IF NOT EXISTS alert_queue (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  dest       TEXT NOT NULL,              -- teléfono (dígitos) o BSUID del destinatario
  text       TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  sent_at    TEXT
);
CREATE INDEX IF NOT EXISTS idx_alert_queue_pending ON alert_queue(dest, sent_at);
