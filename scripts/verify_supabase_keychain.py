"""Compile and exercise the production storage without launching the app or reading credentials."""
from pathlib import Path
import subprocess
import tempfile

source = Path("Sync/SupabaseAuthService.swift").read_text()
assert "storage: SupabaseSessionKeychainStorage()" in source, "SDK still uses prompting legacy storage"
storage = source.split("// MARK: - Non-interactive SDK session storage\n", 1)[1]
tests = Path("scripts/SupabaseKeychainRegression.swift").read_text()
with tempfile.TemporaryDirectory() as directory:
    swift = Path(directory) / "main.swift"
    swift.write_text("import Foundation\nimport Security\nprotocol AuthLocalStorage: Sendable { func store(key: String, value: Data) throws; func retrieve(key: String) throws -> Data?; func remove(key: String) throws }\n" + storage + tests)
    binary = str(Path(directory) / "regression")
    subprocess.run(["swiftc", "-swift-version", "5", "-module-cache-path", str(Path(directory) / "modules"), str(swift), "-o", binary], check=True)
    subprocess.run([binary], check=True)
