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

## El reporte del lunes

`Tumbao · Reporte de opiniones` en n8n, lunes 7am. Lee `/api/pendientes`
—todo lo que tiene `en_hoja = 0`, no "la semana pasada"—, lo consolida
con el modelo y lo manda a bailatumbao@gmail.com. **Cuatro ejecuciones
al mes.**

Se pide lo pendiente y no la semana porque si un lunes falla el envío,
la semana siguiente llega todo junto en vez de perderse. Marcar va
DESPUÉS de enviar, por lo mismo.

Si no hubo conversaciones manda un correo corto diciéndolo. Parece
inútil y no lo es: confirma que sigue vivo. Si el reporte deja de
llegar es que algo se rompió, no que la gente dejó de escribir.

Si el modelo falla, el correo sale igual con la lista cruda y el asunto
marcado `(sin analisis)`. Un reporte feo se lee; uno que no llega, no.

El workflow viejo hacía además una pasada de clasificación **cada media
hora**: 1.440 ejecuciones al mes contra un plan de 2.500. Se quitó — el
Worker ya clasifica al cerrar cada conversación.

## Quién contesta

Tres motores, en este orden:

| | Cuándo | Qué tan bueno |
|---|---|---|
| **OpenAI** | si está `OPENAI_API_KEY` | para lo que se escribió el guion |
| **Workers AI** | siempre que no esté la llave | conversa de verdad, sin llave de nadie |
| Guion fijo | si no hay ni lo uno ni lo otro | tres preguntas que ignoran lo que le escriben |

El del medio es el que está corriendo hoy. Es un binding de Cloudflare
(`ai` en `wrangler.jsonc`), o sea que **no hace falta cuenta de OpenAI
para que el bot funcione**: conversa, transcribe las notas de voz y saca
la ficha por su cuenta. Poner `OPENAI_API_KEY` después no rompe nada,
sube solo al primero.

El tercero es el que estuvo en línea semanas por no tener la llave. No
era "modo de prueba": un bot que recita tres preguntas ignorando lo que
la persona escribe está roto, y el cliente lo nota al segundo mensaje.

El saludo no pasa por ningún modelo — siempre es el mismo, y un modelo
pequeño lo resumía a "Hola, ¿cómo te llamas?", que a alguien que abrió
un enlace de WhatsApp no le dice quién le habla ni para qué.

## Dos cosas que se rompieron y por qué

**La comilla que se llevaba la ficha.** Al pedirle que conservara la
frase textual del cliente "entre comillas", el modelo metía comillas
dobles dentro del JSON y lo partía. Ahora se le piden comillas
angulares «así», y aun si se le escapa una, `taparComillas` la salva.

**El caso bueno era el que fallaba.** Cuando el modelo contesta bien
—JSON limpio, sin vallas de código— Workers AI lo entrega **ya
parseado, como objeto**. El código lo trataba como texto, `String()` lo
volvía `"[object Object]"` y la ficha salía vacía. Costó verlo porque
todas las pruebas con texto pasaban.

Las dos están cubiertas en `pruebas/ficha.test.mjs`.

## Nunca una fila en blanco

Si la extracción falla igual, la ficha no sale vacía: el resumen cae a
las palabras de la persona y el nombre a su primer mensaje. Es la
diferencia entre leer el lunes lo que dijo un cliente y leer
"Sin nombre · (sin resumen)", que hace pensar que no se guardó nada.

## Secretos (van en el dashboard, nunca en el repo)

    TOKEN_REPORTE    para abrir /leer y para que n8n lea /api/pendientes
    OPENAI_API_KEY   OPCIONAL — sin ella el bot funciona con Workers AI
    GOOGLE_SA_JSON   cuenta de servicio, para escribir en la hoja

## Costo real

Hoy, con Workers AI: el plan gratis trae 10.000 neuronas al día y una
conversación de estas gasta del orden de decenas. Una campaña de
WhatsApp entera cabe sin pagar nada.

Con `OPENAI_API_KEY` puesta: ~$0,004 por conversación y $0,006 por
minuto de audio. Una campaña de 40 personas, menos de un dólar.

## Comprobar que sigue en pie

    node pruebas/ficha.test.mjs                  # 38, la ficha del lunes
    node pruebas/limpiar-transcripcion.test.mjs  # 14, alucinaciones de Whisper

## Desplegar

    npx wrangler deploy
    npx wrangler d1 execute tumbao-opina --remote --file=schema.sql
