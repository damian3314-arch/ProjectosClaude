#!/usr/bin/env bash
# Deja lista la máquina para hacer videos (HyperFrames o Remotion). Se puede correr las veces que sea: lo que ya está, lo salta.
# En la nube cada sesión arranca con una máquina limpia, por eso FFmpeg y el navegador hay que ponerlos de nuevo.
set -euo pipefail

if ! command -v ffmpeg >/dev/null || ! command -v ffprobe >/dev/null; then
  echo "→ Instalando FFmpeg…"
  SUDO=$([ "$(id -u)" = 0 ] && echo "" || echo "sudo")
  $SUDO apt-get update -qq
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y -qq ffmpeg
fi

echo "→ Navegador de render de HyperFrames…"
npx -y hyperframes@0.8.150 browser ensure

echo "✓ Listo. Prueba: cd tumbao-videos/prueba-tumbao && npm run check && npm run render"
