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
  el contacto si lo dio. Turno a turno, no al final: cerrar la pestaña
  ya no pierde nada (ver «29 de agosto»).
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

### El lunes 17 no llegó, y hay que saber por qué

El Worker se quedó **sin el secreto `TOKEN_REPORTE`**. `/api/pendientes`
contestaba 401, el flujo moría en el primer nodo y el correo no salía.
`wrangler secret list` sobre `tumbao-opina` devolvía `[]`: no había
ningún secreto puesto.

Cuándo se perdió se puede acotar: el 12 de agosto una corrida a mano
funcionó de punta a punta —mandó el correo y marcó 17 conversaciones—,
y el 17 a las 7 am ya daba 401. Entre esas dos fechas se redesplegó el
Worker varias veces por lo de Workers AI. **La causa no se encontró.**
Un `wrangler deploy` normal no borra secretos, así que queda como algo
a vigilar, no como algo entendido.

Lo peor no fue el fallo sino que fuera **mudo**: un reporte que no llega
se parece exactamente a una semana sin opiniones. Por eso el workflow
quedó enganchado a `Tumbao · Avisos de fallo`, que manda correo con el
nodo y el error. Y por eso el aviso de semana vacía —que parece inútil—
es justo lo que distingue "nadie escribió" de "esto se rompió".

Si el reporte vuelve a faltar, lo primero es:

```
npx wrangler secret list          # ¿está TOKEN_REPORTE?
curl -X POST https://opina.tumbaobaila.com/api/pendientes \
     -H 'Content-Type: application/json' -d '{"token":"..."}'
```


El workflow viejo hacía además una pasada de clasificación **cada media
hora**: 1.440 ejecuciones al mes contra un plan de 2.500. Se quitó — el
Worker ya clasifica al cerrar cada conversación.

## 28 de agosto: la opinión que sí llegó y se tiró a la basura

Se midió el embudo real. De 42 chats abiertos, 11 personas escribieron
algo, 7 contestaron una segunda pregunta y **5 contestaron las tres**.
Pero solo 3 quedaron marcadas como completas.

Esa diferencia no es de redondeo: es una opinión de verdad que se perdió.
El 21 de agosto alguien contestó las tres preguntas —«Los extraño
muchoooo de lunes a viernes 😭», «Trabajooo», «Que es lo mejor de lo
mejor 😃»— y en la base quedó con `resumen`, `tipo`, `nombre` y
`transcripcion` en NULL. En el correo del lunes 24 salió como
**«Sin nombre · (sin resumen)»**. La dueña vio una fila vacía donde había
una clienta contenta. (Las otras dos sin marcar, del 12 de agosto, sí
eran pruebas de desarrollo.)

### Por qué pasa

`/api/cerrar` es el ÚNICO sitio donde se escriben `resumen`, `tipo`,
`nombre`, `telefono`, `transcripcion` y `completa = 1`. Lo llama la
página cuando el bot da la conversación por terminada. Si la persona
cierra la pestaña antes —que es lo que hace la gente cuando ya dijo lo
que tenía que decir— no se llama nunca.

Los mensajes NO se pierden: `guardarMensaje` los va guardando turno a
turno en `mensajes`. Lo que pasa es que **nada de lo que se lee consulta
esa tabla**. `/api/pendientes` y `/leer` leen de `conversaciones`
(`resumen`, `transcripcion`), y ahí no hay nada. La opinión está en D1,
entera, y no la ve nadie.

Dicho de otra forma: el sistema solo se queda con lo que la gente cuenta
si además juega el guion hasta el final, incluida la pregunta del
celular. Contestar las tres preguntas y cerrar la pestaña cuenta como no
haber dicho nada.

### Lo que NO es el problema

