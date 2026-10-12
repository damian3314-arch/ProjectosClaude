"""Música y efectos del brag de Tumbao, sintetizados aquí mismo (sin pistas de terceros).

v2 (12 oct): Damián: «a la música le falta demasiada fuerza, está demasiado lenta; tiene que ser más emocionante y tener
efectos de sonido en las transiciones». Pasa de dembow a 96 BPM a guaracha / latin house a 128 BPM: bombo a negras, palmas
en 2 y 4, platillo abierto a contratiempo, tambores, bajo a contratiempo, acordes cortados, una melodía en los «drops» y
un bombeo (sidechain) que hace respirar todo con el bombo. Dos subidas con redoble y dos caídas fuertes: «CONSTANCIA»
(3,75 s) y el cierre (16,875 s).

128 BPM: un tiempo = 0,46875 s, un compás = 1,875 s; 12 compases = 22,5 s. La menor (Am–F–C–G).
Los efectos caen en los mismos instantes que los cortes del video (ver brag-plan.md).
Salida: ../composition/assets/musica.wav (estéreo, 48 kHz).
"""
import sys
import wave
import numpy as np
from scipy.signal import butter, sosfilt

SR = 48000
BPM = 128
BEAT = 60 / BPM
S16 = BEAT / 4
BAR = BEAT * 4
BARS = 12
DUR = BAR * BARS            # 22,5 s
N = int(SR * DUR)
rng = np.random.default_rng(11)

# Dos buses: la música (bombea con el bombo) y lo que no bombea (bombo, efectos).
M = np.zeros((N, 2))
D = np.zeros((N, 2))


def add(bus, sig, t, gain=1.0, pan=0.0):
    i = int(round(t * SR))
    if i >= N or i + len(sig) <= 0:
        return
    if i < 0:
        sig, i = sig[-i:], 0
    sig = sig[: N - i]
    gl = gain * np.cos((pan + 1) * np.pi / 4)
    gr = gain * np.sin((pan + 1) * np.pi / 4)
    bus[i:i + len(sig), 0] += sig * gl
    bus[i:i + len(sig), 1] += sig * gr


def env(n, a, d):
    t = np.arange(n) / SR
    e = np.exp(-t / d)
    na = max(1, int(a * SR))
    e[:na] *= np.linspace(0, 1, na)
    return e


def filt(x, kind, f, order=2):
    return sosfilt(butter(order, f, btype=kind, fs=SR, output='sos'), x)


def nota(nombre):
    idx = {'C': -9, 'D': -7, 'E': -5, 'F': -4, 'G': -2, 'A': 0, 'B': 2}
    n, o = nombre[:-1], int(nombre[-1])
    return 440.0 * 2 ** ((idx[n[0]] + (1 if '#' in n else 0) + (o - 4) * 12) / 12)


def sierra(f, n, voces=5, det=0.012):
    t = np.arange(n) / SR
    out = np.zeros(n)
    for k in range(voces):
        fk = f * (1 + det * (k - (voces - 1) / 2))
        out += 2 * ((fk * t + rng.random()) % 1) - 1
    return out / voces


# ── batería ──────────────────────────────────────────────────────────────
def bombo():
    n = int(0.32 * SR)
    t = np.arange(n) / SR
    f = 48 + 135 * np.exp(-t / 0.022)
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.001, 0.15)
    click = filt(rng.standard_normal(n), 'highpass', 3000) * env(n, 0.0003, 0.003) * 0.5
    return np.tanh(2.2 * (s + click))


def palmas():
    n = int(0.3 * SR)
    x = filt(rng.standard_normal(n), 'bandpass', [900, 3200])
    e = np.zeros(n)
    for k, d in enumerate((0, 0.009, 0.019)):
        i = int(d * SR)
        e[i:] += env(n - i, 0.0005, 0.006 if k < 2 else 0.11)
    return x * e * 0.9


def platillo(abierto=True):
    n = int((0.25 if abierto else 0.05) * SR)
    return filt(rng.standard_normal(n), 'highpass', 8000) * env(n, 0.001, 0.08 if abierto else 0.015)


