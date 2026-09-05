#!/usr/bin/env python3
"""Run the real iOS sound engine's lifecycle regression on a booted simulator.

Usage: python3 scripts/verify_ios_sound_lifecycle.py --device SIMULATOR_UUID
Requires Xcode. Installs a separate, temporary test app; never replaces Cosmo.
"""
import argparse
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    args = parser.parse_args()
    sdk = subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True).strip()
    identifier = "com.cosmo.audio-lifecycle-regression"
    with tempfile.TemporaryDirectory(prefix="cosmo-ios-audio-regression-") as directory:
        root = Path(directory)
        source = root / "Regression.swift"
        source.write_text((ROOT / "Core/SoundEngine.swift").read_text() + "\n" +
                          (ROOT / "scripts/iOSSoundLifecycleRegression.swift").read_text())
        app = root / "Regression.app"
        app.mkdir()
        shutil.copytree(ROOT / "Resources/Sounds", app / "Sounds")
        with (app / "Info.plist").open("wb") as file:
            plistlib.dump({"CFBundleIdentifier": identifier, "CFBundleName": "Audio Regression",
                           "CFBundleExecutable": "Regression", "CFBundleVersion": "1",
                           "CFBundleShortVersionString": "1", "CFBundlePackageType": "APPL",
                           "MinimumOSVersion": "26.0", "UIDeviceFamily": [1], "UILaunchScreen": {},
                           "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": False}}, file)
        subprocess.run(["xcrun", "--sdk", "iphonesimulator", "swiftc", "-swift-version", "6",
                        "-parse-as-library", "-target", "arm64-apple-ios26.0-simulator", "-sdk", sdk,
                        "-module-cache-path", str(root / "cache"), str(source), "-o", str(app / "Regression")], check=True)
        subprocess.run(["xcrun", "simctl", "install", args.device, str(app)], check=True)
        try:
            result = subprocess.run(["xcrun", "simctl", "launch", "--console", args.device, identifier],
                                    text=True, capture_output=True, timeout=60, check=True)
            print(result.stdout)
            if "ALL PASS" not in result.stdout:
                raise RuntimeError("Audio lifecycle regression did not pass: " + result.stderr)
        finally:
            subprocess.run(["xcrun", "simctl", "uninstall", args.device, identifier], check=False, capture_output=True)


if __name__ == "__main__":
    main()
