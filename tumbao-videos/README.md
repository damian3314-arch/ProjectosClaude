# Videos de Tumbao (motion graphics)

Aquí viven los proyectos de video. Hay dos herramientas instaladas como skills en `.claude/skills/`:

- **HyperFrames** (`/hyperframes`, la de cabecera): el video se escribe como una página HTML con animaciones GSAP y se
  renderiza a MP4. Trae flujos listos: `/motion-graphics` (piezas cortas: logo, cifra que sube, título animado),
  `/music-to-video` (video al ritmo de una canción), `/embedded-captions` (subtítulos a un video hablado),
  `/talking-head-recut` (gráficos encima de un video hablado), `/faceless-explainer`, `/slideshow`, `/general-video`.
- **Remotion** (`/remotion-best-practices`): videos escritos en React. Úsalo solo si se pide Remotion explícitamente.
  Licencia: gratis para personas y empresas de hasta 3 empleados; más de 3 necesitan licencia de empresa.

## Antes de empezar (cada sesión nueva en la nube)

```bash
bash tumbao-videos/preparar.sh   # instala FFmpeg y el navegador de render si faltan
```

## Ojo: nada desde CDN

En la nube el navegador de render no confía en el proxy de salida, así que un `<script src="https://cdn…">` falla
(`ERR_CERT_AUTHORITY_INVALID`) y la animación no corre. Las librerías van como archivo local: GSAP está en
`prueba-tumbao/vendor/gsap.min.js` (cópialo al proyecto nuevo). Las fuentes de Google sí funcionan: HyperFrames las
descarga y las incrusta al compilar.

## Proyecto de prueba

`prueba-tumbao/`: 4 segundos, vertical 1080×1920 (Reels/Historias), «Tumbao · Baila pa' sanar».

```bash
cd tumbao-videos/prueba-tumbao
npm run check                                   # revisa errores, encuadre y contraste
npx hyperframes render --quality draft --output prueba.mp4
```
