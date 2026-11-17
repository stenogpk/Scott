import math
import os
import struct
import wave

OUT = "assets/sounds"
RATE = 22050
os.makedirs(OUT, exist_ok=True)

def write_tone(filename, notes, duration=0.12, volume=0.22, gap=0.025):
    samples = []
    for freq in notes:
        count = int(RATE * duration)
        for i in range(count):
            t = i / RATE
            fade = min(1.0, i / max(1, int(RATE * 0.008)), (count - i) / max(1, int(RATE * 0.02)))
            value = math.sin(2 * math.pi * freq * t) * volume * max(0, fade)
            samples.append(int(max(-1, min(1, value)) * 32767))
        samples.extend([0] * int(RATE * gap))
    with wave.open(os.path.join(OUT, filename), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(b"".join(struct.pack("<h", s) for s in samples))

sounds = {
    "card_discard.wav": ([520, 360], 0.075, 0.18),
    "card_draw.wav": ([440, 660], 0.09, 0.16),
    "previous_pickup.wav": ([620, 780, 920], 0.075, 0.17),
    "show.wav": ([520, 700, 880], 0.16, 0.2),
    "failed_show.wav": ([330, 250, 180], 0.18, 0.22),
    "elimination.wav": ([440, 330, 220], 0.2, 0.2),
    "winner.wav": ([523, 659, 784, 1047], 0.2, 0.22),
    "shuffle.wav": ([360, 430, 390, 470, 410], 0.055, 0.13),
    "tap.wav": ([740], 0.035, 0.10),
}
for name, (notes, duration, volume) in sounds.items():
    write_tone(name, notes, duration, volume)
print(f"Generated {len(sounds)} original SCOTT sound effects in {OUT}")
