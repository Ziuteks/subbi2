"""Dźwięk animacji startowej zgrany z make_splash.swift (logo ląduje ok. 0,70 s).

Warstwy:
  1. świst przelotu (0,15–0,70 s) – narastający szum, przesuwa się z prawej do środka jak logo,
  2. dwa uderzenia basem („bum-bum”, 0,70 s i 1,00 s) strojone do A (55 Hz) – główny akcent,
  3. dzwoneczki przy lądowaniu – arpeggio A-dur (A5, Cis6, E6),
  4. pogłos stereo na świście i dzwoneczkach (bas zostaje suchy, żeby nie stracił uderzenia).

Użycie:
    python3 tools/splash/make_audio.py /tmp/splash-audio.wav
    afconvert -f m4af -d aac -b 192000 /tmp/splash-audio.wav subbi/Splash/audio.m4a

Głośniki iPhone'a słabo grają poniżej ~100 Hz, dlatego bas jest przesterowany (harmoniczne)
i ma krótki „klik” – słychać go także bez słuchawek.
"""
import math
import random
import struct
import sys
import wave

RATE = 44100
DURATION = 2.2          # jak wideo
LAND = 0.70             # lądowanie logo w animacji

# --- Bas ---
HITS = [                # (czas [s], głośność)
    (LAND, 1.00),       # lądowanie logo
    (1.00, 1.00),       # drugie uderzenie
]
BASS_NOTE = 55.0        # A1 – na tej wysokości kończy się opadanie uderzenia
DRIVE = 3.5             # przesterowanie basu: większe = gęstszy, mocniejszy bas
BODY_DECAY = 0.38       # wybrzmienie basu [s]
HIT_LENGTH = 1.0        # długość uderzenia [s]; ostatnie HIT_TAPER s łagodnie wygaszane do zera
HIT_TAPER = 0.35        # (bez tego ucięte wybrzmienie słychać jako ciche stuknięcie)

# --- Pozostałe warstwy (głośność względem basu) ---
WHOOSH_LEVEL = 1.30
CHIME_LEVEL = 0.20
CHIMES = [(LAND + 0.02, 880.00), (LAND + 0.10, 1108.73), (LAND + 0.18, 1318.51)]  # A5, Cis6, E6
REVERB_WET = 0.30

LIMIT_KNEE = 0.80       # limiter na sumie: powyżej tego poziomu szczyty są łagodnie zaokrąglane
PEAK_DBFS = -3.0        # zapas: kodowanie AAC lekko podbija szczyty (bez tego przester)
VOLUME_DB = -4.0        # ogólna głośność względem maksimum (0 = najgłośniej bez przesteru)
TAIL_FADE = 0.30        # wyciszenie końcówki [s]

random.seed(7)  # powtarzalny wynik
N = int(RATE * DURATION)


# ---------- Warstwy ----------

def bass_hit(t: float) -> float:
    """Jedno uderzenie basu w chwili t od jego początku."""
    if t < 0 or t >= HIT_LENGTH:
        return 0.0
    # Wysokość opada szybko z 2x do BASS_NOTE (charakter „stopy” perkusji, ale strojony).
    f_start, f_end, sweep = 2 * BASS_NOTE, BASS_NOTE, 0.06
    phase = 2 * math.pi * (f_end * t + (f_start - f_end) * sweep * (1 - math.exp(-t / sweep)))
    attack = min(t / 0.003, 1.0)
    body = math.sin(phase) * attack * math.exp(-t / BODY_DECAY)
    upper = 0.40 * math.sin(2 * phase) * math.exp(-t / 0.14) + 0.20 * math.sin(3 * phase) * math.exp(-t / 0.09)
    click = 0.50 * random.uniform(-1, 1) * math.exp(-t / 0.004) if t < 0.03 else 0.0
    taper_start = HIT_LENGTH - HIT_TAPER
    taper = 1.0 if t < taper_start else 0.5 * (1 + math.cos(math.pi * (t - taper_start) / HIT_TAPER))
    return (body + upper * attack + click) * taper


def bass() -> list[float]:
    out = [0.0] * N
    for start, gain in HITS:
        first = int(start * RATE)
        for i in range(first, min(N, first + int(HIT_LENGTH * RATE))):
            out[i] += gain * bass_hit((i - first) / RATE)
    # Przesterowanie na sumie uderzeń (nakładające się uderzenia nie ściszają całości).
    return [math.tanh(DRIVE * v) / math.tanh(DRIVE) for v in out]


