-- Intentos fallidos de ADMIN_TOKEN por IP (tope: 10 en 15 min → 429). El cron borra los de más de un día.
CREATE TABLE IF NOT EXISTS admin_fails (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  ip_hash    TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_admin_fails_ip_time ON admin_fails(ip_hash, created_at);
