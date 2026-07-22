import Foundation
import Testing
@testable import FluxHTTP

private func policy(
    delay: TimeInterval = 2,
    maximumDelay: TimeInterval = 10,
    usesExponentialBackoff: Bool = false,
    usesJitter: Bool = false
) -> RetryPolicy {
    RetryPolicy(
        delay: delay,
        maximumDelay: maximumDelay,
        usesExponentialBackoff: usesExponentialBackoff,
        usesJitter: usesJitter
    )
}

private let httpDate = Date(timeIntervalSince1970: 784_111_767)

@Suite struct RetryPolicyTests {

    @Test func usesSafeDefaults() {
        let policy = RetryPolicy()

        #expect(policy.retryableStatusCodes == [408, 429, 500, 502, 503, 504])
        #expect(policy.retryableMethods == ["GET", "HEAD", "PUT", "DELETE", "OPTIONS", "TRACE"])
        #expect(policy.maximumDelay == 30)
    }

    @Test func honorsDeltaSeconds() {
        let delay = retryDelay(
            beforeAttempt: 1,
            policy: policy(),
            retryAfter: "5",
            now: httpDate,
            jitterFactor: 0
        )

        #expect(delay == 5)
    }

    @Test func honorsFutureHTTPDate() {
        let delay = retryDelay(
            beforeAttempt: 1,
            policy: policy(),
            retryAfter: "Sun, 06 Nov 1994 08:49:37 GMT",
            now: httpDate,
            jitterFactor: 0
        )

        #expect(delay == 10)
    }

    @Test func treatsPastHTTPDateAsImmediatelyEligible() {
        let delay = retryDelay(
            beforeAttempt: 1,
            policy: policy(),
            retryAfter: "Sun, 06 Nov 1994 08:49:17 GMT",
            now: httpDate,
            jitterFactor: 0
        )

        #expect(delay == 2)
    }

    @Test func ignoresMalformedRetryAfter() {
        let delay = retryDelay(
            beforeAttempt: 1,
            policy: policy(),
            retryAfter: "not-a-delay",
            now: httpDate,
            jitterFactor: 0
        )

        #expect(delay == 2)
    }

    @Test func refusesRetryAfterBeyondMaximumDelay() {
        let delay = retryDelay(
            beforeAttempt: 1,
            policy: policy(),
            retryAfter: "11",
            now: httpDate,
            jitterFactor: 0
        )

        #expect(delay == nil)
    }

    @Test func capsExponentialBackoffAndJitter() {
        let delay = retryDelay(
            beforeAttempt: 3,
            policy: policy(
                delay: 2,
                maximumDelay: 5,
                usesExponentialBackoff: true,
                usesJitter: true
            ),
            retryAfter: nil,
            now: httpDate,
            jitterFactor: 1
        )

        #expect(delay == 5)
    }

    // Swift Testing subprocess expectations are unavailable on iOS.
    #if os(macOS)
    @Test func rejectsInvalidConfiguration() async {
        await #expect(processExitsWith: .failure) {
            _ = RetryPolicy(maxRetries: -1)
        }
        await #expect(processExitsWith: .failure) {
            _ = RetryPolicy(delay: -1)
        }
        await #expect(processExitsWith: .failure) {
            _ = RetryPolicy(delay: .infinity)
        }
        await #expect(processExitsWith: .failure) {
            _ = RetryPolicy(maximumDelay: -1)
        }
        await #expect(processExitsWith: .failure) {
            _ = RetryPolicy(maximumDelay: .infinity)
        }
        await #expect(processExitsWith: .failure) {
            _ = RetryPolicy(delay: 2, maximumDelay: 1)
        }
    }
    #endif
}
