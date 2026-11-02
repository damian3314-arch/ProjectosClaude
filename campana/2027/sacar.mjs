/** Exporta las piezas de piezas.html a JPG en salida/.  node sacar.mjs */
import { chromium } from '../../tumbao-reservas/node_modules/playwright-core/index.mjs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
const AQUI = dirname(fileURLToPath(import.meta.url));
const NOMBRES = { p1: 'feed-1-no-empieces-en-enero', p2: 'historia-2-lo-has-intentado', p3: 'feed-3-tu-constancia-tiene-premio', p4: 'historia-4-rumbo-a-2027' };
const nav = await chromium.launch({ executablePath: process.env.CHROMIUM || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--no-sandbox'] });
const pg = await nav.newPage({ viewport: { width: 1080, height: 1920 } });
for (const id of Object.keys(NOMBRES)) {
  await pg.goto('file://' + join(AQUI, 'piezas.html') + '?p=' + id);
  await pg.evaluate(() => document.fonts.ready);
  await pg.waitForTimeout(300);
  await pg.locator('.pieza').screenshot({ path: join(AQUI, 'salida', NOMBRES[id] + '.jpg'), type: 'jpeg', quality: 92 });
  console.log('✓', NOMBRES[id]);
}
await nav.close();
