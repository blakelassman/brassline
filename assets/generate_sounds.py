"""Regenerate the original prototype WAV effects. Developer tool, not needed to play."""
from pathlib import Path
import wave
import math
import random
import struct

out = Path(__file__).resolve().parent
settings = {
    'rifle': (.16, 90), 'pistol': (.28, 65), 'blast': (.65, 38),
    'tick': (.07, 1150), 'jump': (.16, 280), 'hit': (.08, 850),
    'head': (.26, 1450), 'equip': (.12, 410), 'sword': (.22, 190),
    'step': (.065, 110), 'sniper': (.48, 52), 'bolt_open': (.19, 780), 'bolt_close': (.16, 430), 'hurt': (.14, 100),
}
rate = 22050
for name, (duration, frequency) in settings.items():
    rng = random.Random(2026)
    data = []
    last = 0.0
    for i in range(int(duration * rate)):
        t = i / rate
        phase = t / duration
        last = .75 * last + .25 * rng.uniform(-1, 1)
        tone = math.sin(2 * math.pi * (frequency*t + (60 if name == 'jump' else -20)*t*t))
        if name in ['bolt_open', 'bolt_close']:
            # Original dry metal ratchet and bolt-seat clack.
            clicks = 0.0
            for onset, strength in [(0, .7), (.032, .45), (.068, .28)]:
                if t >= onset:
                    age = t-onset
                    clicks += (rng.uniform(-1, 1)*.65+math.sin(2*math.pi*frequency*age)*.35)*math.exp(-age*95)*strength
            scrape = last*math.sin(math.pi*phase)*math.exp(-phase*3)*.4
            sample = math.tanh((clicks+scrape)*1.7)*.8
        elif name == 'hurt':
            sample = (last*.45+tone*.55)*math.exp(-phase*7)*.8
        elif name == 'head':
            # Original impact: low thump, bright initial crack and staggered grit.
            crack = rng.uniform(-1, 1) * math.exp(-t * 140) * .75
            thump = math.sin(2 * math.pi * (135*t - 150*t*t)) * math.exp(-t*30) * .65
            grit = 0.0
            for onset, strength in [(0.018, .45), (.038, .30), (.061, .18)]:
                if t >= onset:
                    grit += rng.uniform(-1, 1) * math.exp(-(t-onset)*85) * strength
            ring = math.sin(2*math.pi*1760*t)*math.exp(-t*25)*.10
            sample = math.tanh((crack+thump+grit+ring)*1.2)*.85
        elif name in ['rifle', 'pistol', 'blast', 'sniper']:
            sample = (.75*last + .25*tone) * math.exp(-phase*6)
        elif name in ['step', 'sword', 'equip']:
            sample = (.7*last + .3*tone) * math.sin(math.pi*phase) * math.exp(-phase*4)
        else:
            sample = tone * math.sin(math.pi*phase) * .45
        data.append(struct.pack('<h', int(max(-1, min(1, sample))*29000)))
    with wave.open(str(out / (name + '.wav')), 'wb') as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(rate)
        f.writeframes(b''.join(data))