def maraca():
    n = int(0.06 * SR)
    return filt(rng.standard_normal(n), 'bandpass', [5000, 12000]) * env(n, 0.004, 0.02)


def tambor(f):
    n = int(0.25 * SR)
    t = np.arange(n) / SR
    ff = f * (1 + 0.6 * np.exp(-t / 0.02))
    return np.sin(2 * np.pi * np.cumsum(ff) / SR) * env(n, 0.001, 0.11)


def redoble_golpe():
    n = int(0.12 * SR)
    t = np.arange(n) / SR
    return (0.8 * filt(rng.standard_normal(n), 'bandpass', [1500, 7000]) + 0.5 * np.sin(2 * np.pi * 220 * t)) * env(n, 0.001, 0.04)


def crash():
    n = int(1.6 * SR)
    return filt(rng.standard_normal(n), 'highpass', 4500) * env(n, 0.001, 0.45)


# ── instrumentos con nota ────────────────────────────────────────────────
def bajo(f, largo):
    n = int(largo * SR)
    s = filt(sierra(f, n, 2, 0.004), 'lowpass', 520) * 0.8 + np.sin(2 * np.pi * f * np.arange(n) / SR)
    e = env(n, 0.003, largo * 0.55)
    e[-int(0.01 * SR):] *= np.linspace(1, 0, int(0.01 * SR))
    return np.tanh(2.0 * s * e) * 0.8


def acorde_corto(fs, largo=0.16, corte=5200):
    n = int(largo * SR)
    s = sum(sierra(f, n) for f in fs) / len(fs)
    return filt(filt(s, 'lowpass', corte), 'highpass', 250) * env(n, 0.002, 0.07)


def melodia(f, largo):
    n = int(largo * SR)
    t = np.arange(n) / SR
    pulso = np.sign(np.sin(2 * np.pi * f * t + 0.6 * np.sin(2 * np.pi * 5.5 * t) * (t > 0.08)))
    s = filt(0.6 * pulso + 0.4 * sierra(f, n, 3, 0.006), 'lowpass', 4200)
    return s * env(n, 0.004, largo * 0.6)


def colchon(fs, largo, corte):
    n = int(largo * SR)
    s = filt(sum(sierra(f, n, 5, 0.01) for f in fs) / len(fs), 'lowpass', corte)
    e = np.ones(n)
    a = int(0.05 * SR)
    e[:a] = np.linspace(0, 1, a)
    e[-a:] *= np.linspace(1, 0, a)
    return s * e


ACORDES = [('A1', ['A3', 'C4', 'E4']), ('F1', ['F3', 'A3', 'C4']), ('C2', ['G3', 'C4', 'E4']), ('G1', ['G3', 'B3', 'D4'])]
DROP = {2, 3, 9, 10, 11}          # compases con todo (y melodía)
SUBIDA = {1: (0.0, 1.0), 8: (0.5, 1.0)}   # compás → desde qué fracción hay redoble

