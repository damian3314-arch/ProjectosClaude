# Revisión de la landing de Corónate · 10 de noviembre de 2026

**Qué se revisó:** la versión de `coronate/` en la rama `claude/n8n-pdf-report-delay-1v4yym` (último commit `c1224ac`, 27 minutos antes de la revisión).
**Cómo:** (1) lectura del código, (2) pruebas en navegador en celular (390 px) y escritorio, versión premium y general, (3) dos lectores sin contexto del proyecto (uno que hace de cliente, otro que evalúa alcance), a partir de un resumen escrito del recorrido del cliente.
**Qué NO se revisó:** `panel.html`, `assets/asesoras.js` (47 KB), `creativo.html`, `grabacion.html`, `apps-script/Code.gs` (sin probar), el aspecto en celulares reales y dentro del navegador de WhatsApp, la velocidad de carga con datos móviles.

## Resumen en una frase
La página abre bien y no tiene errores de consola ni de seguridad. Tenía **tres fallos que impedían o ensuciaban la cita** y ya están corregidos en un parche pequeño (3 archivos). Lo demás es criterio de diseño o datos que faltan y lo decide Damián con Tania.

## Cambios aplicados en el parche (`landing-fixes.patch`), todos probados

| # | Problema | Dónde se veía | Qué se cambió |
|---|---|---|---|
| 1 | El pie mostraba `[DIRECCIÓN]` literal | Pie de página, las dos versiones | Cualquier dato de `config.js` que tenga corchetes se oculta en vez de mostrarse. **La dirección real sigue faltando.** |
| 2 | El mensaje de WhatsApp salía con `[hora]` (y `[tu nombre]` en premium sin nombre) | Botón del resultado | Sin corchetes. Premium: «¿Qué horas tienen disponibles para apartarme el cupo?». General: «¿Qué sábados y qué horas tienen disponibles…?» |
| 3 | Quien no marcaba ninguna bandera quedaba atrapado: botón «Ver mi resultado» apagado, y sin botón Agendar ni preguntas | Test | El botón siempre está activo. Con 0 banderas se llega al resultado. «Agendar» y las preguntas son visibles desde la portada. |
| 4 | La versión general decía «este sábado», ambiguo si abren el link otro día | Texto del resultado | «cualquier sábado hasta el 26 de diciembre» |
| 5 | La Corona (cerveza) se mencionaba sin edad en el resultado | Texto del resultado | «(solo mayores de 18, con documento)» |
| 6 | Botón «Agendar» de 38 px (mínimo recomendado 44 px) | Encabezado | 44 px |

**Prueba después del cambio:** sin corchetes visibles ni en los enlaces, en premium, premium sin nombre y general; sin desbordamiento horizontal; 0 errores de consola; la inyección de HTML en el nombre sigue sin efecto; el camino con 2 banderas sigue igual. «Lo que te espera» sigue oculto hasta ver el resultado, como estaba diseñado.

## Decisiones que NO se tomaron (las toma Damián con Tania)

| Tema | Qué dijeron los lectores | Por qué no se tocó |
|---|---|---|
| **Dirección real** | Sin dirección no hay visita. Bloqueante si el cliente no conoce el local. | No tengo el dato. Hay que cargarla en `config.js › contacto.direccion`. |
| **Tono del test** («olor a tradición», «jabón pegado desde el día del sí», «huelen a recuerdo», «pide auxilio») | Puede leerse como que el cliente es descuidado; el chiste del «sí» incomoda a quien está viudo o separado. | Es la voz que Tania aprobó. Se señala, no se cambia. |
| **Bandera 5 «broche flojo»** | El shampoo no arregla un broche; la promesa no coincide con el servicio. | Es de contenido. Si se deja, enlazar con la soldadura ($40.000). |
| **Precio en la portada general** | El cliente hace el test pensando que es regalo y se entera del $30.000 al final. | Si se quiere transparencia, poner el precio en la portada general. Decisión de Tania. |
| **Qué es el shampoo de brillo** | No explica cuánto tarda ni que se hace en el local. | Falta el dato (minutos). Una línea basta. |
| **«Lo que te espera» oculto hasta el resultado** | Ocultar contenido sin necesidad añade estados que probar. | Es el efecto «revelación» que Damián quiere. Se respetó. |
| **Dos versiones con textos distintos** (premium vs general) | Riesgo de que queden diferencias accidentales. | Congelar la lista de diferencias a: nombre, precio del shampoo, fecha. |

## Pendientes técnicos para antes de producción
1. `config.js › avisos` está vacío: nadie recibe aviso de que un cliente hizo el test. Hoy el único rastro es el WhatsApp.
2. Los precios `$40.000` y «desde $20.000» están escritos dentro de `landing.js` y no leen `config.js`. Si cambian, hay que editarlos en tres lugares (perks, FAQ premium, FAQ general).
3. `assets/asesoras.js` (línea ~450): una respuesta para clientes dice «tienen un valor de [CONFIRMAR] cada una». Si una asesora la copia, el cliente la ve con el corchete.
4. `apps-script/Code.gs` no se ha probado.
5. No hay forma de saber con qué texto abrió el cliente: el link premium no registra aperturas.

## Qué congelar desde ahora
Más de 20 cambios en 27 horas, 12 de ellos en la última hora y media. Recomendación de los dos lectores y mía:
1. **Visuales y animación** (paleta, moño, botella, nieve, banda): ningún cambio hasta después del lanzamiento del 21.
2. **Textos y precios:** una sola persona (Tania) aprueba la lista final. Después solo se corrigen datos de hecho: dirección, fecha, hora, número.
3. **Flujo:** se hizo un solo cambio (salida siempre disponible). Cualquier idea nueva va a una lista para después del primer sábado.

## Cómo aplicar el parche (lo hace el chat `[CORO]` en su rama)
```bash
git fetch origin claude/wizardly-fermi-3wpram
git checkout origin/claude/wizardly-fermi-3wpram -- coronate-review/landing-fixes.patch
git apply coronate-review/landing-fixes.patch
```
Se verificó con `git apply --check` sobre la rama `claude/n8n-pdf-report-delay-1v4yym` en `c1224ac`: se aplica limpio.