- **No es que la gente no escriba.** Los 30 chats con `turnos = 1` son
  casi todos ruido de medición: la fila de `conversaciones` se crea en la
  primera llamada a `/api/mensaje`, que la página hace sola para pedir el
  saludo. `turnos = 1` significa «existe el saludo del bot», no «alguien
  abrió y se fue». Y como no se guarda de dónde viene la visita, un toque
  curioso a la burbuja de tumbaobaila.com es indistinguible de alguien que
  recibió el enlace por WhatsApp. Ese número no se puede leer.
- **No es la segunda pregunta.** Los que llegan a ella la contestan sin
  problema: «Trabajooo», «El clima», «Viajar a la ciudad donde resido».

### Lo que sí conviene mirar, por orden

1. **Guardar aunque no se cierre.** Es el único que recupera opiniones
   que hoy se tiran. — *hecho el 29, ver abajo.*
2. **El bot pisa lo que la persona dice.** A un «Buena tarde» lo trató
   como respuesta a la primera pregunta y disparó la segunda. A un «Hola,
   quiero contarles algo» le respondió con el guion en vez de escuchar.
   — *hecho el 29.*
3. **Acusar recibo siempre.** Quien escribió la respuesta más larga y más
   cálida recibió la siguiente pregunta sin una palabra de vuelta; los que
   terminaron sí recibieron un «Me alegra mucho que te guste» antes.
   — *hecho el 29.*
4. **Distinguir la burbuja del enlace**, para que el embudo se pueda leer.
   — **pendiente.** Sin esto no se puede saber si el saludo nuevo sirvió:
   los 42 chats de la medición mezclan enlaces de WhatsApp con toques
   curiosos a la burbuja de tumbaobaila.com.

### Cuidado con el tamaño de la muestra

Descontando el 3 y el 12 de agosto, que son días de desarrollo, quedan
unas 25 aperturas reales en dos semanas y un puñado de personas que
escribieron. Es poquísimo para concluir nada sobre las preguntas. Sobre
lo que sí alcanza es para el punto 1, que no es estadística: es una
opinión concreta que llegó y se perdió.

## 29 de agosto: se guarda aunque cierren la pestaña

Ahora hay dos capas, y la primera es la que cumple la promesa.

**1. Cada turno escribe.** Al terminar cada turno, `guardarAvance` deja
en la fila la conversación entera y un resumen provisional que son las
palabras de la persona, tal cual las escribió. Sin modelo, sin coste y
sin depender de nada posterior. A partir de ahí da igual si cierra la
pestaña, si se cae el modelo o si se va la luz: **quien contesta aunque
sea una sola pregunta sale en el reporte del lunes con lo que dijo.**

**2. El barrido.** `completarAbandonadas` convierte eso en una ficha de
verdad —tipo, nombre, celular, si es urgente— y corre cuando alguien
lee: al pedir `/api/pendientes` y al abrir `/leer`. Lee de `mensajes`,
que es la tabla que nunca se dejó de escribir, así que también rescata
las conversaciones viejas que quedaron con todo en NULL. La del 21 de
agosto entre ellas.

Solo toca conversaciones calladas hace más de 30 minutos: si Tania abre
`/leer` mientras alguien está contestando, no puede darle esa
conversación por terminada. Y **no las marca como completas**, porque no
lo están: en `/leer` siguen saliendo con la etiqueta «se cortó». Marcarlas
taparía el dato de cuánta gente se va a mitad de camino.

### Lo que se descartó, y por qué

- **Clasificar en cada turno** (con `ctx.waitUntil`): una llamada al
  modelo por mensaje, o sea multiplicar por tres o cuatro el coste de
  cada conversación, para acabar tirando todas las fichas menos la
  última. El barrido la saca una vez, cuando ya se sabe que no va a
  haber más mensajes.
- **Un aviso del navegador al cerrar** (`sendBeacon`): el arreglo no
  puede depender del navegador, que es justo el que se está yendo. En
  iOS ese aviso se pierde la mitad de las veces.
- **Un cron que barra solo**: un despliegue más y una cosa más que se
  puede quedar sin secreto y fallar en silencio, que es exactamente lo
  que pasó con el reporte del lunes 17. Colgado de la lectura, si falla
  falla delante de quien está mirando.

