#!/usr/bin/env python3
"""Render Cosmo's deterministic interface palette. Python 3 + numpy + afconvert.

No sampled instruments, noise textures, pitch randomization, or room reverb.
A rounded, mildly phase-modulated pulse supplies the whole family. Short
raised-cosine attacks and tails make each gesture click-free; fixed relative
levels preserve hierarchy. Output: 48 kHz mono, 16-bit LPCM CAF on both platforms.

python3 scripts/generate_interface_sounds.py --out Resources/Sounds --proof /tmp/cosmo-audio
"""

import argparse
import hashlib
import json
import math
from pathlib import Path
import subprocess
import tempfile
import wave

import numpy as np

SR = 48_000


def pulse(frequency, duration, decay, brightness=0.12, bend=0.0):
    t = np.arange(round(duration * SR), dtype=np.float64) / SR
    # A sub-semitone settling curve adds contour without an audible glissando.
    phase = 2 * math.pi * frequency * (t + bend * 0.009 * (1 - np.exp(-t / 0.009)))
    voice = np.sin(phase + brightness * np.exp(-t / 0.018) * np.sin(2 * phase))
    voice += 0.065 * np.sin(2 * phase) * np.exp(-t / 0.028)
    attack = np.sin(np.minimum(t / 0.003, 1) * math.pi / 2) ** 2
    release = np.sin(np.minimum(np.maximum(duration - t - 1 / SR, 0) / 0.024, 1) * math.pi / 2) ** 2
    return voice * attack * np.exp(-t / decay) * release


def gesture(duration, layers, peak_db):
    result = np.zeros(round(duration * SR))
    for offset, frequency, length, decay, level, brightness, bend in layers:
        voice = pulse(frequency, length, decay, brightness, bend) * level
        start = round(offset * SR)
        count = min(len(voice), len(result) - start)
        result[start:start + count] += voice[:count]
    # Remove DC with a gentle first-order high pass, then master peak once.
    pole = math.exp(-2 * math.pi * 35 / SR)
    previous_input = previous_output = 0.0
    for i, sample in enumerate(result):
        output = sample - previous_input + pole * previous_output
        previous_input, previous_output = sample, output
        result[i] = output
    tail = min(round(0.014 * SR), len(result))
    result[-tail:] *= np.linspace(1, 0, tail) ** 2
    result *= 10 ** (peak_db / 20) / max(np.max(np.abs(result)), 1e-12)
    return result


def palette():
    # layer: onset, Hz, length, decay, level, brightness, settling bend.
    # Completion's second pulse arrives 56 ms later: a single compact gesture.
    return {
        "complete": gesture(.272, [(0, 740, .15, .027, .78, .16, .025),
                                    (.056, 1110, .216, .044, 1, .10, .008)], -15),
        "milestone": gesture(.440, [(0, 740, .16, .029, .68, .12, .012),
                                     (.056, 1110, .28, .058, 1, .09, .005),
                                     (.116, 1480, .324, .068, .27, .04, 0)], -16),
        "confirm": gesture(.156, [(0, 990, .156, .030, 1, .11, .012)], -19),
        "open": gesture(.132, [(0, 660, .132, .024, 1, .10, -.035)], -23),
        "close": gesture(.120, [(0, 555, .120, .021, 1, .10, .035)], -24),
        "place": gesture(.100, [(0, 830, .100, .015, 1, .25, .025),
                                 (0, 415, .065, .012, .3, .05, 0)], -22),
        "remove": gesture(.150, [(0, 620, .150, .030, 1, .09, .075)], -23),
        "undo": gesture(.188, [(0, 620, .125, .023, .64, .10, -.02),
                                (.042, 830, .146, .031, 1, .09, 0)], -22),
        "focus": gesture(.328, [(0, 555, .225, .040, .66, .08, .010),
                                 (.052, 830, .276, .060, 1, .07, 0)], -19),
    }


def write_wave(path, samples):
    with wave.open(str(path), "wb") as output:
        output.setparams((1, 2, SR, 0, "NONE", "not compressed"))
        output.writeframes(np.round(np.clip(samples, -1, 1) * 32767).astype("<i2").tobytes())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--proof", type=Path)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    if args.proof:
        args.proof.mkdir(parents=True, exist_ok=True)
    report = {"version": 3, "sample_rate": SR, "channels": 1, "cues": {}}
    sounds = palette()
    with tempfile.TemporaryDirectory() as temporary:
        for name, samples in sounds.items():
            wav = Path(temporary) / (name + ".wav")
            write_wave(wav, samples)
            destination = args.out / ("ui_" + name + ".caf")
            subprocess.run(["afconvert", "-f", "caff", "-d", "LEI16", str(wav), str(destination)], check=True)
            report["cues"][name] = {
                "duration_ms": round(len(samples) / SR * 1000),
                "peak_dbfs": round(20 * math.log10(np.max(np.abs(samples))), 2),
                "rms_dbfs": round(20 * math.log10(np.sqrt(np.mean(samples ** 2))), 2),
                "sha256": hashlib.sha256(destination.read_bytes()).hexdigest(),
            }
            if args.proof:
                write_wave(args.proof / (name + ".wav"), samples * .7)
    if args.proof:
        # User-facing preview: complete × 3, focus, milestone, then everyday cues.
        order = ["complete", "complete", "complete", "focus", "milestone", "confirm", "open", "place", "remove", "undo"]
        sequence = np.concatenate([part for name in order for part in (sounds[name] * .7, np.zeros(SR * 3 // 4))])
        write_wave(args.proof / "cosmo-sound-preview.wav", sequence)
        (args.proof / "manifest.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
