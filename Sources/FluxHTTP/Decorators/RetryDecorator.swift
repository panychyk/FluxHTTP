import Foundation

public final class RetryDecorator: HTTPClientDecorator, @unchecked Sendable {

    private let policy: RetryPolicy

    public init(
        wrapping: any HTTPClient,
        policy: RetryPolicy = RetryPolicy()
    ) {
        self.policy = policy
        super.init(wrapping: wrapping)
    }

    public override func send(_ request: URLRequest) async throws -> HTTPResponse {
        let method = (request.httpMethod ?? "GET").uppercased()
        guard policy.retryableMethods.contains(method) else {
            return try await wrapped.send(request)
        }

        var attempt = 0

        while true {
            try Task.checkCancellation()
            do {
                let response = try await wrapped.send(request)

                if policy.retryableStatusCodes.contains(response.statusCode),
                   attempt < policy.maxRetries {

                    attempt += 1
                    try await sleep(
                        beforeAttempt: attempt,
                        retryAfter: response.value(forHTTPHeaderField: "Retry-After")
                    )
                    continue
                }

                return response

            } catch let error where attempt < policy.maxRetries && isRetryable(error) {
                attempt += 1
                try await sleep(beforeAttempt: attempt, retryAfter: nil)
            }
        }
    }

    private func isRetryable(_ error: Error) -> Bool {
        if error is CancellationError {
            return false
        }
        if case .transport(let urlError) = error as? HTTPError {
            return policy.retryableURLErrorCodes.contains(urlError.code)
        }
        if let urlError = error as? URLError {
            return policy.retryableURLErrorCodes.contains(urlError.code)
        }
        return false
    }

    private func sleep(beforeAttempt attempt: Int, retryAfter: String?) async throws {
        var delay = policy.delay
        if policy.usesExponentialBackoff {
            delay = policy.delay * pow(2, Double(attempt - 1))
        }
        // Only the delta-seconds form of Retry-After is honored; HTTP-date is ignored.
        if let retryAfter, let seconds = TimeInterval(retryAfter), seconds >= 0 {
            delay = max(delay, seconds)
        }
        if policy.usesJitter {
            delay += Double.random(in: 0...(delay * 0.1))
        }
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
}

public struct RetryPolicy: Sendable {

    public let maxRetries: Int
    public let delay: TimeInterval
    public let usesExponentialBackoff: Bool
    public let usesJitter: Bool
    public let retryableStatusCodes: Set<Int>
    public let retryableURLErrorCodes: Set<URLError.Code>
    /// Only idempotent methods are retried by default; POST/PATCH must be opted in.
    public let retryableMethods: Set<String>

    public init(
        maxRetries: Int = 2,
        delay: TimeInterval = 0.3,
        usesExponentialBackoff: Bool = true,
        usesJitter: Bool = true,
        retryableStatusCodes: Set<Int> = Set(500...599).union([408, 429]),
        retryableURLErrorCodes: Set<URLError.Code> = [
            .timedOut,
            .networkConnectionLost,
            .notConnectedToInternet,
            .dnsLookupFailed,
            .cannotFindHost,
            .cannotConnectToHost
        ],
        retryableMethods: Set<String> = ["GET", "HEAD", "PUT", "DELETE", "OPTIONS", "TRACE"]
    ) {
        self.maxRetries = maxRetries
        self.delay = delay
        self.usesExponentialBackoff = usesExponentialBackoff
        self.usesJitter = usesJitter
        self.retryableStatusCodes = retryableStatusCodes
        self.retryableURLErrorCodes = retryableURLErrorCodes
        self.retryableMethods = Set(retryableMethods.map { $0.uppercased() })
    }
}
