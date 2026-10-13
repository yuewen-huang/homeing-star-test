"""Generate a short, dry impact WAV without adding third-party audio."""

from __future__ import annotations

import math
import random
import wave
from pathlib import Path


SAMPLE_RATE = 44_100
DURATION = 0.11


def main() -> None:
	output = Path(__file__).resolve().parents[1] / "assets" / "sideview" / "audio" / "combat" / "hit_impact.wav"
	output.parent.mkdir(parents=True, exist_ok=True)
	random.seed(14827)
	frames = bytearray()
	for index in range(int(SAMPLE_RATE * DURATION)):
		time = index / SAMPLE_RATE
		envelope = math.exp(-time * 34.0)
		thump = math.sin(math.tau * (145.0 - 65.0 * min(time / DURATION, 1.0)) * time) * 0.46
		noise = (random.random() * 2.0 - 1.0) * math.exp(-time * 62.0) * 0.38
		value = max(-1.0, min(1.0, (thump + noise) * envelope))
		frames.extend(int(value * 32767.0).to_bytes(2, "little", signed=True))
	with wave.open(str(output), "wb") as stream:
		stream.setnchannels(1)
		stream.setsampwidth(2)
		stream.setframerate(SAMPLE_RATE)
		stream.writeframes(frames)


if __name__ == "__main__":
	main()
