// CosmoOS/Sync/SupabaseClient.swift
// Supabase REST API client for invisible background sync
// All operations are async and non-blocking

import Foundation

@MainActor
final class SupabaseClient {
    static let shared: SupabaseClient? = {
        // Try to get credentials from APIKeys (Keychain) or Environment
        guard let url = APIKeys.supabaseUrl,
              let key = APIKeys.supabaseAnonKey else {
            print("⚠️ Supabase credentials not found - sync disabled")
            return nil
        }
        return SupabaseClient(url: url, key: key)
    }()

    private let baseURL: String
    private let apiKey: String
    private var authToken: String?

    private let session: URLSession

    init(url: String, key: String) {
        self.baseURL = url.hasSuffix("/") ? String(url.dropLast()) : url
        self.apiKey = key

        // Configure session for background sync
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        config.allowsCellularAccess = true

        self.session = URLSession(configuration: config)
    }

    // MARK: - Authentication
    func setAuthToken(_ token: String?) {
        self.authToken = token
    }

    // MARK: - Insert
    func insert(table: String, data: [String: Any]) async throws {
        let url = URL(string: "\(baseURL)/rest/v1/\(table)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")

        addHeaders(to: &request)

        request.httpBody = try JSONSerialization.data(withJSONObject: data)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SupabaseError.insertFailed
        }
    }

    // MARK: - Update
    func update(table: String, uuid: String, data: [String: Any]) async throws {
        var urlComponents = URLComponents(string: "\(baseURL)/rest/v1/\(table)")!
        urlComponents.queryItems = [URLQueryItem(name: "uuid", value: "eq.\(uuid)")]

        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")

        addHeaders(to: &request)

        request.httpBody = try JSONSerialization.data(withJSONObject: data)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SupabaseError.updateFailed
        }
    }

    // MARK: - Soft Delete
    func softDelete(table: String, uuid: String) async throws {
        try await update(table: table, uuid: uuid, data: [
            "is_deleted": true,
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ])
    }

    // MARK: - Fetch Changes
    func fetchChanges(table: String, since: Date?) async throws -> [[String: Any]] {
        var urlComponents = URLComponents(string: "\(baseURL)/rest/v1/\(table)")!

        var queryItems = [URLQueryItem(name: "is_deleted", value: "eq.false")]

        if let since = since {
            let sinceStr = ISO8601DateFormatter().string(from: since)
            queryItems.append(URLQueryItem(name: "updated_at", value: "gt.\(sinceStr)"))
        }

        queryItems.append(URLQueryItem(name: "order", value: "updated_at.asc"))
        queryItems.append(URLQueryItem(name: "limit", value: "100"))

        urlComponents.queryItems = queryItems

        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        addHeaders(to: &request)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SupabaseError.fetchFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw SupabaseError.invalidResponse
        }

        return json
    }

    // MARK: - Add Headers
    private func addHeaders(to request: inout URLRequest) {
        request.setValue(apiKey, forHTTPHeaderField: "apikey")

        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
    }
}

// MARK: - Supabase Errors
enum SupabaseError: LocalizedError {
    case insertFailed
    case updateFailed
    case fetchFailed
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .insertFailed: return "Failed to insert to Supabase"
        case .updateFailed: return "Failed to update Supabase"
        case .fetchFailed: return "Failed to fetch from Supabase"
        case .invalidResponse: return "Invalid response from Supabase"
        }
    }
}
