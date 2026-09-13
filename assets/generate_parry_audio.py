"""Generate the original BRASSLINE steel parry sound using Python's standard library."""
import math
from pathlib import Path
import random
import struct
import wave

rng = random.Random(803)
samples = []
for i in range(9000):
    t = i / 22050
    strike = .18 * rng.uniform(-1, 1) * math.exp(-t * 65)
    ring = sum(.16 * math.sin(2 * math.pi * hz * t) * math.exp(-t * decay)
               for hz, decay in [(1320, 13), (2237, 18), (3673, 26), (5410, 35)])
    samples.append(struct.pack('<h', int(26000 * max(-1, min(1, strike + ring)))))
with wave.open(str(Path(__file__).with_name('parry.wav')), 'wb') as output:
    output.setnchannels(1)
    output.setsampwidth(2)
    output.setframerate(22050)
    output.writeframes(b''.join(samples))
