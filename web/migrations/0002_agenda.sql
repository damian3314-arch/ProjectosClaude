-- Agenda: cita reservada por el agente y control de mensajes proactivos
ALTER TABLE leads ADD COLUMN meeting_start    TEXT;     -- ISO UTC
ALTER TABLE leads ADD COLUMN meeting_end      TEXT;     -- ISO UTC
ALTER TABLE leads ADD COLUMN meeting_event_id TEXT;     -- id del evento en Google/Outlook (lo devuelve n8n)
ALTER TABLE leads ADD COLUMN followups        INTEGER NOT NULL DEFAULT 0;
ALTER TABLE leads ADD COLUMN last_followup_at TEXT;
ALTER TABLE leads ADD COLUMN reminded_24      INTEGER NOT NULL DEFAULT 0;
ALTER TABLE leads ADD COLUMN reminded_1       INTEGER NOT NULL DEFAULT 0;
ALTER TABLE leads ADD COLUMN owner_note       TEXT;     -- por qué el agente te escaló el caso
CREATE INDEX IF NOT EXISTS idx_leads_meeting ON leads(meeting_start);
