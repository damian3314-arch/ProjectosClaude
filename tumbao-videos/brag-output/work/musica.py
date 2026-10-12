"""Música y efectos del brag de Tumbao, sintetizados aquí mismo (sin pistas de terceros).

Dembow a 96 BPM en la menor (Am–F–C–G). Un compás = 2,5 s; 8 compases = 20 s.
Los efectos van en la misma tonalidad y caen en los mismos instantes que los cortes del video (ver brag-plan.md).
Salida: ../composition/assets/musica.wav (estéreo, 48 kHz).
"""
import sys
import numpy as np
from scipy.signal import butter, sosfilt

SR = 48000
BPM = 96
BEAT = 60 / BPM            # 0,625 s
S16 = BEAT / 4             # semicorchea
BAR = BEAT * 4             # 2,5 s
DUR = 20.0
N = int(SR * DUR)
rng = np.random.default_rng(7)

L = np.zeros(N)
R = np.zeros(N)


def add(sig, t, gain=1.0, pan=0.0):
    i = int(round(t * SR))
    if i >= N:
        return
    sig = sig[: N - i]
    gl = gain * np.cos((pan + 1) * np.pi / 4)
    gr = gain * np.sin((pan + 1) * np.pi / 4)
    L[i:i + len(sig)] += sig * gl
    R[i:i + len(sig)] += sig * gr


def env(n, a, d):
    """Ataque lineal de a s y caída exponencial con constante d s."""
    t = np.arange(n) / SR
    e = np.exp(-t / d)
    na = max(1, int(a * SR))
    e[:na] *= np.linspace(0, 1, na)
    return e


def filt(x, kind, f, order=2):
    sos = butter(order, f, btype=kind, fs=SR, output='sos')
    return sosfilt(sos, x)


def nota(nombre):
    idx = {'C': -9, 'D': -7, 'E': -5, 'F': -4, 'G': -2, 'A': 0, 'B': 2}
    n, oct_ = nombre[:-1], int(nombre[-1])
    semis = idx[n[0]] + (1 if '#' in n else 0) + (oct_ - 4) * 12
    return 440.0 * 2 ** (semis / 12)


# ── instrumentos ────────────────────────────────────────────────────────────
def kick():
    n = int(0.42 * SR)
    t = np.arange(n) / SR
    f = 45 + 85 * np.exp(-t / 0.03)
    ph = 2 * np.pi * np.cumsum(f) / SR
    s = np.sin(ph) * env(n, 0.002, 0.16)
    click = filt(rng.standard_normal(n), 'highpass', 2500) * env(n, 0.0005, 0.004) * 0.25
    return np.tanh(1.6 * (s + click))


def caja():
    n = int(0.25 * SR)
    t = np.arange(n) / SR
    ruido = filt(rng.standard_normal(n), 'bandpass', [1600, 7000]) * env(n, 0.001, 0.07)
    tono = np.sin(2 * np.pi * 210 * t) * env(n, 0.001, 0.05) * 0.6
    return 0.8 * ruido + tono


def hat(abierto=False):
    n = int((0.22 if abierto else 0.06) * SR)
    return filt(rng.standard_normal(n), 'highpass', 7500) * env(n, 0.0005, 0.07 if abierto else 0.018)


def bajo(f, largo):
    n = int(largo * SR)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * f * t) + 0.25 * np.sin(2 * np.pi * 2 * f * t)
    e = env(n, 0.004, largo * 0.9)
    e[-int(0.02 * SR):] *= np.linspace(1, 0, int(0.02 * SR))
    return np.tanh(1.8 * s * e) * 0.9


def sierra(f, n, voces=3, det=0.006):
    t = np.arange(n) / SR
    out = np.zeros(n)
    for k in range(voces):
        fk = f * (1 + det * (k - (voces - 1) / 2))
        fase = rng.random()
        out += 2 * ((fk * t + fase) % 1) - 1
    return out / voces


def pluck(fs, largo=0.22):
    n = int(largo * SR)
    s = sum(sierra(f, n, 2, 0.004) for f in fs) / len(fs)
    return filt(s, 'lowpass', 2600) * env(n, 0.002, 0.07)


def pad(fs, largo, corte):
    n = int(largo * SR)
    s = sum(sierra(f, n, 3, 0.008) for f in fs) / len(fs)
    s = filt(s, 'lowpass', corte)
    e = np.ones(n)
    a = int(0.35 * SR)
    e[:a] = np.linspace(0, 1, a)
    e[-a:] *= np.linspace(1, 0, a)
    return s * e


ACORDES = [  # raíz del bajo, notas del acorde
    ('A1', ['A3', 'C4', 'E4']),
    ('F1', ['F3', 'A3', 'C4']),
    ('C2', ['G3', 'C4', 'E4']),
    ('G1', ['G3', 'B3', 'D4']),
]

