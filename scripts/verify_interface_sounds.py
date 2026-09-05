#!/usr/bin/env python3
"""Verify shipped CAFs, cross-platform parity, and real Swift playback policies."""
import argparse
import math
from pathlib import Path
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def samples(path):
    data = path.read_bytes()
    assert data[:4] == b"caff", path
    position = 8
    description = None
    pcm = None
    while position + 12 <= len(data):
        kind, length = struct.unpack_from(">4sq", data, position)
        position += 12
        chunk = data[position:position + length]
        if kind == b"desc":
            description = struct.unpack(">d4sIIIII", chunk)
        if kind == b"data":
            pcm = chunk[4:]
        position += length
    assert description and pcm is not None, path
    rate, encoding, flags, packet, frames, channels, bits = description
    assert (rate, encoding, channels, bits) == (48000, b"lpcm", 1, 16), description
    # CAFFile.h uses IsLittleEndian (the inverse of AudioStreamBasicDescription).
    assert flags & 2 != 0, "Expected little-endian LPCM"
    return [value[0] / 32768 for value in struct.iter_unpack("<h", pcm)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ios", type=Path)
    args = parser.parse_args()
    expected = {"complete", "milestone", "confirm", "open", "close", "place", "remove", "undo", "focus"}
    bank = ROOT / "Resources/Sounds"
    assert {p.stem[3:] for p in bank.glob("ui_*.caf")} == expected
    assert not list(bank.glob("snd_*.caf")), "Legacy samples still ship"
    for cue in sorted(expected):
        path = bank / ("ui_" + cue + ".caf")
        values = samples(path)
        peak = max(map(abs, values))
        assert .05 < len(values) / 48000 <= .5, cue
        assert peak < 10 ** (-14.9 / 20), cue
        assert abs(values[0]) < 1 / 32768 and abs(values[-1]) < 1 / 32768, cue
        assert abs(sum(values) / len(values)) < .0001, cue
        # At most three voices, all worst-case phase-aligned, remain below clipping.
        assert peak * 3 < 1, cue
        if args.ios:
            assert path.read_bytes() == (args.ios / "CosmoiOS/Resources/Sounds" / path.name).read_bytes(), cue
    if args.ios:
        for mac, ios in [("Core/SoundEngine.swift", "CosmoiOS/Sources/Design/SoundEngine.swift"),
                         ("Settings/SoundSettingsView.swift", "CosmoiOS/Sources/Settings/SoundSettingsView.swift")]:
            assert (ROOT/mac).read_bytes() == (args.ios/ios).read_bytes(), f"Parity drift: {mac}"
    print("PASS: 9 mastered assets; format, duration, peak headroom, DC, endpoints, and platform parity.", flush=True)
    with tempfile.TemporaryDirectory(prefix="cosmo-audio-tests-") as temporary:
        binary = str(Path(temporary) / "policy-tests")
        subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-parse-as-library",
                        "-module-cache-path", str(Path(temporary)/"cache"),
                        str(ROOT/"Core/SoundEngine.swift"), str(ROOT/"scripts/SoundPlaybackRegression.swift"),
                        "-o", binary], check=True)
        subprocess.run([binary], check=True)


if __name__ == "__main__":
    main()
