/** Renderiza los videos de videos.html cuadro a cuadro y los une con ffmpeg → salida/videos/*.mp4.  node videos.mjs [v1 v2 v3 v4] */
import { chromium } from '../../tumbao-reservas/node_modules/playwright-core/index.mjs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { mkdirSync, rmSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
const AQUI = dirname(fileURLToPath(import.meta.url));
const NOMBRES = { v1: 'video-1-no-empieces-en-enero', v2: 'video-2-premiamos-tu-constancia', v3: 'video-3-cuenta-regresiva', v4: 'video-4-regala-tumbao' };
const FPS = 30;
const quedan = process.argv.slice(2).length ? process.argv.slice(2) : Object.keys(NOMBRES);
mkdirSync(join(AQUI, 'salida/videos'), { recursive: true });
const nav = await chromium.launch({ executablePath: process.env.CHROMIUM || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--no-sandbox'] });
const p = await nav.newPage({ viewport: { width: 1080, height: 1920 } });
for (const id of quedan) {
  const tmp = join(AQUI, 'salida/_frames_' + id); rmSync(tmp, { recursive: true, force: true }); mkdirSync(tmp, { recursive: true });
  await p.goto('file://' + join(AQUI, 'videos.html') + '?v=' + id);
  await p.evaluate(() => document.fonts.ready); await p.waitForTimeout(400);
  const dur = await p.evaluate(() => window.__dur);
  const total = dur * FPS;
  for (let f = 0; f < total; f++) {
    await p.evaluate((t) => { for (const a of document.getAnimations()) { a.pause(); a.currentTime = t; } }, (f / FPS) * 1000);
    await p.screenshot({ path: join(tmp, String(f).padStart(4, '0') + '.jpg'), type: 'jpeg', quality: 90 });
  }
  const sal = join(AQUI, 'salida/videos', NOMBRES[id] + '.mp4');
  execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-framerate', String(FPS), '-i', join(tmp, '%04d.jpg'), '-f', 'lavfi', '-i', 'anullsrc=r=44100:cl=stereo',
    '-shortest', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '20', '-preset', 'medium', '-c:a', 'aac', '-b:a', '96k', '-movflags', '+faststart', sal]);
  rmSync(tmp, { recursive: true, force: true });
  console.log('✓', NOMBRES[id], dur + ' s');
}
await nav.close();