K, SN = kick(), caja()
for c in range(8):
    t0 = c * BAR
    raiz, notas = ACORDES[c % 4]
    fs = [nota(x) for x in notas]
    # Pad todo el tiempo; en el compás 1 (el gancho) va más cerrado y más presente.
    add(pad(fs, BAR + 0.3, 1100 if c == 0 else 1500), t0, 0.30 if c == 0 else 0.09, 0)
    if c == 0:
        # el gancho: solo pad, un sub que sube y los hats que crecen hacia el golpe del compás 2
        for k in range(8, 16):
            add(hat(), t0 + k * S16, 0.07 + 0.025 * (k - 8), 0.3)
        continue
    final = c == 7
    for b in range(4):
        tb = t0 + b * BEAT
        if final and b == 3:
            continue
        add(K, tb, 0.95)
    for k in (3, 6, 11, 14):
        if final and k == 14:
            continue
        add(SN, t0 + k * S16, 0.42, 0.05)
    for k in range(0, 16, 2):
        if final and k >= 12:
            continue
        add(hat(abierto=(k % 4 == 2)), t0 + k * S16, 0.13 if k % 4 else 0.08, -0.25)
    fb = nota(raiz)
    for k, largo in ((0, BEAT * 0.95), (6, S16 * 2.6), (11, S16 * 2.6)):
        if final and k == 11:
            continue
        add(bajo(fb, largo), t0 + k * S16, 0.55)
    for k in (2, 6, 10, 14):
        if final and k == 14:
            continue
        add(pluck(fs), t0 + k * S16, 0.17, 0.35 if k % 8 == 2 else -0.35)

# Acorde final que respira hasta el cierre (Am).
fin = [nota(x) for x in ('A3', 'C4', 'E4', 'A4')]
add(pad(fin, 1.6, 2200), 18.4, 0.16)
add(bajo(nota('A1'), 1.2), 18.75, 0.5)

# ── efectos (en la menor, por debajo de la música) ─────────────────────────
def zumbido(largo, parpadeos):
    n = int(largo * SR)
    t = np.arange(n) / SR
    s = sum(np.sin(2 * np.pi * 110 * h * t) / h for h in (1, 2, 3, 4, 5))
    s += 0.15 * filt(rng.standard_normal(n), 'bandpass', [2000, 6000])
    on = np.zeros(n)
    for a, b in parpadeos:
        on[int(a * SR):int(b * SR)] = 1
    on = filt(on, 'lowpass', 200)
    cola = np.ones(n)
    k = int(0.9 * SR)
    cola[k:] = np.exp(-(t[k:] - 0.9) / 0.35)
    return s * on * cola * 0.5


# El letrero titila igual que en el video: 0,10–0,16 · 0,22–0,28 · 0,38–0,44 · desde 0,52 fijo.
add(zumbido(1.8, [(0.10, 0.16), (0.22, 0.28), (0.38, 0.44), (0.52, 1.8)]), 0, 0.17, 0)


def barrido(largo=0.45, sube=True):
    n = int(largo * SR)
    x = rng.standard_normal(n)
    out = np.zeros(n)
    trozos = 12
    for i in range(trozos):
        a, b = i * n // trozos, (i + 1) * n // trozos
        f = 500 + (5000 if sube else 2000) * ((i / trozos) if sube else (1 - i / trozos))
        out[a:b] = filt(x, 'bandpass', [f, f * 1.8])[a:b]
    e = np.sin(np.linspace(0, np.pi, n)) ** 2
    return out * e


for t in (2.5, 5.0, 10.0, 13.75):
    add(barrido(), t - 0.3, 0.16, 0.4)


def toque(f):
    n = int(0.12 * SR)
    t = np.arange(n) / SR
    return (np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * 2 * f * t)) * env(n, 0.001, 0.03)


for t in (6.25, 8.75):
    add(toque(nota('E5')), t, 0.16, 0.1)
add(toque(nota('A5')), 18.1, 0.14, 0.1)

# Escaneo del QR: un barrido suave de la a mi.
n = int(0.7 * SR)
tt = np.arange(n) / SR
f = nota('A5') * (nota('E6') / nota('A5')) ** (tt / 0.7)
add(np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.linspace(0, np.pi, n)) * 0.6, 11.0, 0.05, -0.2)


def campana(f):
    n = int(0.9 * SR)
    t = np.arange(n) / SR
    return (np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * 2.76 * f * t) * np.exp(-t / 0.08)) * env(n, 0.002, 0.28)


for i, nn in enumerate(('A5', 'C6', 'E6')):
    add(campana(nota(nn)), 13.85 + i * 0.09, 0.12, -0.3 + 0.3 * i)

# Subida hacia el cierre y golpe en el logo.
n = int(0.85 * SR)
tt = np.arange(n) / SR
sube = filt(rng.standard_normal(n), 'highpass', 1200) * (tt / 0.85) ** 2
add(sube, 16.25 - 0.85, 0.10, 0)


def golpe():
    n = int(1.2 * SR)
    t = np.arange(n) / SR
    f = 38 + 70 * np.exp(-t / 0.05)
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.002, 0.35)
    s += filt(rng.standard_normal(n), 'lowpass', 3000) * env(n, 0.001, 0.12) * 0.4
    return np.tanh(1.4 * s)


add(golpe(), 2.5, 0.38)
add(golpe(), 16.25, 0.45)

# ── mezcla final ────────────────────────────────────────────────────────────
st = np.stack([L, R], axis=1)
st = np.tanh(st * 1.15) / np.tanh(1.15)          # un pegamento suave, sin picos ásperos
fade = int(0.45 * SR)
st[-fade:] *= np.linspace(1, 0, fade)[:, None]
st[: int(0.01 * SR)] *= np.linspace(0, 1, int(0.01 * SR))[:, None]
st *= 10 ** (-2.5 / 20) / np.max(np.abs(st))     # pico en -2,5 dBFS (≈ -13 LUFS, cómodo para Reels)

pcm = (st * 32767).astype('<i2')
out = sys.argv[1] if len(sys.argv) > 1 else '../composition/assets/musica.wav'
import wave
with wave.open(out, 'wb') as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(pcm.tobytes())
print('listo', out, f'{N / SR:.2f}s')
