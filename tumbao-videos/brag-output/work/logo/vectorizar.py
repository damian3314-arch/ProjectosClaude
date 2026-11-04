"""Pasa el logo (PNG de 521 px) a SVG nítido: separa el naranja («TUMBAO») del rosado («Baila pa' sanar»), agranda cada
máscara 8x con suavizado, la vuelve blanco/negro y la traza con potrace. Así el logo se puede ver grande sin pixelarse."""
import subprocess, re
import numpy as np
from PIL import Image, ImageFilter

im = Image.open('/home/user/ProjectosClaude/docs/img/logo-tumbao.png').convert('RGBA')
a = np.array(im).astype(float)
alfa = a[:, :, 3] / 255
naranja = (a[:, :, 1] > a[:, :, 2] + 20)
capas = {'naranja': (alfa * naranja), 'rosado': (alfa * ~naranja)}
ESC = 8
W, H = im.size
partes = []
for nombre, m in capas.items():
    img = Image.fromarray((m * 255).astype('uint8')).resize((W * ESC, H * ESC), Image.LANCZOS).filter(ImageFilter.GaussianBlur(ESC * 0.35))
    bw = img.point(lambda v: 0 if v > 127 else 255).convert('1')   # potrace traza lo negro
    bw.save(f'{nombre}.pbm')
    subprocess.run(['potrace', f'{nombre}.pbm', '-s', '-o', f'{nombre}.svg', '--turdsize', '20', '--alphamax', '1.0', '--opttolerance', '0.2'], check=True)
    svg = open(f'{nombre}.svg').read()
    g = re.search(r'<g transform="[^"]*"[^>]*>.*?</g>', svg, re.S).group(0)
    color = '#f26837' if nombre == 'naranja' else '#ea4f96'
    g = re.sub(r'fill="[^"]*"', f'fill="{color}"', g, count=1)
    partes.append(g)
w, h = W * ESC, H * ESC
out = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}">\n' + '\n'.join(partes) + '\n</svg>\n'
open('/home/user/ProjectosClaude/tumbao-videos/brag-output/composition/assets/logo.svg', 'w').write(out)
print('ok', w, h, len(out))
