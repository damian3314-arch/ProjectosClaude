/** Exporta los flyers de los pases (flyers.html) a JPG en salida/flyers/.  node sacar-flyers.mjs */
import { chromium } from '../../tumbao-reservas/node_modules/playwright-core/index.mjs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { mkdirSync } from 'node:fs';
const AQUI = dirname(fileURLToPath(import.meta.url));
const NOMBRES = { mensualidad: 'flyer-mensualidad', 8: 'flyer-tiquetera-8-clases', 4: 'flyer-tiquetera-4-clases' };
mkdirSync(join(AQUI, 'salida', 'flyers'), { recursive: true });
const nav = await chromium.launch({ executablePath: process.env.CHROMIUM || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--no-sandbox'] });
const pg = await nav.newPage({ viewport: { width: 1080, height: 1780 } });
for (const id of Object.keys(NOMBRES)) {
  await pg.goto('file://' + join(AQUI, 'flyers.html') + '?f=' + id);
  await pg.evaluate(() => document.fonts.ready);
  await pg.waitForTimeout(400);
  await pg.locator('.pieza').screenshot({ path: join(AQUI, 'salida', 'flyers', NOMBRES[id] + '.jpg'), type: 'jpeg', quality: 93 });
  console.log('✓', NOMBRES[id]);
}
await nav.close();
