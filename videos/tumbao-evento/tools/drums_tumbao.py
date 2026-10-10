"""Capa de percusion + impactos para el video de Tumbao, alineada al pulso de la pista B (105 BPM).

Uso: python drums_tumbao.py <bed_clean.wav> <out_mix.wav>
Sintesis determinista (semilla fija). La masterizacion final se hace con ffmpeg.
"""
import sys

import numpy as np
import soundfile as sf
from scipy.signal import butter, sosfilt

SR = 48000
DUR = 20.0
N = int(SR * DUR)
rng = np.random.default_rng(105)

BEAT0 = 0.522            # primer tiempo fuerte detectado
BEAT = 60.0 / 105.0      # 0.5714 s


def beat(n):
    return BEAT0 + n * BEAT


def bp(x, lo, hi):
    return sosfilt(butter(2, [lo, hi], btype="band", fs=SR, output="sos"), x)


def hp(x, f):
    return sosfilt(butter(2, f, btype="high", fs=SR, output="sos"), x)


def lp(x, f):
    return sosfilt(butter(2, f, btype="low", fs=SR, output="sos"), x)


def kick(gain=1.0):
    d = 0.5
    t = np.arange(int(SR * d)) / SR
    f = 46 + (165 - 46) * np.exp(-t / 0.028)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.26)
    click = hp(rng.standard_normal(len(t)), 2500) * np.exp(-t / 0.0025) * 0.35
    return np.tanh(2.2 * (body + click)) * 0.9 * gain


def clap(gain=1.0):
    d = 0.3
    t = np.arange(int(SR * d)) / SR
    env = np.zeros_like(t)
    for off in (0.0, 0.011, 0.022):
        m = t >= off
        env[m] += np.exp(-(t[m] - off) / (0.012 if off < 0.02 else 0.11))
    noise = bp(rng.standard_normal(len(t)), 900, 5200) * env
    tone = np.sin(2 * np.pi * 190 * t) * np.exp(-t / 0.05) * 0.5
    return (noise * 0.55 + tone) * 0.7 * gain


def shaker(gain=1.0):
    d = 0.08
    t = np.arange(int(SR * d)) / SR
    return hp(rng.standard_normal(len(t)), 6500) * np.exp(-t / 0.022) * 0.22 * gain


def impact(gain=1.0, tail=1.6, crash=True):
    t = np.arange(int(SR * tail)) / SR
    f = 30 + (95 - 30) * np.exp(-t / 0.18)
    sub = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / (tail * 0.38))
    out = np.tanh(1.8 * sub)
    if crash:
        n = lp(rng.standard_normal(len(t)), 5000) * np.exp(-t / 0.45) * 0.28
        out = out + n
    hit = kick(1.0)
    out[: len(hit)] += hit * 0.8
    return out * 0.95 * gain


def riser(d, gain=1.0):
    t = np.arange(int(SR * d)) / SR
    x = rng.standard_normal(len(t))
    # barrido de filtro por bloques: el brillo sube hacia el golpe
    out = np.zeros_like(x)
    blocks = 24
    edges = np.linspace(0, len(x), blocks + 1).astype(int)
    for i in range(blocks):
        fc = 300 * (9000 / 300) ** (i / (blocks - 1))
        seg = bp(x[edges[i]: edges[i + 1]], max(80, fc * 0.5), min(18000, fc * 1.6))
        out[edges[i]: edges[i + 1]] = seg
    sweep = np.sin(2 * np.pi * np.cumsum(220 * (6 ** (t / d))) / SR) * 0.15
    return (out * 0.5 + sweep) * (t / d) ** 2.2 * gain


L = np.zeros(N)
R = np.zeros(N)


def place(sig, at, pan=0.0):
    i = int(round(at * SR))
    if i >= N:
        return
    j = min(N, i + len(sig))
    s = sig[: j - i]
    L[i:j] += s * np.sqrt((1 - pan) / 2) * np.sqrt(2)
    R[i:j] += s * np.sqrt((1 + pan) / 2) * np.sqrt(2)


