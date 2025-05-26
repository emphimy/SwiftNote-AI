import Foundation

// MARK: - Network Recovery Manager

/// Manages network failure recovery and retry logic for sync operations
class NetworkRecoveryManager {

    /// Configuration for retry behavior
    struct RetryConfiguration {
        let maxRetries: Int
        let baseDelay: TimeInterval
        let maxDelay: TimeInterval
        let backoffMultiplier: Double

        static let `default` = RetryConfiguration(
            maxRetries: 3,
            baseDelay: 1.0,
            maxDelay: 30.0,
            backoffMultiplier: 2.0
        )

        static let aggressive = RetryConfiguration(
            maxRetries: 5,
            baseDelay: 0.5,
            maxDelay: 60.0,
            backoffMultiplier: 2.5
        )
    }

    /// Types of errors that can be recovered from
    enum RecoverableError {
        case networkTimeout
        case networkUnavailable
        case serverError(code: Int)
        case rateLimited
        case temporaryFailure

        var shouldRetry: Bool {
            switch self {
            case .networkTimeout, .networkUnavailable, .temporaryFailure:
                return true
            case .serverError(let code):
                return code >= 500 && code < 600 // Server errors
            case .rateLimited:
                return true
            }
        }

        var retryConfiguration: RetryConfiguration {
            switch self {
            case .networkTimeout, .networkUnavailable:
                return .aggressive
            case .serverError, .temporaryFailure:
                return .default
            case .rateLimited:
                return RetryConfiguration(
                    maxRetries: 2,
                    baseDelay: 5.0,
                    maxDelay: 120.0,
                    backoffMultiplier: 3.0
                )
            }
        }
    }

    /// Classify an error to determine if it's recoverable
    /// - Parameter error: The error to classify
    /// - Returns: RecoverableError if the error can be retried, nil otherwise
    func classifyError(_ error: Error) -> RecoverableError? {
        // Handle NSError cases
        if let nsError = error as NSError? {
            switch nsError.domain {
            case NSURLErrorDomain:
                return classifyURLError(nsError)
            case "SupabaseService":
                return classifySupabaseError(nsError)
            default:
                break
            }
        }

        // Handle Supabase-specific errors
        let errorDescription = error.localizedDescription.lowercased()
        if errorDescription.contains("network") || errorDescription.contains("connection") {
            return .networkUnavailable
        }
        if errorDescription.contains("timeout") {
            return .networkTimeout
        }
        if errorDescription.contains("rate limit") || errorDescription.contains("too many requests") {
            return .rateLimited
        }
        if errorDescription.contains("server error") || errorDescription.contains("internal error") {
            return .serverError(code: 500)
        }

        return nil
    }

    /// Classify URL errors
    /// - Parameter error: NSError with NSURLErrorDomain
    /// - Returns: RecoverableError if applicable
    private func classifyURLError(_ error: NSError) -> RecoverableError? {
        switch error.code {
        case NSURLErrorTimedOut:
            return .networkTimeout
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            return .networkUnavailable
        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
            return .networkUnavailable
        case NSURLErrorDNSLookupFailed:
            return .networkUnavailable
        case NSURLErrorHTTPTooManyRedirects:
            return .temporaryFailure
        case NSURLErrorResourceUnavailable:
            return .temporaryFailure
        default:
            return nil
        }
    }

    /// Classify Supabase service errors
    /// - Parameter error: NSError with SupabaseService domain
    /// - Returns: RecoverableError if applicable
    private func classifySupabaseError(_ error: NSError) -> RecoverableError? {
        switch error.code {
        case 429: // Too Many Requests
            return .rateLimited
        case 500...599: // Server errors
            return .serverError(code: error.code)
        case 408: // Request Timeout
            return .networkTimeout
        case 503: // Service Unavailable
            return .temporaryFailure
        default:
            return nil
        }
    }

    /// Execute an operation with retry logic
    /// - Parameters:
    ///   - operation: The async operation to execute
    ///   - operationName: Name for logging purposes
    /// - Returns: Result of the operation
    func executeWithRetry<T>(
        operation: @escaping () async throws -> T,
        operationName: String
    ) async throws -> T {
        var lastError: Error?
        var attempt = 0

        while attempt <= RetryConfiguration.default.maxRetries {
            do {
                let result = try await operation()

                if attempt > 0 {
                    #if DEBUG
                    print("🔄 NetworkRecoveryManager: \(operationName) succeeded on attempt \(attempt + 1)")
                    #endif
                }

                return result
            } catch {
                lastError = error
                attempt += 1

                #if DEBUG
                print("🔄 NetworkRecoveryManager: \(operationName) failed on attempt \(attempt): \(error.localizedDescription)")
                #endif

                // Check if this error is recoverable
                guard let recoverableError = classifyError(error),
                      recoverableError.shouldRetry,
                      attempt <= recoverableError.retryConfiguration.maxRetries else {
                    #if DEBUG
                    print("🔄 NetworkRecoveryManager: \(operationName) failed permanently: \(error.localizedDescription)")
                    #endif
                    throw error
                }

                // Calculate delay with exponential backoff
                let config = recoverableError.retryConfiguration
                let delay = min(
                    config.baseDelay * pow(config.backoffMultiplier, Double(attempt - 1)),
                    config.maxDelay
                )

                #if DEBUG
                print("🔄 NetworkRecoveryManager: Retrying \(operationName) in \(String(format: "%.1f", delay))s (attempt \(attempt + 1)/\(config.maxRetries + 1))")
                #endif

                // Wait before retrying
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        // If we get here, all retries failed
        throw lastError ?? NSError(domain: "NetworkRecoveryManager", code: 500, userInfo: [
            NSLocalizedDescriptionKey: "All retry attempts failed for \(operationName)"
        ])
    }
}
