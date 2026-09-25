#!/usr/bin/env python3
"""Génère les sons du shell (carillons doux), 100 % originaux et libres de droits.

    python3 tools/generate-sounds.py [dossier_de_sortie]
"""

import math
import random
import struct
import sys
import wave
from pathlib import Path

RATE = 48000


def tone(freq: float, dur: float, vol: float = 0.5, attack: float = 0.006, decay: float = 5.0) -> list[float]:
    """Note de type clochette : fondamentale + harmoniques douces, attaque rapide, extinction exponentielle."""
    n = int(RATE * dur)
    out = []
    for i in range(n):
        t = i / RATE
        env = min(1.0, t / attack) * math.exp(-decay * t)
        s = (math.sin(2 * math.pi * freq * t)
             + 0.35 * math.sin(2 * math.pi * freq * 2 * t) * math.exp(-3 * t)
             + 0.12 * math.sin(2 * math.pi * freq * 3.01 * t) * math.exp(-6 * t))
        out.append(vol * env * s / 1.47)
    return out


def mix(*parts: tuple[float, list[float]]) -> list[float]:
    length = max(int(off * RATE) + len(p) for off, p in parts)
    buf = [0.0] * length
    for off, p in parts:
        start = int(off * RATE)
        for i, v in enumerate(p):
            buf[start + i] += v
    return buf


def click() -> list[float]:
    random.seed(27)
    n = int(RATE * 0.09)
    return [0.45 * random.uniform(-1, 1) * math.exp(-60 * i / RATE) for i in range(n)]


def save(path: Path, samples: list[float]) -> None:
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = 0.8 / peak if peak > 0.8 else 1.0
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * scale)) * 32767)) for s in samples))


def main() -> None:
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "config/quickshell/caelestia/assets/sounds"
    out.mkdir(parents=True, exist_ok=True)
    E6, A6, C6, G5, E5, C5, A4 = 1318.5, 1760.0, 1046.5, 784.0, 659.3, 523.3, 440.0
    sounds = {
        "notification": mix((0, tone(E6, 0.9, 0.45)), (0.11, tone(A6, 1.1, 0.4))),
        "device_connect": mix((0, tone(G5, 0.6, 0.45)), (0.09, tone(C6, 0.8, 0.45))),
        "device_disconnect": mix((0, tone(C6, 0.6, 0.45)), (0.09, tone(G5, 0.8, 0.45))),
        "plug": mix((0, tone(C5, 0.5, 0.4)), (0.07, tone(E5, 0.5, 0.4)), (0.14, tone(G5, 0.9, 0.4))),
        "unplug": mix((0, tone(G5, 0.5, 0.4)), (0.07, tone(E5, 0.5, 0.4)), (0.14, tone(C5, 0.9, 0.4))),
        "battery_low": mix((0, tone(A4, 0.35, 0.5, decay=9)), (0.22, tone(A4, 0.6, 0.5, decay=7))),
        "screenshot": mix((0, click()), (0.05, tone(C6, 0.35, 0.25, decay=12))),
    }
    for name, samples in sounds.items():
        save(out / f"{name}.wav", samples)
        print(f"  {name}.wav")


if __name__ == "__main__":
    main()
