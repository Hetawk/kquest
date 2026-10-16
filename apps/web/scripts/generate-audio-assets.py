import math
import struct
import wave
from pathlib import Path


SAMPLE_RATE = 22050
OUTPUT = Path(__file__).resolve().parents[1] / "static" / "audio"


def write_wave(filename, samples):
    OUTPUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUTPUT / filename), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)
        output.writeframes(b"".join(struct.pack("<h", round(max(-1, min(1, value)) * 32767)) for value in samples))


def ambient_pad():
    duration = 10
    tones = (176, 220, 264, 330)
    samples = []
    for index in range(SAMPLE_RATE * duration):
        time = index / SAMPLE_RATE
        swell = 0.7 + 0.3 * math.sin(2 * math.pi * time / duration)
        value = sum(math.sin(2 * math.pi * tone * time) for tone in tones) / len(tones)
        samples.append(value * swell * 0.16)
    write_wave("ambient-pad.wav", samples)


def soft_tick():
    duration = 0.12
    samples = []
    for index in range(round(SAMPLE_RATE * duration)):
        time = index / SAMPLE_RATE
        envelope = math.exp(-time * 38) * min(1, time * 120)
        tone = math.sin(2 * math.pi * 660 * time) + 0.25 * math.sin(2 * math.pi * 1320 * time)
        samples.append(tone * envelope * 0.09)
    write_wave("soft-tick.wav", samples)


def warm_chord():
    duration = 1.1
    tones = (261.63, 329.63, 392.0, 523.25)
    samples = []
    for index in range(round(SAMPLE_RATE * duration)):
        time = index / SAMPLE_RATE
        envelope = min(1, time * 18) * math.exp(-time * 3)
        value = sum(math.sin(2 * math.pi * tone * time) for tone in tones) / len(tones)
        samples.append(value * envelope * 0.2)
    write_wave("warm-chord.wav", samples)


def soft_thud():
    duration = 0.42
    samples = []
    for index in range(round(SAMPLE_RATE * duration)):
        time = index / SAMPLE_RATE
        envelope = math.exp(-time * 11) * min(1, time * 70)
        frequency = 115 - 35 * time / duration
        samples.append(math.sin(2 * math.pi * frequency * time) * envelope * 0.18)
    write_wave("soft-thud.wav", samples)


if __name__ == "__main__":
    ambient_pad()
    soft_tick()
    warm_chord()
    soft_thud()
