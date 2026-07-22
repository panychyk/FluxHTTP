import Foundation

public struct RetryPolicy: Sendable {

    public let maxRetries: Int
    public let delay: TimeInterval
    /// Caps exponential backoff and jitter, and bounds server-requested delays.
    public let maximumDelay: TimeInterval
    public let usesExponentialBackoff: Bool
    public let usesJitter: Bool
    public let retryableStatusCodes: Set<Int>
    public let retryableURLErrorCodes: Set<URLError.Code>
    /// Only idempotent methods are retried by default; POST/PATCH must be opted in.
    public let retryableMethods: Set<String>

    /// Creates a retry policy.
    ///
    /// - Precondition: `maxRetries`, `delay`, and `maximumDelay` are
    ///   non-negative; both delays are finite; and `maximumDelay >= delay`.
    public init(
        maxRetries: Int = 2,
        delay: TimeInterval = 0.3,
        maximumDelay: TimeInterval = 30,
        usesExponentialBackoff: Bool = true,
        usesJitter: Bool = true,
        retryableStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504],
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
        precondition(maxRetries >= 0, "maxRetries must be non-negative")
        precondition(delay.isFinite && delay >= 0, "delay must be non-negative and finite")
        precondition(
            maximumDelay.isFinite && maximumDelay >= 0,
            "maximumDelay must be non-negative and finite"
        )
        precondition(maximumDelay >= delay, "maximumDelay must be greater than or equal to delay")

        self.maxRetries = maxRetries
        self.delay = delay
        self.maximumDelay = maximumDelay
        self.usesExponentialBackoff = usesExponentialBackoff
        self.usesJitter = usesJitter
        self.retryableStatusCodes = retryableStatusCodes
        self.retryableURLErrorCodes = retryableURLErrorCodes
        self.retryableMethods = Set(retryableMethods.map { $0.uppercased() })
    }
}

/// Returns `nil` when a valid `Retry-After` asks for a delay beyond the policy limit.
func retryDelay(
    beforeAttempt attempt: Int,
    policy: RetryPolicy,
    retryAfter: String?,
    now: Date,
    jitterFactor: Double
) -> TimeInterval? {
    precondition(attempt > 0)
    precondition((0...1).contains(jitterFactor))

    var delay = policy.delay
    if policy.usesExponentialBackoff && delay > 0 {
        let exponentialDelay = delay * pow(2, Double(attempt - 1))
        delay = exponentialDelay.isFinite ? exponentialDelay : policy.maximumDelay
    }
    delay = min(delay, policy.maximumDelay)

    if policy.usesJitter {
        delay += delay * 0.1 * jitterFactor
        delay = min(delay, policy.maximumDelay)
    }

    guard let retryAfter,
          let serverDelay = retryAfterDelay(retryAfter, relativeTo: now) else {
        return delay
    }
    guard serverDelay <= policy.maximumDelay else {
        return nil
    }
    return max(delay, serverDelay)
}

private func retryAfterDelay(_ value: String, relativeTo now: Date) -> TimeInterval? {
    let value = value.trimmingCharacters(in: .whitespacesAndNewlines)

    if !value.isEmpty,
       value.utf8.allSatisfy({ (48...57).contains($0) }) {
        // A syntactically valid but unrepresentable delta is necessarily over
        // every finite policy maximum and therefore suppresses the retry.
        return TimeInterval(value) ?? .infinity
    }

    for format in [
        "EEE',' dd MMM yyyy HH':'mm':'ss zzz",
        "EEEE',' dd-MMM-yy HH':'mm':'ss zzz",
        "EEE MMM d HH':'mm':'ss yyyy"
    ] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        formatter.isLenient = false

        if let date = formatter.date(from: value) {
            return max(0, date.timeIntervalSince(now))
        }
    }

    return nil
}