def whoosh() -> tuple[list[float], list[float]]:
    """Szum przefiltrowany dolnoprzepustowo z rosnącą częstotliwością odcięcia; panorama prawo → środek."""
    start, end = 0.15, LAND
    left, right = [0.0] * N, [0.0] * N
    y1 = y2 = 0.0
    for i in range(int(start * RATE), int((end + 0.05) * RATE)):
        t = i / RATE
        p = min(max((t - start) / (end - start), 0.0), 1.0)
        cutoff = 300 * (12 ** p)                      # 300 Hz → 3,6 kHz
        a = 1 - math.exp(-2 * math.pi * cutoff / RATE)
        n = random.uniform(-1, 1)
        y1 += a * (n - y1)                            # dwa filtry 1. rzędu = łagodniejsze zbocze
        y2 += a * (y1 - y2)
        env = (p ** 2) * (1 - max(0.0, (t - end) / 0.05))  # narasta, urywa się przy lądowaniu
        pan = 0.5 + 0.5 * (1 - p)                     # 1 = prawo, 0,5 = środek
        s = y2 * env * 2.2
        left[i] += s * math.cos(pan * math.pi / 2)
        right[i] += s * math.sin(pan * math.pi / 2)
    return left, right


def chimes() -> list[float]:
    """Szklane dzwoneczki: ton podstawowy + delikatne alikwoty, szybki atak, długie wybrzmienie."""
    out = [0.0] * N
    for start, f in CHIMES:
        first = int(start * RATE)
        for i in range(first, N):
            t = (i - first) / RATE
            env = min(t / 0.004, 1.0) * math.exp(-t / 0.45)
            if env < 1e-4 and t > 0.1:
                break
            w = 2 * math.pi * f * t
            out[i] += env * (math.sin(w) + 0.30 * math.sin(2 * w) * math.exp(-t / 0.15) + 0.12 * math.sin(3.01 * w) * math.exp(-t / 0.08))
    return out


def reverb(x: list[float], seed_offset: int) -> list[float]:
    """Prosty pogłos Schroedera (4 filtry grzebieniowe + 2 wszechprzepustowe); inny dla L i P = stereo."""
    combs = [(1557 + seed_offset, 0.80), (1617 + seed_offset, 0.79), (1491 + seed_offset, 0.81), (1422 + seed_offset, 0.78)]
    out = [0.0] * len(x)
    for delay, fb in combs:
        buf = [0.0] * delay
        damp, lp = 0.25, 0.0
        for i, v in enumerate(x):
            y = buf[i % delay]
            lp = y * (1 - damp) + lp * damp           # tłumienie wysokich w ogonie
            buf[i % delay] = v + lp * fb
            out[i] += y * 0.25
    for delay, g in ((225 + seed_offset // 4, 0.5), (556 + seed_offset // 4, 0.5)):
        buf = [0.0] * delay
        for i, v in enumerate(out):
            b = buf[i % delay]
            y = -v + b
            buf[i % delay] = v + b * g
            out[i] = y
    return out


# ---------- Miks ----------

def soft_limit(v: float) -> float:
    """Liniowo do LIMIT_KNEE, powyżej łagodnie dociąga do 1."""
    a = abs(v)
    if a <= LIMIT_KNEE:
        return v
    return math.copysign(LIMIT_KNEE + (1 - LIMIT_KNEE) * math.tanh((a - LIMIT_KNEE) / (1 - LIMIT_KNEE)), v)


def render() -> tuple[list[float], list[float]]:
    b = bass()
    wl, wr = whoosh()
    ch = chimes()
    # Dzwoneczki lekko rozłożone w stereo (pierwszy z lewej, ostatni z prawej).
    dry_l = [WHOOSH_LEVEL * wl[i] + CHIME_LEVEL * 1.1 * ch[i] for i in range(N)]
    dry_r = [WHOOSH_LEVEL * wr[i] + CHIME_LEVEL * 0.9 * ch[i] for i in range(N)]
    wet_l, wet_r = reverb(dry_l, 0), reverb(dry_r, 23)
    # Limiter na sumie: dzwoneczki i pogłos nakładające się na bas nie podnoszą szczytu,
    # więc normalizacja nie ścisza uderzeń.
    left = [soft_limit(b[i] + dry_l[i] + REVERB_WET * wet_l[i]) for i in range(N)]
    right = [soft_limit(b[i] + dry_r[i] + REVERB_WET * wet_r[i]) for i in range(N)]

    fade = int(TAIL_FADE * RATE)
    for i in range(fade):
        g = (i / fade) ** 2
        left[N - 1 - i] *= g
        right[N - 1 - i] *= g

    peak = max(max(abs(v) for v in left), max(abs(v) for v in right)) or 1.0
    k = 10 ** ((PEAK_DBFS + VOLUME_DB) / 20) / peak
    return [v * k for v in left], [v * k for v in right]


def main(path: str) -> None:
    left, right = render()
    with wave.open(path, 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        frames = bytearray()
        for l, r in zip(left, right):
            frames += struct.pack('<hh', int(max(-1.0, min(1.0, l)) * 32767), int(max(-1.0, min(1.0, r)) * 32767))
        w.writeframes(bytes(frames))
    print(f'zapisano {path}: {DURATION} s (świst, bas w {", ".join(f"{t:.2f} s" for t, _ in HITS)}, dzwoneczki, pogłos)')


if __name__ == '__main__':
    main(sys.argv[1])
