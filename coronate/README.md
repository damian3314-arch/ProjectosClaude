# Sábados de Realeza · landing + panel (Joyería Tanya Santiago)

Sitio estático, sin build ni dependencias. Tres piezas:

| Archivo | Para quién | Qué hace |
|---|---|---|
| `index.html` | Clientes | Landing navideña: saludo por nombre, cuenta regresiva, test de banderas rojas, fechas, formulario de cita, preguntas |
| `panel.html#ase` | Asesoras | Lista de clientes, plantillas, botón de WhatsApp con el mensaje ya armado, tarjeta personalizada en PNG |
| `panel.html#adm` | Propietaria | KPIs, semáforo por fecha, línea de tiempo, citas, lista de preparación, copia de seguridad |
| `panel.html#cre` | Creativo | Carpeta de Drive, idea y paleta, piezas por producir, tarjeta, banco de textos |

## Probar en local

```bash
cd coronate
python3 -m http.server 8080
```

Abre `http://localhost:8080/index.html` y `http://localhost:8080/panel.html`.
Link personalizado: `index.html?n=Carlos`. Día de prueba (14 nov): agrega `&p=1`.

## Lo primero que debes completar (`assets/config.js`)

- `contacto.whatsapp` (formato `573001234567`), `direccion`, `horario`
- `agenda.inicio`, `agenda.fin`, `agenda.cuposPorBloque`
- `bebidas` y `mostrarSnacks` según lo que se confirme
- Domingo de noviembre: descomenta la línea en `fechas`
- `drive.carpeta`

## Límites que debes conocer

1. **Los datos viven en el navegador de cada persona (localStorage).** Una asesora no ve la lista de otra y la propietaria no ve las citas hechas en el celular de un cliente. Para eso existe el paso del Apps Script (abajo) y, más adelante, una base de datos.
2. **El panel no tiene contraseña.** Cuando se publique, protégelo (Cloudflare Access) o no lo publiques.
3. **El repo es público: nunca subas listas de clientes ni teléfonos.** Las listas se pegan en el panel y quedan solo en el navegador.
4. **Cita real en Calendar:** `apps-script/Code.gs` guarda cada cita en una hoja y crea el evento en Google Calendar. No está probado: pruébalo antes del 14 de nov.
5. **WhatsApp:** el botón abre el chat con el mensaje listo, pero la asesora envía cada uno a mano desde la línea de la joyería. Eso no es un envío masivo oficial. Conviene espaciar los envíos y escribirle solo a clientes que ya tuvieron contacto. Cada plantilla incluye "responde BAJA".
6. La imagen no se adjunta sola (WhatsApp no lo permite por link). En celular, "Compartir" abre WhatsApp con la imagen; en computador se descarga y se adjunta.
7. Se pide autorización de datos en el formulario (Ley 1581 de 2012). Confirma el texto con tu asesor.

## Publicar (cuando decidas)

Cloudflare Pages: carpeta raíz `coronate`, sin comando de build. Después pon la URL en `config.js > baseUrl` para que los links de las plantillas apunten a la página publicada.