K, CL = bombo(), palmas()
tiempos_bombo = []
for c in range(BARS):
    t0 = c * BAR
    raiz, notas = ACORDES[c % 4]
    fs = [nota(x) for x in notas]
    fb = nota(raiz) * 2               # el bajo una octava arriba del sub (A2, F2…)
    ultimo = c == BARS - 1
    if c == 0:
        # Intro: acordes cortados con el filtro abriéndose, bombo suave y maracas; el letrero se prende.
        for k in range(16):
            if k in (0, 3, 6, 10, 12):
                add(M, acorde_corto(fs, corte=700 + 160 * k), t0 + k * S16, 0.26, -0.2 if k % 2 else 0.2)
            add(M, maraca(), t0 + k * S16, 0.05 + 0.03 * (k % 2), 0.3)
        for b in range(4):
            add(D, K, t0 + b * BEAT, 0.55); tiempos_bombo.append(t0 + b * BEAT)
        add(M, colchon(fs, BAR, 900), t0, 0.12)
        continue
    if c in SUBIDA:
        # Subida: redoble que se acelera y sube; el bombo se va en el último tiempo (el hueco antes del golpe).
        desde, _ = SUBIDA[c]
        ini = t0 + desde * BAR
        largo = (1 - desde) * BAR
        t = ini
        while t < t0 + BAR - S16 * 0.5:
            p = (t - ini) / largo
            paso = S16 * 2 if p < 0.4 else (S16 if p < 0.75 else S16 / 2)
            add(M, redoble_golpe(), t, 0.10 + 0.32 * p, 0.1 * np.sin(t * 9))
            t += paso
        for b in range(4):
            if b == 3:
                continue
            add(D, K, t0 + b * BEAT, 0.9 if c > 1 else 0.7); tiempos_bombo.append(t0 + b * BEAT)
        for k in range(16):
            if k in (0, 3, 6, 10, 12) and (c > 1 or k < 12):
                add(M, acorde_corto(fs, corte=2500 if c == 1 else 4800), t0 + k * S16, 0.2, -0.2 if k % 2 else 0.2)
            if k % 4 == 2:
                add(M, platillo(), t0 + k * S16, 0.1, -0.3)
        add(M, colchon(fs, BAR, 1600 if c == 1 else 2600), t0, 0.08)
        if c == 8:
            for k in (2, 6):
                add(M, bajo(fb, S16 * 1.6), t0 + k * S16, 0.5)
        continue
    # Compases con ritmo completo.
    fuerte = c in DROP
    for b in range(4):
        tb = t0 + b * BEAT
        if ultimo and b == 3:
            continue
        add(D, K, tb, 1.0); tiempos_bombo.append(tb)
        if b in (1, 3):
            add(M, CL, tb, 0.5, 0.05)
    for k in range(16):
        tk = t0 + k * S16
        if ultimo and k >= 12:
            continue
        add(M, maraca(), tk, 0.05 if k % 2 == 0 else 0.08, 0.35)
        if k % 4 == 2:
            add(M, platillo(), tk, 0.14, -0.3)
        if k in (2, 5, 7, 11, 13, 15):
            add(M, tambor(150 if k in (2, 11) else (190 if k in (5, 13) else 240)), tk, 0.22, -0.4 if k % 2 else 0.4)
        if k in (2, 6, 10, 14) or (k == 15 and not ultimo):
            add(M, bajo(fb, S16 * 1.7), tk, 0.55)
        if k in (0, 3, 6, 10, 12):
            add(M, acorde_corto(fs, corte=5200 if fuerte else 3600), tk, 0.22 if fuerte else 0.15, -0.25 if k % 2 else 0.25)
    add(M, colchon(fs, BAR, 3000 if fuerte else 2000), t0, 0.07)
    if fuerte:
        ct = [nota(x[:-1] + str(int(x[-1]) + 1)) for x in notas]   # notas del acorde, una octava arriba
        frase = [(0, ct[0]), (3, ct[2]), (6, ct[1]), (8, ct[2]), (10, ct[0] * 2), (12, ct[2]), (14, ct[1])]
        for k, f in frase:
            if ultimo and k >= 12:
                continue
            add(M, melodia(f, S16 * 1.8), t0 + k * S16, 0.11, 0.15)

# Final: el último golpe (compás 12, tiempo 4) con todo y la cola.
t_fin = DUR - BEAT
fin = [nota(x) for x in ('A3', 'C4', 'E4', 'A4')]
add(M, acorde_corto(fin, largo=0.6, corte=6000), t_fin, 0.32)
add(D, K, t_fin, 1.0)

# ── bombeo: todo lo de la música se agacha con cada bombo ─────────────────
bomba = np.ones(N)
lar = int(0.2 * SR)
curva = 1 - 0.6 * np.exp(-np.arange(lar) / (0.06 * SR))
for tb in tiempos_bombo:
    i = int(tb * SR)
    j = min(N, i + lar)
    bomba[i:j] = np.minimum(bomba[i:j], curva[: j - i])
