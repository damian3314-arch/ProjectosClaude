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

## Las del panel de administración

Las siete `*.test.mjs` del panel corren solas, sin argumentos ni servidor:

```bash
node pruebas/todas.mjs            # las siete de un tirón
node pruebas/tarjeta-sabado.test.mjs   # o una suelta
```

No hay que pasarles ninguna ruta. `instrumentar.mjs` lee `docs/admin.html`,
le inyecta el gancho `window.__e2e` y escribe una copia temporal que es la
que cargan las pruebas. **`docs/admin.html` no se toca nunca**: el gancho no
puede viajar en la página que se despliega.

Si hace falta un gancho nuevo, va en `instrumentar.mjs` y en ningún otro
sitio. Antes de escribirlo, mirar el código real del panel: el nombre exacto
de la función interna, el id del elemento y la clase CSS. Ahí es donde se
falla — la tirilla se pinta en `#tirilla` y no en `#tirilla-pagos`, y los
recuadros son `.ojo` y no `.recuadro`.
