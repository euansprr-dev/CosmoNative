// CosmoOS/Services/NetworkRetry.swift
// Shared retry helper for transient network failures (429, 5xx)

import Foundation

enum NetworkRetryError: LocalizedError {
    case maxRetriesExhausted(lastError: Error)
    case nonRetryableHTTPError(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .maxRetriesExhausted(let lastError):
            return "Max retries exhausted. Last error: \(lastError.localizedDescription)"
        case .nonRetryableHTTPError(let code, let body):
            return "HTTP \(code): \(body)"
        }
    }
}

/// Execute a network request with exponential backoff retry on 429 and 5xx errors.
///
/// - Parameters:
///   - maxAttempts: Maximum number of attempts (default: 3)
///   - baseBackoff: Base backoff interval in seconds (default: 2.0)
///   - label: Label for log messages (default: "NetworkRetry")
///   - operation: Closure that performs the request and returns (Data, URLResponse)
/// - Returns: (Data, HTTPURLResponse) on success
/// - Throws: `NetworkRetryError` if all retries exhausted or a non-retryable error occurs
func withNetworkRetry(
    maxAttempts: Int = 3,
    baseBackoff: Double = 2.0,
    label: String = "NetworkRetry",
    operation: () async throws -> (Data, URLResponse)
) async throws -> (Data, HTTPURLResponse) {
    var lastError: Error?

    for attempt in 0..<maxAttempts {
        if attempt > 0 {
            let backoff = baseBackoff * Double(attempt)
            print("[\(label)] Retry \(attempt)/\(maxAttempts - 1) after \(Int(backoff))s backoff")
            try await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
        }

        do {
            let (data, response) = try await operation()

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkRetryError.nonRetryableHTTPError(statusCode: 0, body: "Non-HTTP response")
            }

            let status = httpResponse.statusCode

            // Retryable: 429 rate limit, 5xx server errors
            if status == 429 || (status >= 500 && status < 600) {
                let body = String(data: data, encoding: .utf8) ?? ""
                print("[\(label)] Retryable HTTP \(status): \(body.prefix(200))")
                lastError = NetworkRetryError.nonRetryableHTTPError(statusCode: status, body: String(body.prefix(200)))
                continue
            }

            return (data, httpResponse)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as NetworkRetryError {
            throw error
        } catch {
            // Network-level errors (timeout, DNS, connection reset) are retryable
            print("[\(label)] Network error on attempt \(attempt): \(error.localizedDescription)")
            lastError = error
            continue
        }
    }

    throw NetworkRetryError.maxRetriesExhausted(lastError: lastError ?? CancellationError())
}
