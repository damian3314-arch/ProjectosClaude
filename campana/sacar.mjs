import pw from 'playwright-core';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
const { chromium } = pw;
const aqui = dirname(fileURLToPath(import.meta.url));
const cuales = process.argv.slice(2);
const nav = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
const ctx = await nav.newContext({ viewport: { width: 1080, height: 1920 }, deviceScaleFactor: 1 });
const pag = await ctx.newPage();
for (const id of (cuales.length ? cuales : ['p1','p2','p3'])) {
  await pag.goto('file://' + join(aqui, 'pieza.html') + '?p=' + id);
  await pag.evaluate(() => document.fonts.ready);
  await pag.waitForTimeout(400);
  await pag.screenshot({ path: join(aqui, `marca-${id}.png`) });
  console.log('listo marca-' + id + '.png');
}
await nav.close();
