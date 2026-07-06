import Foundation
import Testing
@testable import FluxHTTP

@Suite struct LoggingDecoratorTests {

    @Test func passesResponseThroughOnSuccess() async throws {
        let mock = MockHTTPClient(response: HTTPResponse(statusCode: 200, data: Data("ok".utf8)))
        let client = LoggingDecorator(wrapping: mock)

        var request = URLRequest(url: URL(string: "https://example.com/log")!)
        request.httpMethod = "PUT"
        let response = try await client.send(request)

        #expect(response.statusCode == 200)
        #expect(response.data == Data("ok".utf8))
        #expect(mock.requests[0].httpMethod == "PUT")
    }

    @Test func rethrowsErrorOnFailure() async throws {
        let mock = MockHTTPClient(results: [
            .failure(HTTPError.transport(URLError(.timedOut)))
        ])
        let client = LoggingDecorator(wrapping: mock)

        await #expect(throws: HTTPError.self) {
            try await client.send(URLRequest(url: URL(string: "https://example.com")!))
        }
        #expect(mock.requestCount == 1)
    }
}
