import Foundation
import Testing
@testable import FluxHTTP

/// Appends its label to a shared log when the request passes through.
private final class RecordingDecorator: HTTPClientDecorator, @unchecked Sendable {

    final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String] = []
        func append(_ entry: String) { lock.withLock { entries.append(entry) } }
        var all: [String] { lock.withLock { entries } }
    }

    private let label: String
    private let log: Log

    init(wrapping: any HTTPClient, label: String, log: Log) {
        self.label = label
        self.log = log
        super.init(wrapping: wrapping)
    }

    override func send(_ request: URLRequest) async throws -> HTTPResponse {
        log.append(label)
        return try await wrapped.send(request)
    }
}

@Suite struct HTTPClientBuilderTests {

    @Test func lastAddedDecoratorIsOutermost() async throws {
        let log = RecordingDecorator.Log()
        let mock = MockHTTPClient(response: HTTPResponse(statusCode: 200))

        let client = HTTPClientBuilder(base: mock)
            .add { RecordingDecorator(wrapping: $0, label: "inner", log: log) }
            .add { RecordingDecorator(wrapping: $0, label: "outer", log: log) }
            .build()

        _ = try await client.send(URLRequest(url: URL(string: "https://example.com")!))

        #expect(log.all == ["outer", "inner"])
        #expect(mock.requestCount == 1)
    }

    @Test func buildWithoutDecoratorsReturnsBase() async throws {
        let mock = MockHTTPClient(response: HTTPResponse(statusCode: 204))
        let client = HTTPClientBuilder(base: mock).build()

        let response = try await client.send(URLRequest(url: URL(string: "https://example.com")!))

        #expect(response.statusCode == 204)
    }

    @Test func buildWithoutDecoratorsDoesNotRetry() async throws {
        let mock = MockHTTPClient(response: HTTPResponse(statusCode: 503))
        let client = HTTPClientBuilder(base: mock).build()

        let response = try await client.send(URLRequest(url: URL(string: "https://example.com")!))

        #expect(response.statusCode == 503)
        #expect(mock.requestCount == 1)
    }

    @Test func baseURLWrapsFinishedRetryPipeline() async throws {
        let baseURL = URL(string: "https://api.example.com/v1")!
        let mock = MockHTTPClient(results: [
            .success(HTTPResponse(statusCode: 503)),
            .success(HTTPResponse(statusCode: 200))
        ])
        let policy = RetryPolicy(
            maxRetries: 1,
            delay: 0,
            maximumDelay: 0,
            usesExponentialBackoff: false,
            usesJitter: false
        )

        let client: any HTTPClient = HTTPClientBuilder(base: mock)
            .add { RetryDecorator(wrapping: $0, policy: policy) }
            .build(baseURL: baseURL)

        let response = try await client.send(.get("health"))

        #expect(response.statusCode == 200)
        #expect(mock.requests.map(\.url?.absoluteString) == [
            "https://api.example.com/v1/health",
            "https://api.example.com/v1/health"
        ])
    }
}
