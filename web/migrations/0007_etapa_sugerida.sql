-- Etapa que el agente sugiere para el negocio en HubSpot; la rutina horaria la aplica al sincronizar.
-- necesidades | demo_pendiente | perdido  (demo agendada solo cuando existe la reunión)
ALTER TABLE loggro_leads ADD COLUMN next_stage TEXT;
