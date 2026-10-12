# Brag · tumbaobaila.com

**Formato:** vertical 1080×1920, 30 fps, 22,5 s (12 compases de 128 BPM: un compás = 1,875 s, un tiempo = 0,46875 s).

**v2 (12 oct):** Damián pidió música con más fuerza y más rápida, efectos en las transiciones y el copy de la campaña de constancia (la de la tiquetera) en vez de «tu clase te espera».

**v3 (12 oct):** la música sintetizada no le gustó: el video lleva solo los efectos (`assets/efectos.wav`) y la música se pone al publicar. Letras más pequeñas; en el cierre el logo (vectorizado a `assets/logo.svg` para que no se pixele) es lo más grande: 960 px de ancho.
**Tono:** `default` empujado hacia el Instagram de Tumbao: neón, titulares en letra condensada gruesa, cortes al ritmo.
**Idioma:** español (Barrancabermeja).

## Qué es (una frase)
La página donde reservas tu clase de baile en Tumbao en un minuto: escoges día y hora, pagas con QR o llave Bre-B y te queda tu código.

## Las respuestas
- **Para quién:** gente de Barrancabermeja que quiere bailar (rumba, clases grupales) y las alumnas de Tumbao.
- **Qué la hace distinta:** reservas sola, sin llamar ni esperar respuesta. Tres pasos: Reserva → Paga → Listo.
- **La frase más fuerte (de la misma página):** «Reserva tu clase en un minuto».
- **Gancho:** el copy de la campaña de constancia: «Los objetivos no se cumplen con ganas» (palabra por palabra; «con ganas» se prende en neón y se tacha) → caída: «se cumplen con CONSTANCIA» → «Rétate a seguir».
- **UI real que se muestra:** capturas de la página ya rediseñada (dark neón): ¿Cómo vienes? → toque en *Clase suelta* → ¿Cuándo quieres bailar? → toque en *5:00 pm Rumba básica* → *Paga tu clase* ($15.000 + QR) → *¡Tu cupo está apartado!* con el código.
- **Texto para publicar:** ver `share-copy.txt`.

## Identidad visual
- Fondo `#0b0710` (casi negro con tinte morado), resplandores de luz morada `#8f3dff` y fucsia `#ff2e8f`, tiras de neón en diagonal como las luces del techo del salón.
- Naranja del logo `#ff6b35` y fucsia `#ff2e8f`; el degradado naranja→fucsia se usa en el número de cada paso y en la píldora de la URL.
- **Sin fondo lila.** El morado solo aparece como luz.
- Letra: **Anton** (condensada, como los titulares de los Reels) para los títulos y **Outfit** (la de la página) para el texto.

## Guion (escena por escena)

| # | Tiempo | Qué se ve | Texto que se lee | Sonido |
|---|---|---|---|---|
| 1 · Gancho | 0–3,75 | Las tiras de neón se prenden; las palabras entran a corcheas; «con ganas» se prende en neón y a los 3,05 s se tacha con una raya de luz | LOS OBJETIVOS / NO SE CUMPLEN / ~~CON GANAS~~ | zumbido del neón, intro filtrada, subida con redoble que se acelera, chispazo al tachar |
| 2 · Caída | 3,75–5,625 | Destello y golpe; el texto entra grande con sacudida; las tiras laten con el bombo | SE CUMPLEN CON **CONSTANCIA** | golpe + platillo; entra todo el ritmo |
| 3 · Reto | 5,625–7,5 | «RÉTATE» y «A SEGUIR» en la caja fucsia | RÉTATE **A SEGUIR** · Reserva en un minuto | barrido |
| 4 · Reserva | 7,5–11,25 | Sube el celular con la página real; toque en *Clase suelta* (8,906) → horarios → toque en *5:00 pm Rumba básica* (10,781) | **1 · RESERVA** · Escoge el día y la hora | barrido, «pop» del número, toques, barrido corto al cambiar de pantalla |
| 5 · Paga | 11,25–14,06 | *Paga tu clase*: baja hasta el QR y una línea de neón lo escanea | **2 · PAGA** · Con QR o llave Bre-B | barrido corto, «pop», bip-bip |
| 6 · Listo | 14,06–16,875 | *¡Tu cupo está apartado!*, código en neón y chispas | **3 · LISTO** · Tu cupo queda apartado | barrido corto, «pop», campanitas; segunda subida |
| 7 · Cierre | 16,875–22,5 | Destello y golpe; la frase de la campaña entra a tiempos; el logo se prende en neón; «Reserva tu clase en» + píldora con toque | CUANDO NO TE DETIENES, **SIEMPRE LLEGAN COSAS BUENAS** · Reserva tu clase en tumbaobaila.com | golpe + platillo, ritmo completo con melodía, zumbido y destello del logo, toque, golpe final |

## Legibilidad
Cada línea queda quieta al menos 0,3 s por palabra después de entrar completa. Los textos clave van arriba (zona 230–600 px) para no chocar con la interfaz de Reels abajo y a la derecha; el celular puede bajar hasta el borde porque es imagen, no texto.

## Datos
Nada real de clientes: el nombre «Camila Rojas» y el código «TB7K2Q» son de muestra. Los horarios, precio y QR son los públicos de la página.

## Sonido

Solo efectos, en cada transición (`work/musica.py --solo-efectos` → `composition/assets/efectos.wav`): zumbido del neón, subida y chispazo al tachar «con ganas», golpes con destello en «CONSTANCIA» y en el cierre, barridos que cruzan de izquierda a derecha, «pops» al cambiar de paso, toques, bip-bip del QR, campanitas y el destello del logo. La música va aparte: la biblioteca de Instagram al publicar, o una pista que escoja Damián (los cortes están a 128 BPM). `work/musica.py` sin la bandera todavía genera la pista sintetizada de la v2 por si se quiere comparar.
