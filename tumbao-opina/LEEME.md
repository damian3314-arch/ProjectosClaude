# Tumbao · bot de opiniones

Un chat en el navegador donde los clientes cuentan cómo les ha ido. El
enlace se manda por WhatsApp a mano.

**En línea:** https://tumbao-opina.damian3314.workers.dev
(pendiente: `opina.tumbaobaila.com`)

## Por qué no está en n8n

Cada mensaje de una conversación sería una ejecución. El plan de n8n son
2.500 al mes; una campaña de 40 personas se comería 480. En Cloudflare
Workers caben 100.000 **al día** en el plan gratis.

n8n solo entra una vez por semana, para el reporte. Cuatro ejecuciones
al mes.

## Las tres preguntas

1. ¿Qué te hizo volver la segunda vez?
2. Si mañana dejaras de venir, ¿cuál sería la razón más probable?
3. ¿Qué le dirías a alguien que está pensando en venir?

La segunda es la que importa: deja quejarse sin quedar mal, porque es
hipotética. Preguntar "¿qué no te gustó?" de frente produce "todo bien".

## Qué se guarda y qué no

- **Se guarda** en D1: la conversación completa, el resumen, el tipo y
  el contacto si lo dio.
- **No se guarda** el audio de las notas de voz. Se transcribe con
  Whisper y se suelta, igual que las capturas de comprobantes.

D1 es la verdad; Google Sheets es la vista. Si Google falla justo cuando
alguien termina de contar algo importante, el dato ya está a salvo.

## Modo ensayo

Sin `OPENAI_API_KEY` el bot arranca igual y contesta con un guion fijo.
Sirve para probar la página entera sin gastar ni un peso. Se nota porque
la ficha sale con `tipo: mixto` y sin nombre.

## Secretos (van en el dashboard, nunca en el repo)

    OPENAI_API_KEY   Workers > tumbao-opina > Settings > Variables
    GOOGLE_SA_JSON   cuenta de servicio, para escribir en la hoja
    TOKEN_REPORTE    lo usa n8n para leer /api/pendientes

## Costo real

Con `gpt-4o-mini` y Whisper: ~$0,004 por conversación y $0,006 por
minuto de audio. Una campaña de 40 personas sale por menos de un dólar.

## Desplegar

    npx wrangler deploy
    npx wrangler d1 execute tumbao-opina --remote --file=schema.sql
