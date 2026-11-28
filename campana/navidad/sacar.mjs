/** Saca el saludo de Navidad a JPG en salida/.  node sacar.mjs */
import { chromium } from '../../tumbao-reservas/node_modules/playwright-core/index.mjs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
const AQUI = dirname(fileURLToPath(import.meta.url));
const SALIDAS = { story: ['navidad-historia', 1920], feed: ['navidad-feed', 1350] };
const nav = await chromium.launch({ executablePath: process.env.CHROMIUM || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--no-sandbox'] });
for (const [f, [nombre, alto]] of Object.entries(SALIDAS)) {
  const pg = await nav.newPage({ viewport: { width: 1080, height: alto } });
  await pg.goto('file://' + join(AQUI, 'pieza.html') + '?f=' + f);
  await pg.evaluate(() => document.fonts.ready);
  await pg.waitForTimeout(300);
  await pg.screenshot({ path: join(AQUI, 'salida', nombre + '.jpg'), type: 'jpeg', quality: 92 });
  console.log('✓', nombre);
}
await nav.close();
