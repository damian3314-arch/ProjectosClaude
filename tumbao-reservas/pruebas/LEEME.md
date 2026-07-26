# Pruebas

Reproducen todo el flujo sin tocar n8n ni Supabase.

`espejo-n8n.mjs` no reimplementa los workflows: **extrae el `jsCode` real de los
`.json` de `n8n/` y lo ejecuta**, contra un Postgres local. Si estas pruebas
pasan, el workflow importado a n8n se comporta igual.

## Correrlas

```bash
# 1. Postgres local con las migraciones aplicadas
createdb tumbao
psql -d tumbao -f ../db/001_schema.sql -f ../db/002_logica_reservas.sql -f ../db/003_seed_demo.sql

# 2. Servidor espejo (ajusta la conexión en espejo-n8n.mjs si hace falta)
node espejo-n8n.mjs

# 3. Prueba de navegador
npm install playwright-core
node prueba-pagina.mjs
```

`prueba-pagina.mjs` espera Chromium en `/opt/pw-browsers/chromium-1194/chrome-linux/chrome`.
Ajusta `executablePath` a tu instalación.
