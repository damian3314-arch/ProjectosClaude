/**
 * Las tres cosas de la semana — la parte que se puede probar sin modelo.
 *
 * LO QUE MIDE
 * Dos cosas distintas:
 *
 * 1. QUÉ SE ANALIZA. "La semana" tiene que ser la semana, y cuando la
 *    semana está vacía hay que decirlo en vez de disfrazar material
 *    viejo de reciente.
 * 2. QUE LO QUE DEVUELVE EL MODELO NO ROMPA LA PÁGINA. Ese texto no lo
 *    escribimos nosotros: entra tal cual en el HTML. Si un resumen trae
 *    un <script>, la página es del modelo y no nuestra.
 *
 * Se corre solo:  node pruebas/semana.test.mjs
 */
import { loQueSeAnaliza, arriba } from '../src/index.js';

let fallos = 0;
const ok = (n, c, extra = '') => {
  console.log(`  ${c ? '\x1b[32mv\x1b[0m' : '\x1b[31mx\x1b[0m'} ${n}${extra ? '  → ' + extra : ''}`);
  if (!c) fallos++;
};
const hace = (dias) => new Date(Date.now() - dias * 86400000).toISOString();
const conv = (dias, resumen = 'dijo algo', extra = {}) =>
  ({ empezada_at: hace(dias), turnos: 4, resumen, ...extra });

console.log('\n-- 1. Qué entra en las tarjetas -----------------------------');

{
  const r = loQueSeAnaliza([conv(1), conv(2), conv(3)]);
  ok('con material de esta semana, se analiza esta semana',
     r.fresco === true && r.filas.length === 3, `${r.filas.length} · ${r.ventana}`);
  ok('y lo dice con esas palabras', /7 días/.test(r.ventana), r.ventana);
}

{
  // Lo que hay hoy en producción: todo es de hace más de una semana.
  const r = loQueSeAnaliza([conv(20), conv(25), conv(30)]);
  ok('sin nada esta semana, cae hacia atrás', r.filas.length === 3);
  ok('pero NO finge que es de esta semana', r.fresco === false);
  ok('y dice de cuándo es de verdad', /—/.test(r.ventana), r.ventana);
}

{
  // Una sola opinión no es un patrón: es una persona. Sacar "tres cosas
  // clave" de ahí es inventarlas, y una tarjeta inventada quema la
  // confianza en toda la pantalla.
  const r = loQueSeAnaliza([conv(1)]);
  ok('con una sola conversación no se analiza nada', r.filas.length === 0);
  ok('y no se inventa una ventana', r.ventana === null);
}

{
  const r = loQueSeAnaliza([]);
  ok('sin nada, tampoco revienta', r.filas.length === 0 && r.ventana === null);
}

{
  // Las de un turno son alguien que abrió el chat y se fue. Ya se
  // filtran en la lista de abajo; aquí también, o el "cuantos de
  // cuantos" del modelo saldría inflado.
  const r = loQueSeAnaliza([
    conv(1), conv(1),
    { empezada_at: hace(1), turnos: 1, resumen: null },
    { empezada_at: hace(1), turnos: 1, resumen: null },
  ]);
  ok('las que no pasaron del saludo no cuentan', r.filas.length === 2,
     `${r.filas.length} de 4`);
}

{
  // El corte es de 7 días. Una de hace ocho no es de esta semana.
  const r = loQueSeAnaliza([conv(1), conv(2), conv(8), conv(9)]);
  ok('el corte de los 7 días se respeta', r.filas.length === 2 && r.fresco,
     `${r.filas.length} dentro`);
}

{
  // Con muchas viejas no se le manda el archivo entero al modelo.
  const muchas = Array.from({ length: 40 }, (_, i) => conv(20 + i));
  const r = loQueSeAnaliza(muchas);
  ok('el respaldo se queda en 12, no manda 40', r.filas.length === 12,
     `${r.filas.length}`);
  ok('y son las más nuevas',
     r.filas[0].empezada_at > r.filas[11].empezada_at);
}