def groove(n0, n1, kicks=True, claps=True, shakers=True, half=False, g=1.0):
    """Dembow entre los tiempos n0 (incluido) y n1 (excluido)."""
    for n in range(n0, n1):
        b = beat(n)
        if kicks and (not half or (n - n0) % 2 == 0):
            place(kick(0.95 * g), b)
        if claps:
            # dembow: golpe en la "a" del 1 y en el "y" del 2 (cada 2 tiempos)
            if (n - n0) % 2 == 0:
                place(clap(0.8 * g), b + 0.75 * BEAT, pan=-0.15)
            else:
                place(clap(0.8 * g), b + 0.5 * BEAT, pan=0.15)
        if shakers:
            for k, acc in ((0.0, 0.6), (0.5, 1.0)):
                place(shaker(acc * g), b + k * BEAT, pan=0.35 if k else -0.35)


# --- arreglo (tiempos n: beat(n) = 0.522 + n*0.5714) ---
place(riser(0.52, 0.7), 0.0)                 # intro corta hacia el primer golpe
place(impact(0.9), beat(0))                  # 0.52  arranca la vibra
groove(0, 7)                                 # 0.52 - 4.52 groove completo
place(impact(0.75, tail=1.2), beat(7))       # 4.52  corte: "Llegas con el dia encima"
groove(7, 11, claps=False, half=True, g=0.8) # tension: solo bombo a medio tiempo
place(riser(0.57, 0.9), beat(10))            # sube hacia el drop
place(impact(1.0), beat(11))                 # 6.81  "Y aqui lo SUELTAS"
groove(11, 15)                               # 6.81 - 9.09
# 9.09 - 13.67 respiro: sin bateria, solo la pista y dos latidos graves
place(impact(0.45, tail=2.0, crash=False), beat(15))
place(impact(0.55, tail=2.2, crash=False), beat(19))   # 11.38 "terapia."
place(riser(0.57, 0.9), beat(22))            # sube hacia el corte
place(impact(1.0), beat(23))                 # 13.67 seguro / tranquilo / climatizado
groove(23, 28)
for n in (24, 25, 26):                       # refuerzo en cada etiqueta
    place(clap(0.6), beat(n), pan=0.0)
place(riser(0.29, 0.8), beat(28) - 0.29)
place(impact(1.1, tail=2.4), beat(28))       # 16.52 cierre con logo
groove(28, 32, claps=True, g=0.85)           # 16.52 - 18.81
place(impact(0.9, tail=2.0), beat(32))       # 18.81 golpe final, cola hasta el final

drums = np.stack([L, R], axis=1)

bed, sr = sf.read(sys.argv[1], always_2d=True)
assert sr == SR, sr
bed = bed[:N]
if len(bed) < N:
    bed = np.pad(bed, ((0, N - len(bed)), (0, 0)))

# la pista baja durante los golpes grandes (sidechain simple) y sube en el respiro
env = np.ones(N)
for at, depth in ((beat(0), 0.5), (beat(7), 0.4), (beat(11), 0.5), (beat(23), 0.5), (beat(28), 0.55), (beat(32), 0.45)):
    i = int(at * SR)
    k = np.arange(int(0.6 * SR))
    j = min(N, i + len(k))
    env[i:j] = np.minimum(env[i:j], 1 - depth * np.exp(-k[: j - i] / (0.18 * SR)))
bed_gain = np.full(N, 0.55)
b0, b1 = int(beat(15) * SR), int(beat(23) * SR)
bed_gain[b0:b1] = 0.8                        # en el respiro la melodia toma el frente
mix = drums * 0.62 + bed * (bed_gain * env)[:, None]

# fade de salida en los ultimos 0.5 s
fade = np.ones(N)
f0 = int((DUR - 0.5) * SR)
fade[f0:] = np.linspace(1, 0, N - f0)
mix *= fade[:, None]
peak = np.max(np.abs(mix))
mix = mix / peak * 0.95
sf.write(sys.argv[2], mix.astype(np.float32), SR)
print("ok", sys.argv[2], f"peak_before_norm={peak:.2f}")
