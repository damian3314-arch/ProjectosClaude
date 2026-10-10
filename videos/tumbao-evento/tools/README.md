# Audio del video

1. `musicgen_tumbao.py <carpeta>`: genera las pistas con MusicGen local (`facebook/musicgen-small`). La elegida fue `bgm-b`.
2. Limpieza de `bgm-b.wav` con ffmpeg (quita siseo y frecuencias ásperas):
   `ffmpeg -i bgm-b.wav -af "highpass=f=45,lowpass=f=8500,afftdn=nr=12:nf=-42:tn=1,equalizer=f=3200:t=q:w=1.2:g=-3,aresample=48000" -ac 2 -ar 48000 bgm-b-clean.wav`
3. `drums_tumbao.py bgm-b-clean.wav mix_raw.wav`: percusión dembow, bajos e impactos al pulso (105 BPM, primer tiempo en 0.522 s).
4. Master: `ffmpeg -i mix_raw.wav -af "acompressor=threshold=-16dB:ratio=3:attack=8:release=120:makeup=2,loudnorm=I=-14:TP=-1.5:LRA=9,alimiter=limit=0.84:level=false" -ar 48000 -c:a pcm_s16le tumbao-mix.wav`

Requiere `torch`, `transformers<5`, `soundfile`, `numpy`, `scipy`.
