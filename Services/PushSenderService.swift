// CosmoOS/Services/PushSenderService.swift
// The Mac speaks APNs directly — no server. A .p8 key (Settings → Sync →
// iPhone Push) signs an ES256 JWT; the push rides HTTP/2 straight to Apple
// and lights the iPhone up with a SCAN_REQUEST notification that deep-links
// into the scanner. Tokens come from the device_push_tokens table the phone
// maintains.

import CryptoKit
import Foundation

@MainActor
final class PushSenderService {
    static let shared = PushSenderService()

    private init() {}

    /// Cached JWT — Apple accepts a token for up to an hour; re-signing per
    /// push is wasteful and Apple throttles overly fresh tokens.
    private var cachedJWT: (token: String, issuedAt: Date)?

    var isConfigured: Bool { APIKeys.hasAPNs }

    enum PushError: LocalizedError {
        case notConfigured
        case badPrivateKey
        case noDeviceToken
        case apns(status: Int, body: String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Add your APNs Team ID, Key ID, and .p8 key in Settings → Sync."
            case .badPrivateKey: return "The APNs .p8 key couldn't be read."
            case .noDeviceToken: return "Your iPhone hasn't registered for push yet — open Cosmo on the phone once."
            case .apns(let status, let body): return "APNs rejected the push (HTTP \(status)): \(body.prefix(160))"
            }
        }
    }

    /// Wake the iPhone for a scan request. Sends to every registered iOS
    /// device token (personal account — usually exactly one phone).
    func sendScanRequest(_ request: CaptureRequest) async throws {
        guard isConfigured else { throw PushError.notConfigured }
        let devices = try await fetchDeviceTokens()
        guard !devices.isEmpty else { throw PushError.noDeviceToken }

        let title = "Scan for your Mac"
        let body = request.kind == .inquiryScan
            ? "Photograph pages into “\(request.questionTitle ?? request.deepDiveTitle ?? "your session")”"
            : "Photograph pages into your Inbox"

        let payload: [String: Any] = [
            "aps": [
                "alert": ["title": title, "body": body],
                "sound": "default",
                "category": "SCAN_REQUEST",
                "interruption-level": "time-sensitive",
            ],
            "deepLink": "cosmo://scan-request/\(request.uuid)",
        ]

        var lastError: Error?
        for device in devices {
            do {
                try await send(payload: payload, to: device)
            } catch {
                lastError = error
            }
        }
        if devices.allSatisfy({ _ in lastError != nil }), let lastError { throw lastError }
    }

    // MARK: - Device tokens

    private struct DeviceToken {
        let token: String
        let environment: String
        let bundleId: String
    }

    private func fetchDeviceTokens() async throws -> [DeviceToken] {
        guard let client = SupabaseClient.shared, client.isAuthenticated else { return [] }
        let rows = try await client.fetchChanges(
            table: "device_push_tokens",
            since: nil,
            excludeLocalSource: false,
            limit: 10
        )
        return rows.compactMap { row in
            guard let token = row["token"] as? String, !token.isEmpty,
                  (row["platform"] as? String ?? "ios") == "ios" else { return nil }
            return DeviceToken(
                token: token,
                environment: row["environment"] as? String ?? "production",
                bundleId: row["bundle_id"] as? String ?? (APIKeys.apnsBundleId ?? "")
            )
        }
    }

    // MARK: - APNs transport

    private func send(payload: [String: Any], to device: DeviceToken) async throws {
        let host = device.environment == "development"
            ? "api.sandbox.push.apple.com"
            : "api.push.apple.com"
        guard let url = URL(string: "https://\(host)/3/device/\(device.token)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("bearer \(try jwt())", forHTTPHeaderField: "authorization")
        let topic = device.bundleId.isEmpty ? (APIKeys.apnsBundleId ?? "") : device.bundleId
        request.setValue(topic, forHTTPHeaderField: "apns-topic")
        request.setValue("alert", forHTTPHeaderField: "apns-push-type")
        request.setValue("10", forHTTPHeaderField: "apns-priority")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            throw PushError.apns(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        print("📮 APNs push delivered (\(device.environment))")
    }

    // MARK: - JWT (ES256, cached ~45 min)

    private func jwt() throws -> String {
        if let cachedJWT, Date().timeIntervalSince(cachedJWT.issuedAt) < 45 * 60 {
            return cachedJWT.token
        }
        guard let teamId = APIKeys.apnsTeamId, let keyId = APIKeys.apnsKeyId,
              let pem = APIKeys.apnsPrivateKey else {
            throw PushError.notConfigured
        }
        guard let key = try? P256.Signing.PrivateKey(pemRepresentation: pem) else {
            throw PushError.badPrivateKey
        }

        let header = ["alg": "ES256", "kid": keyId]
        let claims: [String: Any] = ["iss": teamId, "iat": Int(Date().timeIntervalSince1970)]
        let headerPart = try Self.base64URL(JSONSerialization.data(withJSONObject: header))
        let claimsPart = try Self.base64URL(JSONSerialization.data(withJSONObject: claims))
        let signingInput = "\(headerPart).\(claimsPart)"
        let signature = try key.signature(for: Data(signingInput.utf8))
        let token = "\(signingInput).\(Self.base64URL(signature.rawRepresentation))"
        cachedJWT = (token, Date())
        return token
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
