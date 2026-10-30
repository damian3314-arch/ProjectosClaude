-- La rutina de HubSpot marca aquí cuándo dejó la nota de 'mensaje enviado' en el negocio.
ALTER TABLE outbox ADD COLUMN synced_at TEXT;
