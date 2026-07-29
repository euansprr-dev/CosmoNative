// CosmoOS/Services/GoogleDrive/GoogleDriveClient.swift
// Drive v3 over URLSession: folders, uploads, revisions.
//
// Two things shape this file more than anything else.
//
// SCOPE CONSEQUENCE: under `drive.file` we can only see files this app made.
// `files.list` will never return the user's existing folders, so there is no
// such thing as "browse my Drive and pick a destination" here. Cosmo creates
// and owns its folders. The user is free to drag them anywhere in Drive
// afterwards — a Drive file ID survives being moved or renamed, so the
// connection doesn't break when they tidy up.
//
// 401 LADDER: an expired token and a revoked token look identical from here —
// both are a 401. So a 401 buys exactly one forced refresh and one retry. If
// the retry also 401s, the grant is genuinely gone and we surface
// `reconnectRequired` rather than looping. `withNetworkRetry` sits underneath
// for 429/5xx, so transport flakiness never reaches this ladder.
// July 2026

import Foundation

// MARK: - Models

struct DriveFile: Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let mimeType: String
    let webViewLink: String?
    let modifiedTime: Date?

    var isFolder: Bool { mimeType == GoogleDriveClient.folderMimeType }

    /// A link that always works, even when Drive omitted `webViewLink`.
    var openURL: URL? {
        if let webViewLink, let url = URL(string: webViewLink) { return url }
        return URL(string: "https://drive.google.com/open?id=\(id)")
    }
}

struct DriveAccount: Sendable, Equatable {
    let email: String
    let displayName: String?
}

/// One file's worth of bytes plus the two mime types that matter: what we're
/// sending, and what it should become once it lands.
struct DriveUpload: Sendable {
    var name: String
    /// What the file should BE in Drive. Setting this to
    /// `application/vnd.google-apps.document` asks Drive to convert on ingest.
    var targetMimeType: String
    /// The mime type of the bytes in `data`.
    var sourceMimeType: String
    var data: Data
}

// MARK: - Client