### El detalle que muerde: la transcripción no encoge

La página guarda la conversación en memoria y se la manda entera en cada
turno. Si la persona **recarga**, esa memoria arranca de cero y el turno
siguiente traería solo la mitad final. Por eso tanto `guardarAvance`
como `/api/cerrar` solo escriben la transcripción **si es más larga que
la guardada**. Sin esa comparación, recargar borraría lo ya contado.

## El saludo, y que el bot no atropelle

El saludo anterior era «Nos ayuda muchísimo saber cómo lo estás
viviendo». Habla de nosotros: qué nos ayuda a nosotros, no qué gana la
persona ni a quién le llega lo que escriba. Y «soy de Tumbao» no es
nadie.

El de ahora dice tres cosas, en este orden: **para qué** se pregunta
(vamos a cambiar cosas y preferimos preguntar antes que adivinar), **a
quién** le llega (lo leemos nosotras, no un robot) y **cuánto cuesta** (con una frase
basta), y termina en la primera pregunta. Que le pregunten a uno antes
de decidir halaga, y es verdad.

Lo mismo va en la vista previa de WhatsApp —`<title>`, `description` y
las `og:`—, que es lo primero que se ve, antes que el saludo. Decía «Dos
minutos para contarnos cómo te ha ido»: anunciaba trabajo y encima
contradecía al saludo, que promete que con una frase basta.

**Que no atropelle.** Pedírselo al guion no alcanza: ya tenía
instrucciones de conversar y aun así a un «Buena tarde» le contestó con
la pregunta 2. `esArranque()` reconoce los saludos pelados y los «quiero
contarles algo», y con eso hace dos cosas que no dependen del modelo:
le mete al guion, solo en ese turno, un aviso de que no avance; y no los
cuenta como una de las cuatro respuestas que hacen falta para poder
cerrar —si contaran, un «Buenas tardes» adelantaría el cierre un paso y
la conversación terminaría con una pregunta sin hacer—.

**Que siempre acuse recibo.** `conAcuse()` mira si el mensaje del bot
empieza directamente en la pregunta y, si es así, le antepone una línea.
El acuse fijo es sobrio a propósito («Gracias por contarme»): cualquier
otro —«qué bueno», «qué pesar»— se equivoca la mitad de las veces, y
equivocarse de emoción es peor que ser sobrio. No se le pone a quien
apenas saludó: detrás de un «hola» suena a máquina.

## Por qué el saludo arranca con la pregunta

Hasta el 17 de agosto lo primero que pedía el bot era el nombre. En dos
días seis personas abrieron el chat y **ninguna escribió una palabra**.

Tiene sentido: pedir el nombre cuesta algo y no devuelve nada, y en una
página web —a diferencia de un enlace que te llega por WhatsApp— se lo
estás dando a un desconocido. Encima el saludo anunciaba "son tres
preguntas", que es avisar de trabajo antes de dar una razón.

Ahora lo primero que ve la persona es la pregunta de verdad, que se
contesta en tres palabras. El nombre se pide **al final**, junto con el
celular, cuando ya contó algo y darlo tiene sentido. Se prefiere una
opinión anónima de verdad antes que un nombre sin opinión.

El saludo referencia `LAS_TRES[0]`, así que la pregunta del saludo y la
primera del guion no pueden separarse.

Ojo con una cosa al leer los números: **la fila se crea cuando alguien
abre el chat**, no cuando escribe. Al cargar, la página pide el saludo
y eso ya cuenta como turno 1. Por eso `turnos > 1` es el filtro de "esta
persona sí escribió", y una conversación de un turno significa que la
abrió y se fue sin teclear.

## Dónde se ven los resultados

`opina.tumbaobaila.com/leer?token=…` — la misma llave `TOKEN_REPORTE`.

Arriba, **las tres cosas de la semana**: un titular, hasta tres tarjetas
con lo que se repite, lo crítico si lo hay, y una frase textual. Debajo,
las conversaciones una por una, como siempre.

