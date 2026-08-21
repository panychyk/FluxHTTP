import Foundation

public final class RetryDecorator: HTTPClientDecorator {

    public let wrapped: any HTTPClient
    private let policy: RetryPolicy

    public init(
        wrapping: any HTTPClient,
        policy: RetryPolicy = RetryPolicy()
    ) {
        self.wrapped = wrapping
        self.policy = policy
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        let method = (request.httpMethod ?? "GET").uppercased()
        guard policy.retryableMethods.contains(method), request.httpBodyStream == nil else {
            return try await wrapped.send(request)
        }

        for retryIndex in 0..<policy.maxRetries {
            try Task.checkCancellation()
            let nextAttempt = retryIndex + 1

            do {
                let response = try await wrapped.send(request)

                guard policy.retryableStatusCodes.contains(response.statusCode) else {
                    return response
                }

                guard let delay = retryDelay(
                    beforeAttempt: nextAttempt,
                    policy: policy,
                    retryAfter: response.value(forHTTPHeaderField: "Retry-After"),
                    now: Date(),
                    jitterFactor: Double.random(in: 0...1)
                ) else {
                    return response
                }

                try await sleep(for: delay)
            } catch let error where isRetryable(error) {
                let delay = retryDelay(
                    beforeAttempt: nextAttempt,
                    policy: policy,
                    retryAfter: nil,
                    now: Date(),
                    jitterFactor: Double.random(in: 0...1)
                )
                if let delay {
                    try await sleep(for: delay)
                }
            }
        }

        try Task.checkCancellation()
        return try await wrapped.send(request)
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

    private func sleep(for delay: TimeInterval) async throws {
        let maximumNanoseconds = TimeInterval(UInt64.max / 2)
        let nanoseconds = min(delay * 1_000_000_000, maximumNanoseconds)
        try await Task.sleep(nanoseconds: UInt64(nanoseconds.rounded(.up)))
    }
}