console.log('\n-- 2. Lo que devuelve el modelo no manda en la página -------');

{
  const html = arriba({ fresco: true, ventana: 'los últimos 7 días', token: 'T',
    datos: {
      titular: 'Tres personas dijeron que el salón queda apretado',
      claves: [{ titulo: 'Salón apretado', detalle: 'A las 7 pm no se cabe.',
                 cuantos: '3 de 7 personas' }],
      critico: null,
      cita: 'A las 7 no se cabe',
    } });
  ok('el titular se ve', html.includes('el salón queda apretado'));
  ok('la tarjeta se ve', html.includes('Salón apretado'));
  ok('el cuántos se ve', html.includes('3 de 7 personas'));
  ok('la cita se ve', html.includes('A las 7 no se cabe'));
}

{
  // El caso que importa: el texto viene de un modelo, no de nosotros.
  const html = arriba({ fresco: true, ventana: 'x', token: 'T', datos: {
    titular: '<script>alert(1)</script>',
    claves: [{ titulo: '<img src=x onerror=alert(2)>', detalle: '"><b>hola',
               cuantos: '<i>1</i>' }],
    critico: { que: '<script>3</script>', por_que: '<script>4</script>' },
    cita: '<script>5</script>',
  } });
  // Lo que hay que comprobar es que no se forme NINGUNA etiqueta con lo
  // que mandó el modelo. Que la palabra "onerror" aparezca como texto
  // visible no es un problema: sin un "<" sin escapar no hay etiqueta
  // donde colgarla, y buscarla daría un fallo donde no lo hay.
  ok('no se cuela ninguna etiqueta',
     !/<(script|img|svg|iframe|style)\b/i.test(html));
  ok('pero el texto sí se lee, escapado', html.includes('&lt;script&gt;'));
}

{
  // Un modelo pequeño puede devolver cinco. La pantalla es de tres.
  const cinco = Array.from({ length: 5 }, (_, i) =>
    ({ titulo: `Cosa ${i}`, detalle: 'd', cuantos: '1' }));
  const html = arriba({ fresco: true, ventana: 'x', token: 'T',
                        datos: { titular: 't', claves: cinco } });
  ok('nunca más de tres tarjetas',
     (html.match(/class="clave"/g) || []).length === 3,
     `${(html.match(/class="clave"/g) || []).length}`);
}

{
  // Un modelo que devuelve media ficha no puede dejar la página a medias.
  const html = arriba({ fresco: true, ventana: 'x', token: 'T',
                        datos: { titular: 'solo esto' } });
  ok('sin claves ni cita, sigue saliendo el titular',
     /olo esto/.test(html) && !html.includes('class="clave"'));
  // Los modelos pequeños lo devuelven en minúscula la mitad de las
  // veces. Es lo primero que se lee de la pantalla.
  ok('y el titular arranca en mayúscula', html.includes('>Solo esto<'),
     (html.match(/class="titular">([^<]*)/) || [])[1]);
}

{
  const html = arriba({ fresco: false, ventana: '3 ago — 12 ago', token: 'T',
                        datos: { titular: 't', claves: [] } });
  ok('cuando es material viejo, la página lo dice',
     /no hubo nada nuevo/i.test(html), html.match(/Esta semana[^<·]*/)?.[0]);
}

{
  const html = arriba({ error: 'Analizar 500', token: 'T' });
  ok('si el modelo falla, se dice y no se cae', /No se pudo/.test(html));
  ok('y se nombra el motivo', html.includes('Analizar 500'));
}

{
  const html = arriba({ datos: null, conCuantas: 1, token: 'T' });
  ok('con poco material se dice, no se inventa',
     /Todavía no hay material/.test(html) && !html.includes('class="clave"'));
}

ok('sin análisis no estorba', arriba(null) === '');

console.log(`\n${fallos === 0 ? '\x1b[32mtodo en verde\x1b[0m' : `\x1b[31m${fallos} FALLOS\x1b[0m`}`);
process.exit(fallos ? 1 : 0);