M *= bomba[:, None]

# ── efectos de sonido (en la menor) ──────────────────────────────────────
def barrido(largo=0.55, f0=400, f1=7000, sube=True):
    n = int(largo * SR)
    x = rng.standard_normal(n)
    out = np.zeros(n)
    tr = 16
    for i in range(tr):
        a, b = i * n // tr, (i + 1) * n // tr
        p = i / (tr - 1)
        f = f0 * (f1 / f0) ** (p if sube else 1 - p)
        out[a:b] = filt(x, 'bandpass', [f, min(f * 1.9, 20000)])[a:b]
    return out * np.sin(np.linspace(0, np.pi, n)) ** 1.5


def barrido_estereo(t, largo=0.55, gain=0.35, f0=400, f1=7000):
    """El barrido cruza de izquierda a derecha."""
    s = barrido(largo, f0, f1)
    n = len(s)
    pan = np.linspace(-0.9, 0.9, n)
    i = int(round((t - largo * 0.6) * SR))
    j = min(N, i + n)
    gl = np.cos((pan + 1) * np.pi / 4)[: j - i]
    gr = np.sin((pan + 1) * np.pi / 4)[: j - i]
    D[i:j, 0] += s[: j - i] * gl * gain
    D[i:j, 1] += s[: j - i] * gr * gain


def golpe():
    n = int(1.4 * SR)
    t = np.arange(n) / SR
    f = 34 + 90 * np.exp(-t / 0.06)
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.001, 0.45)
    s += filt(rng.standard_normal(n), 'lowpass', 2500) * env(n, 0.0005, 0.09) * 0.6
    return np.tanh(1.6 * s)


def subida_ruido(largo):
    n = int(largo * SR)
    t = np.arange(n) / SR
    x = rng.standard_normal(n)
    out = np.zeros(n)
    tr = 24
    for i in range(tr):
        a, b = i * n // tr, (i + 1) * n // tr
        f = 300 * (9000 / 300) ** (i / (tr - 1))
        out[a:b] = filt(x, 'highpass', f)[a:b]
    tono = np.sin(2 * np.pi * np.cumsum(220 * (4 ** (t / largo))) / SR) * 0.35
    return (out + tono) * (t / largo) ** 2


def zumbido(largo, parpadeos):
    n = int(largo * SR)
    t = np.arange(n) / SR
    s = sum(np.sin(2 * np.pi * 110 * h * t) / h for h in (1, 2, 3, 4, 5)) + 0.2 * filt(rng.standard_normal(n), 'bandpass', [2000, 6000])
    on = np.zeros(n)
    for a, b in parpadeos:
        on[int(a * SR):int(b * SR)] = 1
    on = filt(on, 'lowpass', 200)
    cola = np.ones(n)
    k = int(0.7 * SR)
    cola[k:] = np.exp(-(t[k:] - 0.7) / 0.3)
    return s * on * cola * 0.5


def toque():
    n = int(0.1 * SR)
    t = np.arange(n) / SR
    click = filt(rng.standard_normal(n), 'bandpass', [2500, 9000]) * env(n, 0.0003, 0.004)
    tono = (np.sin(2 * np.pi * nota('E6') * t) + 0.3 * np.sin(2 * np.pi * nota('E6') * 2 * t)) * env(n, 0.001, 0.025)
    return click * 0.8 + tono


def pop(f):
    n = int(0.18 * SR)
    t = np.arange(n) / SR
    ff = f * (1 + 0.5 * np.exp(-t / 0.015))
    return np.sin(2 * np.pi * np.cumsum(ff) / SR) * env(n, 0.001, 0.05)


def bip(f, largo=0.08):
    n = int(largo * SR)
    t = np.arange(n) / SR
    return np.sign(np.sin(2 * np.pi * f * t)) * 0.4 * env(n, 0.002, 0.03)


