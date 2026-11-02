-- Horarios ocupados de Damián (la rutina horaria copia las reuniones de HubSpot) + hora que el cliente eligió con Alter
CREATE TABLE IF NOT EXISTS agenda_busy (
  id         TEXT PRIMARY KEY,           -- 'hs:<id de la reunión>' o 'alter:<teléfono>'
  start_utc  TEXT NOT NULL,
  end_utc    TEXT NOT NULL,
  label      TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_agenda_busy_end ON agenda_busy(end_utc);
ALTER TABLE loggro_leads ADD COLUMN meeting_at TEXT;
