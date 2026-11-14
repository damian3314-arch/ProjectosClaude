/**
 * Exporta las piezas de piezas.html a PNG en salida/ (una por id).
 *   node sacar.mjs
 */
import { chromium } from '../../tumbao-reservas/node_modules/playwright-core/index.mjs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const AQUI = dirname(fileURLToPath(import.meta.url));
// 26 oct: se retiraron las piezas que ofrecían clases adicionales por constancia (c1, c4, c5, f1, f2, h1): la dueña no lo aprobó.
const IDS = ['c2', 'c3', 'h2', 'h3', 'r1', 'r2', 'r3', 'n1', 'n2', 'n3', 'w1', 'w2', 'w3'];
const NOMBRES = {
  c1: 'carrusel-1-portada', c2: 'carrusel-2-elige', c3: 'carrusel-3-reserva', c4: 'carrusel-4-completa', c5: 'carrusel-5-clases-adicionales',
  f1: 'fija-tiquetera-8', f2: 'fija-tiquetera-4', h1: 'historia-constancia', h2: 'historia-halloween', h3: 'historia-mensualidad',
  r1: 'anuncio-1-noviembre-se-baila', r2: 'anuncio-2-eliges-tu-pase', r3: 'anuncio-3-historia-noviembre',
  n1: 'navidad-1-noviembre-se-baila', n2: 'navidad-2-elige-como-bailar', n3: 'navidad-3-historia-noviembre',
  w1: 'web-1-noviembre-se-baila', w2: 'web-2-elige-como-bailar', w3: 'web-3-historia-noviembre',
};
const nav = await chromium.launch({ executablePath: process.env.CHROMIUM || '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });
const p = await nav.newPage({ viewport: { width: 1080, height: 1920 } });
for (const id of IDS) {
  await p.goto('file://' + join(AQUI, 'piezas.html') + '?p=' + id);
  await p.evaluate(() => document.fonts.ready);
  await p.waitForTimeout(250);
  await p.locator('.pieza').screenshot({ path: join(AQUI, 'salida', NOMBRES[id] + '.png') });
  console.log('✓', NOMBRES[id]);
}
await nav.close();
