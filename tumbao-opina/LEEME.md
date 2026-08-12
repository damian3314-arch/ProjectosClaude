# Tumbao · bot de opiniones

Un chat en el navegador donde los clientes cuentan cómo les ha ido. El
enlace se manda por WhatsApp a mano.

**El enlace que se comparte:** https://opina.tumbaobaila.com
**Para leer lo que dice la gente:** https://opina.tumbaobaila.com/leer?token=…

El de `workers.dev` sigue vivo y funciona; se deja encendido para no
romper ningún enlace ya compartido.

## La burbuja de tumbaobaila.com

La página pública trae un botón flotante que abre este mismo chat en un
iframe con `?burbuja=1`, que esconde el encabezado (la ventanita ya
tiene el suyo). No hay una segunda copia del chat: el enlace de WhatsApp
y la burbuja son el mismo sitio, así que arreglar algo aquí lo arregla
en los dos.

El iframe se crea al abrirlo, no al cargar la página: quien entra a
reservar no tiene por qué descargarse un chat que no pidió.

## Dónde se lee lo que la gente cuenta

`/leer?token=…`, con la llave `TOKEN_REPORTE`. Ordena lo urgente
primero y esconde las conversaciones que no pasaron del saludo — una
pestaña que alguien abrió y cerró no es una opinión.

Es una página aparte y no una pestaña del panel de admin a propósito: el
panel vive contra Supabase y esto contra D1, y cruzarlos obligaría a que
un Worker le pidiera datos al otro para enseñar una lista que se mira
una vez a la semana.

Sin `TOKEN_REPORTE` la página no se abre y dice dónde ponerlo. Aquí hay
nombres, celulares y quejas de clientes: no puede quedar abierta.

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

## Whisper alucina con el silencio

Con audio en silencio o puro ruido, Whisper no devuelve vacío: devuelve
frases de subtítulos de YouTube que se aprendió de memoria — *"Gracias
por ver el video"*, *"Subtítulos por la comunidad de Amara.org"*.

Sin filtro eso entraba al chat como si la persona lo hubiera dicho, el
bot le respondía a algo que nadie dijo, y terminaba en la ficha, en la
hoja y en el reporte del lunes como si fuera la opinión de un cliente.

`limpiarTranscripcion()` las descarta. El tope de 60 caracteres no
sobra: una nota larga y real que de casualidad diga "gracias por ver" no
se puede tirar a la basura, y las alucinaciones siempre son cortas.
Cuando descarta, `/api/voz` responde sin `texto` y la página pide otra
nota, que es lo que ya hacía cuando no se entendía nada.

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
