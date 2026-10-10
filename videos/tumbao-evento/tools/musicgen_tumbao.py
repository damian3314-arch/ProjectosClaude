"""Genera pistas instrumentales para el video de Tumbao con MusicGen local (facebook/musicgen-small)."""
import sys
import time

import numpy as np
import soundfile as sf
import torch
from transformers import AutoProcessor, MusicgenForConditionalGeneration

OUT_DIR = sys.argv[1]
DURATION_S = 22.0

VARIANTS = {
    "bgm-a": (
        "warm emotional latin dance music, soft piano intro, congas and bongos join, "
        "building into a joyful uplifting salsa groove, hopeful and heartfelt, "
        "100 bpm, instrumental, no vocals, high quality studio recording",
        7,
    ),
    "bgm-b": (
        "uplifting afro-latin percussion with warm nylon guitar and soft brass, "
        "gentle start building to a celebratory feel-good dance groove, "
        "105 bpm, instrumental, no vocals, high quality studio recording",
        11,
    ),
}

torch.set_num_threads(4)
processor = AutoProcessor.from_pretrained("facebook/musicgen-small")
model = MusicgenForConditionalGeneration.from_pretrained("facebook/musicgen-small")
model.eval()
sr = int(model.config.audio_encoder.sampling_rate)
tokens = int(DURATION_S * model.config.audio_encoder.frame_rate)

for name, (prompt, seed) in VARIANTS.items():
    t0 = time.time()
    torch.manual_seed(seed)
    inputs = processor(text=[prompt], padding=True, return_tensors="pt")
    with torch.no_grad():
        audio = model.generate(**inputs, do_sample=True, guidance_scale=3.0, max_new_tokens=tokens)
    wav = audio[0, 0].cpu().numpy().astype(np.float32)
    peak = float(np.max(np.abs(wav))) or 1.0
    wav = wav / peak * 0.89
    path = f"{OUT_DIR}/{name}.wav"
    sf.write(path, wav, sr)
    print(f"[musicgen] {name}: {len(wav) / sr:.2f}s sr={sr} in {time.time() - t0:.0f}s -> {path}", flush=True)
