"""Exercise production Mac sync policy and REST writes against a local cloud stub.

No app launch, user database, keychain, or real cloud connection is involved.
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json
import argparse
import subprocess
import tempfile
import threading
from urllib.parse import urlparse, parse_qs

ROOT = Path(__file__).resolve().parents[1]

class Cloud(BaseHTTPRequestHandler):
    rows = {}

    def log_message(self, *_):
        pass

    def respond(self, body):
        data = json.dumps(body).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        key = (urlparse(self.path).path, body['uuid'])
        if 'ignore-duplicates' not in self.headers.get('Prefer', '') or key not in self.rows:
            self.rows[key] = body
        self.respond([])

    def do_PATCH(self):
        parsed = urlparse(self.path)
        uuid = parse_qs(parsed.query)['uuid'][0].removeprefix('eq.')
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        key = (parsed.path, uuid)
        if key in self.rows:
            self.rows[key].update(body)
            self.respond([{'uuid': uuid}])
        else:
            self.respond([])  # A successful HTTP response can affect ZERO rows.

    def do_GET(self):
        parsed = urlparse(self.path)
        uuid = parse_qs(parsed.query)['uuid'][0].removeprefix('eq.')
        row = self.rows.get((parsed.path, uuid))
        self.respond([row] if row else [])


def block(source, start, end):
    return source.split(start, 1)[1].split(end, 1)[0]


parser = argparse.ArgumentParser()
parser.add_argument('--ios-core', type=Path, help='Test a CosmoCoreKit source tree instead of the Mac client')
args = parser.parse_args()

server = ThreadingHTTPServer(('127.0.0.1', 0), Cloud)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    client = (ROOT / 'Sync/SupabaseClient.swift').read_text()
    integration = (ROOT / 'Sync/SyncIntegration.swift').read_text()
    tracker = (ROOT / 'Sync/ChangeTracker.swift').read_text()
    engine = (ROOT / 'Sync/SyncEngine.swift').read_text()
    traffic = (ROOT / 'Sync/SupabaseSyncTrafficPolicy.swift').read_text()
    disposition = 'enum SyncWriteDisposition' + block(integration, 'enum SyncWriteDisposition', '// MARK: - AtomRepository')
    immediate = 'let writeDisposition: SyncWriteDisposition' + block(tracker, 'let writeDisposition: SyncWriteDisposition', 'nonisolated(unsafe) let preparedPayload')
    # Skip the similarly named property of PushPayloadPrep; keep the actual decision.
    prep = block(engine, 'private nonisolated static func preparePushPayload(', '/// Convert TEXT JSON fields')
    batch = 'let writeDisposition: SyncWriteDisposition' + block(prep, 'let writeDisposition: SyncWriteDisposition', 'return PushPayloadPrep')
    failures = traffic[traffic.index('struct SyncFailureResolution:'):]
    support = '''
import Foundation
// Dependencies outside the tested code. Credentials are deliberately unavailable.
enum APIKeys {
    static var supabaseUrl: String? { nil }
    static var supabaseAnonKey: String? { nil }
    static var supabaseAuthToken: String? { nil }
    static var supabaseUserId: String? { nil }
}
enum SupabaseSyncTrafficPolicy {
    static let localSource = "mac"
    static var remoteOnlyQueryItem: URLQueryItem { URLQueryItem(name: "_source", value: "neq.mac") }
}
enum ISO8601 { static func string(from date: Date) -> String { ISO8601DateFormatter().string(from: date) } }
'''
    if args.ios_core:
        sync = args.ios_core / 'Sources/Sync'
        client = (sync / 'SupabaseRESTClient.swift').read_text()
        tracker = (sync / 'ChangeTracker.swift').read_text()
        engine = (sync / 'SyncEngine.swift').read_text()
        traffic = (sync / 'SupabaseSyncTrafficPolicy.swift').read_text()
        disposition = 'public enum SyncWriteDisposition' + block(tracker, 'public enum SyncWriteDisposition', '@MainActor')
        decision = block(tracker, 'nonisolated public static func disposition(table: String, operation: String, serverVersion: Int) -> SyncWriteDisposition {', '\n    }')
        immediate = 'let writeDisposition: SyncWriteDisposition = { ' + decision + ' }()'
        batch = 'let table = tableName\n' + immediate
        assert 'ChangeTracker.disposition(table: table, operation: operation, serverVersion: serverVersion)' in engine
        failures = traffic[traffic.index('public struct SyncFailureResolution:'):]
        support += """
enum CosmoKeychain {
    static let supabaseProjectUrl = "https://example.test"
    static let supabasePublishableKey = "fixture"
    static var supabaseAuthToken: String? { nil }
    static var supabaseUserId: String? { nil }
}
typealias SupabaseClient = SupabaseRESTClient
"""
    harness = (ROOT / 'scripts/OfflineCaptureSyncRegression.swift').read_text()
    swift_source = support + client + disposition + failures
    swift_source += '\nfunc immediateDisposition(table: String, operation: String, serverVersion: Int) -> SyncWriteDisposition {\n' + immediate + '\nreturn writeDisposition\n}\n'
    swift_source += '\nfunc batchDisposition(tableName: String, operation: String, serverVersion: Int) -> SyncWriteDisposition {\n' + batch + '\nreturn writeDisposition\n}\n'
    swift_source += harness
    with tempfile.TemporaryDirectory(prefix='cosmo-offline-regression-') as directory:
        source = Path(directory) / 'Regression.swift'
        source.write_text(swift_source)
        binary = str(Path(directory) / 'regression')
        subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library', '-module-cache-path', str(Path(directory) / 'modules'), str(source), '-o', binary], check=True)
        subprocess.run([binary, f'http://127.0.0.1:{server.server_port}'], check=True)
finally:
    server.shutdown()
    server.server_close()