def campana(f):
    n = int(1.0 * SR)
    t = np.arange(n) / SR
    return (np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * 2.76 * f * t) * np.exp(-t / 0.08)) * env(n, 0.002, 0.3)


def destello(largo=1.0):
    n = int(largo * SR)
    out = np.zeros(n)
    for k in range(16):
        i = int(k * n / 20)
        f = nota(['A6', 'C7', 'E7', 'G6'][k % 4])
        m = n - i
        tt = np.arange(m) / SR
        out[i:] += np.sin(2 * np.pi * f * tt) * env(m, 0.001, 0.06) * (1 - k / 18)
    return out


def chispazo():
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    s = filt(rng.standard_normal(n), 'bandpass', [1500, 9000]) * (np.sin(2 * np.pi * 60 * t) > 0.2)
    tono = np.sin(2 * np.pi * np.cumsum(1400 * np.exp(-t / 0.08) + 120) / SR)
    return (0.7 * s + 0.5 * tono) * env(n, 0.001, 0.09)


# El letrero y las tiras se prenden: 0,10–0,16 · 0,22–0,28 · 0,38–0,44 · desde 0,52.
add(D, zumbido(1.4, [(0.10, 0.16), (0.22, 0.28), (0.38, 0.44), (0.52, 1.4)]), 0, 0.16)
# «CON GANAS» se tacha: chispazo.
add(D, chispazo(), 3.05, 0.28)
# Subidas antes de las dos caídas.
add(D, subida_ruido(BAR), BAR, 0.16)
add(D, subida_ruido(BAR * 0.5), 8 * BAR + BAR * 0.5, 0.16)
# Golpes y platillo en las caídas.
for t in (2 * BAR, 9 * BAR):
    add(D, golpe(), t, 0.75)
    add(M, crash(), t, 0.22, 0.2)
add(D, golpe(), t_fin, 0.55)
add(M, crash(), t_fin, 0.2, -0.2)
# Barridos en cada corte de escena y en cada cambio de pantalla.
for t, g in ((3 * BAR, 0.34), (4 * BAR, 0.36), (16.6, 0.3)):
    barrido_estereo(t, 0.6, g)
for t in (9.2, 11.25, 14.0625):
    barrido_estereo(t, 0.32, 0.26, 900, 9000)
# Toques del dedo.
for t in (8.90625, 10.78125, 20.625):
    add(D, toque(), t, 0.42, 0.1)
# El número del paso cambia: un «pop».
for t, f in ((7.65, nota('A4')), (11.4, nota('C5')), (14.2, nota('E5'))):
    add(D, pop(f), t, 0.42)
# Escaneo del QR: bip-bip.
for i, t in enumerate((12.55, 12.7, 13.45)):
    add(D, bip(nota('A6') if i < 2 else nota('E7')), t, 0.10, -0.2)
# ¡Listo!: campanitas.
for i, nn in enumerate(('A5', 'C6', 'E6', 'A6')):
    add(D, campana(nota(nn)), 14.3 + i * 0.07, 0.16, -0.3 + 0.2 * i)
# El logo se prende: zumbido corto y destello.
add(D, zumbido(0.9, [(0.0, 0.05), (0.1, 0.15), (0.2, 0.9)]), 19.15, 0.12)
add(D, destello(1.0), 19.2, 0.10, 0.2)

# ── mezcla ────────────────────────────────────────────────────────────────
st = M + D
st = np.tanh(st * 1.3) / np.tanh(1.3)
st[: int(0.005 * SR)] *= np.linspace(0, 1, int(0.005 * SR))[:, None]
fade = int(0.4 * SR)
st[-fade:] *= np.linspace(1, 0, fade)[:, None]
st *= 10 ** (-2.2 / 20) / np.max(np.abs(st))   # pico de muestra en -2,2 dBFS: el pico real queda por debajo de -1

out = sys.argv[1] if len(sys.argv) > 1 else '../composition/assets/musica.wav'
with wave.open(out, 'wb') as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes((st * 32767).astype('<i2').tobytes())
print('listo', out, f'{DUR:.3f}s')
