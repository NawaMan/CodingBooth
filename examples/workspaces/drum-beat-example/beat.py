#!/usr/bin/env python3
"""Synthesize a drum beat (kick / snare / hi-hat) to a WAV file — standard library only.

Every sound is made from scratch: no samples, no audio libraries.

    kick   a sine wave whose pitch drops fast (the "thump")
    snare  a short tone plus decaying noise
    hat    high-passed noise with a very short decay

Edit PATTERN to change the groove: 16 steps per bar, x = hit, o = accent, . = rest.
"""
import argparse
import math
import random
import struct
import wave

SR = 44100

PATTERN = {
    "kick":  "x.....x...x.....",
    "snare": "....x.......x..o",
    "hat":   "x.x.x.x.x.x.x.xo",
}


def kick(n):
    out, phase = [], 0.0
    for i in range(n):
        t = i / SR
        freq = 45 + 110 * math.exp(-t * 30)
        phase += 2 * math.pi * freq / SR
        out.append(math.sin(phase) * math.exp(-t * 7))
    return out


def snare(n):
    out = []
    for i in range(n):
        t = i / SR
        tone = math.sin(2 * math.pi * 185 * t) * math.exp(-t * 25)
        noise = random.uniform(-1, 1) * math.exp(-t * 16)
        out.append(0.45 * tone + 0.7 * noise)
    return out


def hat(n):
    out, prev = [], 0.0
    for i in range(n):
        t = i / SR
        x = random.uniform(-1, 1)
        out.append((x - prev) * 0.5 * math.exp(-t * 60))  # crude high-pass
        prev = x
    return out


VOICES = {"kick": (kick, 0.9), "snare": (snare, 0.6), "hat": (hat, 0.25)}


def render(bpm, bars, volume):
    step = 60 / bpm / 4  # one 16th note, in seconds
    total = int(SR * step * 16 * bars) + SR // 2
    mix = [0.0] * total
    for name, (voice, gain) in VOICES.items():
        sound = voice(int(SR * 0.5))
        for bar in range(bars):
            for s, ch in enumerate(PATTERN[name]):
                if ch == ".":
                    continue
                g = gain * (1.4 if ch == "o" else 1.0)
                start = int(SR * step * (bar * 16 + s))
                for i, v in enumerate(sound[: total - start]):
                    mix[start + i] += v * g
    peak = max(abs(v) for v in mix) or 1.0
    return [v / peak * volume for v in mix]


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--bpm", type=int, default=100, help="tempo (default 100)")
    parser.add_argument("--bars", type=int, default=4, help="bars to render (default 4)")
    parser.add_argument("--out", default="beat.wav", help="output file (default beat.wav)")
    parser.add_argument("--volume", type=float, default=0.9, help="peak level, 0-1 (default 0.9)")
    args = parser.parse_args()

    mix = render(args.bpm, args.bars, max(0.0, min(args.volume, 1.0)))
    with wave.open(args.out, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(v * 32767)) for v in mix))
    print(f"{args.out}: {args.bars} bars at {args.bpm} BPM, {len(mix) / SR:.1f}s")


if __name__ == "__main__":
    main()