Hasta ahora ese análisis solo existía **dentro del correo del lunes**.
Si el correo no llegaba —y no llegó cinco días— no había ningún sitio
donde mirarlo, y entre semana no había forma de ver qué está diciendo la
gente sin leerse las conversaciones a mano.

CÓMO SE CALCULA
Lo hace el propio Worker con Workers AI, que no necesita llave de nadie.
Si hay `OPENAI_API_KEY` la usa; si no, Workers AI. El resultado se guarda
en la caché de Cloudflare con una huella —cuántas conversaciones y cuál
es la última—, así que abrir la página diez veces no cuesta diez
análisis. Cuando entra material nuevo la huella cambia y se recalcula
solo. El enlace *volver a calcular* fuerza el recálculo.

Se usa la caché y no una tabla a propósito: esto es un resultado, no un
dato. Si se pierde se vuelve a calcular y no pasa nada.

QUÉ VENTANA MIRA
Los últimos 7 días. Si esa semana no dio para nada, **no enseña tarjetas
vacías ni disfraza material viejo de reciente**: cae hacia atrás a lo
último que sí hubo y lo dice con todas las letras («Esta semana no hubo
nada nuevo. Esto es lo último que hubo: …»).

Con menos de dos conversaciones con contenido no analiza nada y lo dice.
Con una sola, cualquier «patrón» es esa persona, y una tarjeta inventada
quema la confianza en toda la pantalla. Por lo mismo el guion permite
devolver UNA sola cosa clave: rellenar hasta tres es peor que quedarse
corto.

QUE NO SE CAIGA
El análisis va en su propio `try`. Si el modelo no contesta o devuelve
algo que no parsea, la página sale igual con las conversaciones y un
aviso de una línea. Perder el resumen es un fastidio; perder el acceso a
lo que la gente contó, no.

Y el texto de las tarjetas lo escribe un modelo, no nosotros: entra al
HTML escapado. `pruebas/semana.test.mjs` lo comprueba metiéndole
`<script>` por cada campo.

## Dónde se invita a contarnos

Dos sitios, y el segundo es el que importa:

- **El globito de la burbuja**, en `tumbaobaila.com`. Sale una sola vez
  por persona, a los 6 segundos, y **solo en la pantalla de inicio**.
  Antes salía pasara lo que pasara y le caía encima a quien estaba
  escribiendo su nombre o mirando el QR para pagar.
- **La pantalla de confirmación**, cuando la reserva quedó lista. Es el
  único momento en que se sabe que la persona viene a Tumbao de verdad
  y que ya terminó lo que vino a hacer. Lleva la pregunta escrita, no
  un "cuéntanos cómo te ha ido": una pregunta se contesta, una fórmula
  vaga obliga a inventar qué decir.

Solo se ofrece si el pago quedó confirmado —a quien tiene el pago en el
aire hay que dejarlo resolver eso— y desaparece para siempre en cuanto
la persona abre el chat una vez.

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

    node pruebas/no-se-pierde.test.mjs           # la opinión que cierra la pestaña
    node pruebas/saludo.test.mjs                 # el gancho y que no atropelle
    node pruebas/ficha.test.mjs                  # 38, la ficha del lunes
    node pruebas/limpiar-transcripcion.test.mjs  # 14, alucinaciones de Whisper
    node pruebas/semana.test.mjs                 # las tres cosas de la semana

Las dos primeras corren el Worker entero contra una SQLite de verdad
—`node:sqlite`, viene con Node— cargada con este mismo `schema.sql`.
`pruebas/entorno-falso.mjs` es el andamio, no una prueba. Se hizo así
porque lo que se rompió el 21 de agosto no fue ninguna función: fue que
`/api/cerrar` nunca se llamó. Para probar eso hay que hacer lo que hizo
la clienta —abrir, contestar, irse— y pedir después el reporte.

## Desplegar

    npx wrangler deploy
    npx wrangler d1 execute tumbao-opina --remote --file=schema.sql