actor GoogleDriveClient {
    static let shared = GoogleDriveClient()

    static let folderMimeType = "application/vnd.google-apps.folder"
    static let googleDocMimeType = "application/vnd.google-apps.document"

    private let auth: GoogleOAuthService
    private let session: URLSession

    init(auth: GoogleOAuthService = .shared) {
        self.auth = auth
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 600
        configuration.waitsForConnectivity = true
        self.session = URLSession(configuration: configuration)
    }

    private static let fileFields = "id,name,mimeType,webViewLink,modifiedTime"

    // MARK: - Account

    /// Doubles as the connection health check: if this succeeds, the stored
    /// grant is live and Drive-capable.
    func accountInfo() async throws -> DriveAccount {
        var components = URLComponents(
            url: GoogleDriveConfiguration.driveAPIBase.appendingPathComponent("about"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "fields", value: "user(displayName,emailAddress)")
        ]
        guard let url = components?.url else {
            throw GoogleDriveError.invalidResponse("Couldn't build the account URL")
        }

        let (data, _) = try await authorized { token in
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            return request
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let user = json["user"] as? [String: Any],
            let email = user["emailAddress"] as? String
        else {
            throw GoogleDriveError.invalidResponse("Drive didn't return an account")
        }
        return DriveAccount(email: email, displayName: user["displayName"] as? String)
    }

    // MARK: - Folders

    /// Fetch a file or folder by ID. Returns nil when it's gone or in the
    /// trash — both mean "you need a new one", and callers shouldn't have to
    /// distinguish a 404 from a tombstone.
    func file(id: String) async throws -> DriveFile? {
        var components = URLComponents(
            url: GoogleDriveConfiguration.driveAPIBase.appendingPathComponent("files/\(id)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "fields", value: "\(Self.fileFields),trashed")
        ]
        guard let url = components?.url else {
            throw GoogleDriveError.invalidResponse("Couldn't build the file URL")
        }

        do {
            let (data, _) = try await authorized { token in
                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                return request
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            if json["trashed"] as? Bool == true { return nil }
            return Self.parseFile(json)
        } catch GoogleDriveError.api(let status, _, _) where status == 404 {
            return nil
        }
    }

    /// Folders this app created, newest first. Under `drive.file` that's the
    /// complete set of folders we're allowed to know about.
    func listAppFolders() async throws -> [DriveFile] {
        var components = URLComponents(
            url: GoogleDriveConfiguration.driveAPIBase.appendingPathComponent("files"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "q", value: "mimeType='\(Self.folderMimeType)' and trashed=false"),
            URLQueryItem(name: "fields", value: "files(\(Self.fileFields))"),
            URLQueryItem(name: "orderBy", value: "createdTime desc"),
            URLQueryItem(name: "pageSize", value: "100"),
            URLQueryItem(name: "spaces", value: "drive")
        ]
        guard let url = components?.url else {
            throw GoogleDriveError.invalidResponse("Couldn't build the folder list URL")
        }

        let (data, _) = try await authorized { token in
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            return request
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let files = json["files"] as? [[String: Any]]
        else { return [] }
        return files.compactMap(Self.parseFile)
    }

    @discardableResult
    func createFolder(named name: String, parentID: String? = nil) async throws -> DriveFile {
        var metadata: [String: Any] = [
            "name": name,
            "mimeType": Self.folderMimeType
        ]
        if let parentID { metadata["parents"] = [parentID] }

        var components = URLComponents(
            url: GoogleDriveConfiguration.driveAPIBase.appendingPathComponent("files"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "fields", value: Self.fileFields)]
        guard let url = components?.url else {
            throw GoogleDriveError.invalidResponse("Couldn't build the folder URL")
        }

        let body = try JSONSerialization.data(withJSONObject: metadata)
        let (data, _) = try await authorized { token in
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            return request
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let folder = Self.parseFile(json)
        else {
            throw GoogleDriveError.invalidResponse("Drive didn't return the new folder")
        }
        return folder
    }

    /// Reuse a folder of this name if we already made one, otherwise create it.
    /// Name-matching is scoped to folders this app owns, so it can't collide
    /// with an unrelated "Cosmo Exports" the user happens to have.
    func ensureFolder(named name: String, parentID: String? = nil) async throws -> DriveFile {
        let existing = try await listAppFolders().first { $0.name == name }
        if let existing { return existing }
        return try await createFolder(named: name, parentID: parentID)
    }

    // MARK: - Upload

    /// Create a new file, or push a new revision of one that already exists.
    ///
    /// Passing `replacingFileID` keeps the Drive link stable across re-exports:
    /// the same document updates in place and Drive keeps the old version in
    /// its own revision history. If that file has since been deleted, we fall
    /// back to creating a fresh one rather than failing the export.
    func upload(
        _ upload: DriveUpload,
        toFolderID folderID: String?,
        replacingFileID: String? = nil,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> DriveFile {
        if let replacingFileID {
            if try await file(id: replacingFileID) != nil {
                return try await send(upload, folderID: nil, existingFileID: replacingFileID, onProgress: onProgress)
            }
            // The user deleted it in Drive. Create rather than resurrect.
        }
        return try await send(upload, folderID: folderID, existingFileID: nil, onProgress: onProgress)
    }

    private func send(
        _ upload: DriveUpload,
        folderID: String?,
        existingFileID: String?,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> DriveFile {
        if upload.data.count <= GoogleDriveConfiguration.multipartUploadCeiling {
            onProgress?(0)
            let file = try await sendMultipart(upload, folderID: folderID, existingFileID: existingFileID)
            onProgress?(1)
            return file
        }
        return try await sendResumable(
            upload,
            folderID: folderID,
            existingFileID: existingFileID,
            onProgress: onProgress
        )
    }

    // MARK: Multipart (small files — the common path)

    private func sendMultipart(
        _ upload: DriveUpload,
        folderID: String?,
        existingFileID: String?
    ) async throws -> DriveFile {
        let boundary = "cosmo-\(UUID().uuidString)"
        let metadata = Self.uploadMetadata(for: upload, folderID: folderID, isUpdate: existingFileID != nil)
        let body = try Self.multipartBody(metadata: metadata, upload: upload, boundary: boundary)
        let url = try uploadURL(fileID: existingFileID, uploadType: "multipart")

        let (data, _) = try await authorized { token in
            var request = URLRequest(url: url)
            request.httpMethod = existingFileID == nil ? "POST" : "PATCH"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            return request
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let file = Self.parseFile(json)
        else {
            throw GoogleDriveError.invalidResponse("Drive didn't return the uploaded file")
        }
        return file
    }

    /// `multipart/related` with a JSON metadata part followed by the media part.
    static func multipartBody(
        metadata: [String: Any],
        upload: DriveUpload,
        boundary: String
    ) throws -> Data {
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }

        let metadataJSON = try JSONSerialization.data(withJSONObject: metadata)

        append("--\(boundary)\r\n")
        append("Content-Type: application/json; charset=UTF-8\r\n\r\n")
        body.append(metadataJSON)
        append("\r\n--\(boundary)\r\n")
        append("Content-Type: \(upload.sourceMimeType)\r\n\r\n")
        body.append(upload.data)
        append("\r\n--\(boundary)--")

        return body
    }

    /// On update, `parents` is rejected in the metadata body — Drive requires
    /// `addParents`/`removeParents` query parameters for reparenting. And the
    /// target mime type is already settled by the existing file, so re-sending
    /// it risks an unnecessary conversion argument.
    static func uploadMetadata(
        for upload: DriveUpload,
        folderID: String?,
        isUpdate: Bool
    ) -> [String: Any] {
        var metadata: [String: Any] = ["name": upload.name]
        guard !isUpdate else { return metadata }
        metadata["mimeType"] = upload.targetMimeType
        if let folderID { metadata["parents"] = [folderID] }
        return metadata
    }

    private func uploadURL(fileID: String?, uploadType: String) throws -> URL {
        let path = fileID.map { "files/\($0)" } ?? "files"
        var components = URLComponents(
            url: GoogleDriveConfiguration.driveUploadBase.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "uploadType", value: uploadType),
            URLQueryItem(name: "fields", value: Self.fileFields)
        ]
        guard let url = components?.url else {
            throw GoogleDriveError.invalidResponse("Couldn't build the upload URL")
        }
        return url
    }

    // MARK: Resumable (large files)

    private func sendResumable(
        _ upload: DriveUpload,
        folderID: String?,
        existingFileID: String?,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> DriveFile {
        let metadata = Self.uploadMetadata(for: upload, folderID: folderID, isUpdate: existingFileID != nil)
        let initiationURL = try uploadURL(fileID: existingFileID, uploadType: "resumable")
        let metadataBody = try JSONSerialization.data(withJSONObject: metadata)
        let total = upload.data.count

        let (_, initiationResponse) = try await authorized { token in
            var request = URLRequest(url: initiationURL)
            request.httpMethod = existingFileID == nil ? "POST" : "PATCH"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            request.setValue(upload.sourceMimeType, forHTTPHeaderField: "X-Upload-Content-Type")
            request.setValue(String(total), forHTTPHeaderField: "X-Upload-Content-Length")
            request.httpBody = metadataBody
            return request
        }

        guard
            let location = initiationResponse.value(forHTTPHeaderField: "Location"),
            let sessionURL = URL(string: location)
        else {
            throw GoogleDriveError.uploadFailed("Drive didn't open an upload session")
        }

        // The session URI carries its own authorization; chunks are plain PUTs.
        var offset = 0
        while offset < total {
            let length = min(GoogleDriveConfiguration.resumableChunkSize, total - offset)
            let chunk = upload.data.subdata(in: offset..<(offset + length))
            let end = offset + length - 1

            var request = URLRequest(url: sessionURL)
            request.httpMethod = "PUT"
            request.setValue("bytes \(offset)-\(end)/\(total)", forHTTPHeaderField: "Content-Range")
            request.setValue(upload.sourceMimeType, forHTTPHeaderField: "Content-Type")
            request.httpBody = chunk

            let (data, response) = try await withNetworkRetry(label: "GoogleDriveUpload") {
                try await self.session.data(for: request)
            }

            // 308 Resume Incomplete is Drive saying "chunk received, keep going".
            if response.statusCode == 308 {
                offset += length
                onProgress?(Double(offset) / Double(total))
                continue
            }
            if response.statusCode == 200 || response.statusCode == 201 {
                onProgress?(1)
                guard
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let file = Self.parseFile(json)
                else {
                    throw GoogleDriveError.invalidResponse("Drive didn't return the uploaded file")
                }
                return file
            }
            throw Self.mapError(status: response.statusCode, data: data)
        }

        throw GoogleDriveError.uploadFailed("Upload ended without a response from Drive")
    }

    // MARK: - Authorized Transport

    /// Build-send-retry. The builder closure is called again on retry so the
    /// refreshed token actually reaches the wire — rebuilding the request is
    /// the whole point, since `Authorization` is baked in at build time.
    private func authorized(
        _ build: @Sendable (String) throws -> URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        let token = try await auth.validAccessToken()
        let (data, response) = try await withNetworkRetry(label: "GoogleDrive") {
            try await self.session.data(for: try build(token))
        }

        if response.statusCode == 401 {
            // See 401 LADDER in the file header: one refresh, one retry.
            let refreshed = try await auth.forceRefresh().accessToken
            let (retryData, retryResponse) = try await withNetworkRetry(label: "GoogleDrive") {
                try await self.session.data(for: try build(refreshed))
            }
            if retryResponse.statusCode == 401 {
                throw GoogleDriveError.reconnectRequired("Google rejected the refreshed credentials")
            }
            guard retryResponse.statusCode < 400 else {
                throw Self.mapError(status: retryResponse.statusCode, data: retryData)
            }
            return (retryData, retryResponse)
        }

        guard response.statusCode < 400 else {
            throw Self.mapError(status: response.statusCode, data: data)
        }
        return (data, response)
    }

    // MARK: - Parsing

    static func parseFile(_ json: [String: Any]) -> DriveFile? {
        guard let id = json["id"] as? String else { return nil }
        return DriveFile(
            id: id,
            name: json["name"] as? String ?? "Untitled",
            mimeType: json["mimeType"] as? String ?? "application/octet-stream",
            webViewLink: json["webViewLink"] as? String,
            modifiedTime: (json["modifiedTime"] as? String).flatMap(ISO8601DateFormatter().date(from:))
        )
    }

    /// Drive wraps failures in `{ "error": { code, message, errors: [{reason}] } }`.
    /// The `reason` is the part worth branching on — the message is prose.
    static func mapError(status: Int, data: Data) -> GoogleDriveError {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let envelope = json?["error"] as? [String: Any]
        let message = envelope?["message"] as? String
            ?? String(data: data, encoding: .utf8)?.prefix(200).description
            ?? "Unknown error"
        let reason = (envelope?["errors"] as? [[String: Any]])?.first?["reason"] as? String

        switch reason {
        case "storageQuotaExceeded":
            return .driveStorageFull
        case "insufficientFilePermissions", "appNotAuthorizedToFile":
            return .api(status: status, reason: reason, message:
                "Cosmo can only touch files it created — this one wasn't made by Cosmo.")
        default:
            if status == 403 || status == 401 {
                return .api(status: status, reason: reason, message: message)
            }
            return .api(status: status, reason: reason, message: message)
        }
    }
}
