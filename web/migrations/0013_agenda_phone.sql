-- Teléfono del cliente de cada reunión (la rutina horaria lo copia de HubSpot): Alter calla con quien ya tiene una demo agendada
ALTER TABLE agenda_busy ADD COLUMN phone TEXT;
