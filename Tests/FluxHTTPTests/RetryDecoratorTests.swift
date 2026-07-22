import Foundation
import Testing
@testable import FluxHTTP

private func fastPolicy(
    maxRetries: Int = 2,
    retryableMethods: Set<String> = ["GET", "HEAD", "PUT", "DELETE", "OPTIONS", "TRACE"]
) -> RetryPolicy {
    RetryPolicy(
        maxRetries: maxRetries,
        delay: 0,
        usesExponentialBackoff: false,
        usesJitter: false,
        retryableMethods: retryableMethods
    )
}

private func getRequest(_ url: String = "https://example.com/a") -> URLRequest {
    URLRequest(url: URL(string: url)!)
}

@Suite struct RetryDecoratorTests {

    @Test func retriesTransientTransportErrorAndSucceeds() async throws {
        let mock = MockHTTPClient(results: [
            .failure(HTTPError.transport(URLError(.timedOut))),
            .success(HTTPResponse(statusCode: 200))
        ])
        let client = RetryDecorator(wrapping: mock, policy: fastPolicy())

        let response = try await client.send(getRequest())

        #expect(response.statusCode == 200)
        #expect(mock.requestCount == 2)
    }

    @Test func exhaustsRetriesAndThrowsLastError() async throws {
        let mock = MockHTTPClient(results: [
            .failure(HTTPError.transport(URLError(.networkConnectionLost)))
        ])
        let client = RetryDecorator(wrapping: mock, policy: fastPolicy(maxRetries: 2))

        await #expect(throws: HTTPError.self) {
            try await client.send(getRequest())
        }
        // 1 initial attempt + 2 retries
        #expect(mock.requestCount == 3)
    }

    @Test func doesNotRetryNonRetryableTransportError() async throws {
        let mock = MockHTTPClient(results: [
            .failure(HTTPError.transport(URLError(.badURL)))
        ])
        let client = RetryDecorator(wrapping: mock, policy: fastPolicy())

        await #expect(throws: HTTPError.self) {
            try await client.send(getRequest())
        }
        #expect(mock.requestCount == 1)
    }

    @Test func doesNotRetryCancellation() async throws {
        let mock = MockHTTPClient(results: [
            .failure(CancellationError())
        ])
        let client = RetryDecorator(wrapping: mock, policy: fastPolicy())

        await #expect(throws: CancellationError.self) {
            try await client.send(getRequest())
        }
        #expect(mock.requestCount == 1)
    }

    @Test func retriesRetryableStatusCode() async throws {
        let mock = MockHTTPClient(results: [
            .success(HTTPResponse(statusCode: 503)),
            .success(HTTPResponse(statusCode: 200))
        ])
        let client = RetryDecorator(wrapping: mock, policy: fastPolicy())

        let response = try await client.send(getRequest())

        #expect(response.statusCode == 200)
        #expect(mock.requestCount == 2)
    }

    @Test func returnsFailingStatusAfterRetriesExhausted() async throws {
        let mock = MockHTTPClient(results: [
            .success(HTTPResponse(statusCode: 500))
        ])
        let client = RetryDecorator(wrapping: mock, policy: fastPolicy(maxRetries: 1))

        let response = try await client.send(getRequest())

        #expect(response.statusCode == 500)
        #expect(mock.requestCount == 2)
    }

    @Test func doesNotRetryNonIdempotentMethod() async throws {
        let mock = MockHTTPClient(results: [
            .success(HTTPResponse(statusCode: 500))
        ])
        let client = RetryDecorator(wrapping: mock, policy: fastPolicy())

        var request = getRequest()
        request.httpMethod = "POST"
        let response = try await client.send(request)

        #expect(response.statusCode == 500)
        #expect(mock.requestCount == 1)
    }

    @Test func doesNotRetryRequestWithBodyStream() async throws {
        let mock = MockHTTPClient(results: [
            .success(HTTPResponse(statusCode: 500))
        ])
        let client = RetryDecorator(wrapping: mock, policy: fastPolicy())

        var request = getRequest()
        request.httpBodyStream = InputStream(data: Data("body".utf8))
        let response = try await client.send(request)

        #expect(response.statusCode == 500)
        #expect(mock.requestCount == 1)
    }

    @Test func doesNotRetryUnknownErrorType() async throws {
        struct CustomError: Error {}
        let mock = MockHTTPClient(results: [
            .failure(CustomError())
        ])
        let client = RetryDecorator(wrapping: mock, policy: fastPolicy())

        await #expect(throws: CustomError.self) {
            try await client.send(getRequest())
        }
        #expect(mock.requestCount == 1)
    }

    @Test func defaultPolicyPassesSuccessThrough() async throws {
        let mock = MockHTTPClient(response: HTTPResponse(statusCode: 200))
        let client = RetryDecorator(wrapping: mock)

        let response = try await client.send(getRequest())

        #expect(response.statusCode == 200)
        #expect(mock.requestCount == 1)
    }

    @Test func retriesRawURLErrorWithoutWrapper() async throws {
        let mock = MockHTTPClient(results: [
            .failure(URLError(.timedOut)),
            .success(HTTPResponse(statusCode: 200))
        ])
        let client = RetryDecorator(wrapping: mock, policy: fastPolicy())

        let response = try await client.send(getRequest())

        #expect(response.statusCode == 200)
        #expect(mock.requestCount == 2)
    }

    @Test func honorsRetryAfterWithBackoffAndJitter() async throws {
        let mock = MockHTTPClient(results: [
            .success(HTTPResponse(statusCode: 503, headers: ["Retry-After": "0"])),
            .success(HTTPResponse(statusCode: 200))
        ])
        let policy = RetryPolicy(
            maxRetries: 2,
            delay: 0.001,
            usesExponentialBackoff: true,
            usesJitter: true
        )
        let client = RetryDecorator(wrapping: mock, policy: policy)

        let response = try await client.send(getRequest())

        #expect(response.statusCode == 200)
        #expect(mock.requestCount == 2)
    }

    @Test func returnsResponseWhenRetryAfterExceedsMaximumDelay() async throws {
        let response = HTTPResponse(statusCode: 503, headers: ["Retry-After": "1"])
        let mock = MockHTTPClient(results: [.success(response)])
        let policy = RetryPolicy(
            maxRetries: 2,
            delay: 0,
            maximumDelay: 0,
            usesExponentialBackoff: false,
            usesJitter: false
        )
        let client = RetryDecorator(wrapping: mock, policy: policy)

        let result = try await client.send(getRequest())

        #expect(result.statusCode == 503)
        #expect(mock.requestCount == 1)
    }

    @Test func ignoresMalformedRetryAfterAndRetries() async throws {
        let mock = MockHTTPClient(results: [
            .success(HTTPResponse(statusCode: 503, headers: ["Retry-After": "later"])),
            .success(HTTPResponse(statusCode: 200))
        ])
        let client = RetryDecorator(wrapping: mock, policy: fastPolicy())

        let response = try await client.send(getRequest())

        #expect(response.statusCode == 200)
        #expect(mock.requestCount == 2)
    }

    @Test func propagatesCancellationFromRetryLoop() async throws {
        let mock = MockHTTPClient(results: [
            .success(HTTPResponse(statusCode: 503))
        ])
        let policy = RetryPolicy(
            maxRetries: 10,
            delay: 0.05,
            usesExponentialBackoff: false,
            usesJitter: false
        )
        let client = RetryDecorator(wrapping: mock, policy: policy)

        let task = Task {
            try await client.send(getRequest())
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test func doesNotRetryClientErrorStatus() async throws {
        let mock = MockHTTPClient(results: [
            .success(HTTPResponse(statusCode: 404))
        ])
        let client = RetryDecorator(wrapping: mock, policy: fastPolicy())

        let response = try await client.send(getRequest())

        #expect(response.statusCode == 404)
        #expect(mock.requestCount == 1)
    }

    @Test func doesNotRetryUnlistedServerErrorByDefault() async throws {
        let mock = MockHTTPClient(results: [
            .success(HTTPResponse(statusCode: 501))
        ])
        let client = RetryDecorator(wrapping: mock, policy: fastPolicy())

        let response = try await client.send(getRequest())

        #expect(response.statusCode == 501)
        #expect(mock.requestCount == 1)
    }
}
