// CosmoOS/Sync/SupabaseClient.swift
// Supabase REST API client for invisible background sync
// Phase 0: Enhanced with auth, upsert, Realtime readiness, and unified atoms table

import Foundation

@MainActor
final class SupabaseClient {
    static let shared: SupabaseClient? = {
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
    private var userId: String?

    private let session: URLSession

    init(url: String, key: String) {
        self.baseURL = url.hasSuffix("/") ? String(url.dropLast()) : url
        self.apiKey = key

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        config.allowsCellularAccess = true

        self.session = URLSession(configuration: config)

        // Load saved auth token if available
        if let savedToken = APIKeys.supabaseAuthToken {
            self.authToken = savedToken
        }
        if let savedUserId = APIKeys.supabaseUserId {
            self.userId = savedUserId
        }
    }

    // MARK: - Authentication

    func setAuthToken(_ token: String?) {
        self.authToken = token
    }

    func setUserId(_ id: String?) {
        self.userId = id
    }

    var currentUserId: String? { userId }
    var isAuthenticated: Bool { authToken != nil && userId != nil }

    // MARK: - Insert

    func insert(table: String, data: [String: Any]) async throws {
        let url = try buildURL(table: table)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        addHeaders(to: &request)
        request.httpBody = try JSONSerialization.data(withJSONObject: data)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw SupabaseError.insertFailed(statusCode: statusCode)
        }
    }

    // MARK: - Upsert (Insert or Update on Conflict)

    func upsert(table: String, data: [String: Any], onConflict: String) async throws {
        let url = try buildURL(table: table)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        addHeaders(to: &request)

        // Add on_conflict as query parameter
        if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = (components.queryItems ?? []) + [
                URLQueryItem(name: "on_conflict", value: onConflict)
            ]
            if let newURL = components.url {
                request.url = newURL
            }
        }

        // Supabase prefers header for merge strategy
        request.setValue("return=minimal,resolution=merge-duplicates", forHTTPHeaderField: "Prefer")

        request.httpBody = try JSONSerialization.data(withJSONObject: data)

        let (responseData, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: responseData, encoding: .utf8) ?? ""
            throw SupabaseError.upsertFailed(statusCode: statusCode, body: body)
        }
    }

    // MARK: - Batch Upsert

    func batchUpsert(table: String, records: [[String: Any]], onConflict: String) async throws {
        guard !records.isEmpty else { return }

        let url = try buildURL(table: table)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal,resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        addHeaders(to: &request)

        if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = (components.queryItems ?? []) + [
                URLQueryItem(name: "on_conflict", value: onConflict)
            ]
            if let newURL = components.url {
                request.url = newURL
            }
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: records)

        let (responseData, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: responseData, encoding: .utf8) ?? ""
            throw SupabaseError.upsertFailed(statusCode: statusCode, body: body)
        }
    }

    // MARK: - Update

    func update(table: String, uuid: String, data: [String: Any]) async throws {
        guard var urlComponents = URLComponents(string: "\(baseURL)/rest/v1/\(table)") else {
            throw SupabaseError.invalidURL
        }
        urlComponents.queryItems = [URLQueryItem(name: "uuid", value: "eq.\(uuid)")]

        guard let url = urlComponents.url else {
            throw SupabaseError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        addHeaders(to: &request)
        request.httpBody = try JSONSerialization.data(withJSONObject: data)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw SupabaseError.updateFailed(statusCode: statusCode)
        }
    }

    // MARK: - Soft Delete

    func softDelete(table: String, uuid: String) async throws {
        try await update(table: table, uuid: uuid, data: [
            "is_deleted": true,
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ])
    }

    // MARK: - Fetch Changes (Pull)

    func fetchChanges(
        table: String,
        since: Date?,
        userId: String? = nil,
        excludeLocalSource: Bool = false
    ) async throws -> [[String: Any]] {
        guard var urlComponents = URLComponents(string: "\(baseURL)/rest/v1/\(table)") else {
            throw SupabaseError.invalidURL
        }

        urlComponents.queryItems = Self.fetchChangesQueryItems(
            since: since,
            userId: userId,
            excludeLocalSource: excludeLocalSource
        )

        guard let url = urlComponents.url else {
            throw SupabaseError.invalidURL
        }
        var request = URLRequest(url: url)
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

    nonisolated static func fetchChangesQueryItems(
        since: Date?,
        userId: String? = nil,
        excludeLocalSource: Bool = false
    ) -> [URLQueryItem] {
        var queryItems = [URLQueryItem(name: "is_deleted", value: "eq.false")]

        if let since = since {
            let sinceStr = ISO8601DateFormatter().string(from: since)
            queryItems.append(URLQueryItem(name: "updated_at", value: "gt.\(sinceStr)"))
        }

        // Filter by user_id if provided (for RLS-bypassing service role calls)
        if let uid = userId {
            queryItems.append(URLQueryItem(name: "user_id", value: "eq.\(uid)"))
        }

        if excludeLocalSource {
            queryItems.append(SupabaseSyncTrafficPolicy.remoteOnlyQueryItem)
        }

        queryItems.append(URLQueryItem(name: "order", value: "updated_at.asc"))
        queryItems.append(URLQueryItem(name: "limit", value: "100"))

        return queryItems
    }

    // MARK: - Fetch Single Row

    func fetchOne(table: String, uuid: String) async throws -> [String: Any]? {
        guard var urlComponents = URLComponents(string: "\(baseURL)/rest/v1/\(table)") else {
            throw SupabaseError.invalidURL
        }

        urlComponents.queryItems = [
            URLQueryItem(name: "uuid", value: "eq.\(uuid)"),
            URLQueryItem(name: "limit", value: "1")
        ]

        guard let url = urlComponents.url else {
            throw SupabaseError.invalidURL
        }
        var request = URLRequest(url: url)
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

        return json.first
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

    // MARK: - URL Builder

    private func buildURL(table: String) throws -> URL {
        guard let url = URL(string: "\(baseURL)/rest/v1/\(table)") else {
            throw SupabaseError.invalidURL
        }
        return url
    }
}

// MARK: - Supabase Errors

enum SupabaseError: LocalizedError {
    case invalidURL
    case insertFailed(statusCode: Int)
    case updateFailed(statusCode: Int)
    case upsertFailed(statusCode: Int, body: String)
    case fetchFailed
    case invalidResponse
    case authRequired

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid Supabase URL"
        case .insertFailed(let code): return "Failed to insert to Supabase (HTTP \(code))"
        case .updateFailed(let code): return "Failed to update Supabase (HTTP \(code))"
        case .upsertFailed(let code, let body): return "Failed to upsert to Supabase (HTTP \(code)): \(body)"
        case .fetchFailed: return "Failed to fetch from Supabase"
        case .invalidResponse: return "Invalid response from Supabase"
        case .authRequired: return "Supabase authentication required"
        }
    }
}
