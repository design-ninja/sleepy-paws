#!/usr/bin/env python3
"""Synthesize a sleepy little yawn and a soft closing pop."""
import math
import struct
import wave
from pathlib import Path

RATE = 44100
NOTES = (
    (0.00, 0.19, 570, 660, 0.19),
    (0.16, 0.36, 530, 235, 0.24),
    (0.50, 0.27, 245, 140, 0.23),
    (0.83, 0.19, 360, 150, 0.17),
)

samples = [0.0] * RATE * 2
for start, duration, high, low, volume in NOTES:
    phase = 0.0
    for i in range(int(duration * RATE)):
        t = i / RATE
        progress = t / duration
        pitch = high * (low / high) ** progress + 7 * math.sin(2 * math.pi * 12 * t)
        phase += 2 * math.pi * pitch / RATE
        envelope = min(1, t / 0.018) * (1 - progress) ** 1.35
        tone = math.sin(phase) + 0.32 * math.sin(2 * phase) + 0.13 * math.sin(3 * phase)
        samples[int(start * RATE) + i] += volume * envelope * tone
path = Path(__file__).resolve().parents[1] / "Resources" / "TimeIsUp.wav"
with wave.open(str(path), "wb") as output:
    output.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
    output.writeframes(b"".join(struct.pack("<h", round(32767 * sample)) for sample in samples[:int(1.05 * RATE)]))
