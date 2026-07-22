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
        guard policy.retryableMethods.contains(method), request.httpBodyStream == nil else {
            return try await wrapped.send(request)
        }

        var attempt = 0

        while true {
            try Task.checkCancellation()
            do {
                let response = try await wrapped.send(request)

                if policy.retryableStatusCodes.contains(response.statusCode),
                   attempt < policy.maxRetries {
                    let nextAttempt = attempt + 1
                    guard let delay = retryDelay(
                        beforeAttempt: nextAttempt,
                        policy: policy,
                        retryAfter: response.value(forHTTPHeaderField: "Retry-After"),
                        now: Date(),
                        jitterFactor: Double.random(in: 0...1)
                    ) else {
                        return response
                    }

                    attempt = nextAttempt
                    try await sleep(for: delay)
                    continue
                }

                return response

            } catch let error where attempt < policy.maxRetries && isRetryable(error) {
                attempt += 1
                let delay = retryDelay(
                    beforeAttempt: attempt,
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
