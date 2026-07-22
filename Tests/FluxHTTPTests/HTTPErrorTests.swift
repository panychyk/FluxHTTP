import Foundation
import Testing
@testable import FluxHTTP

@Suite struct HTTPErrorTests {

    @Test func describesAllCases() {
        struct Dummy: Error {}

        #expect(HTTPError.invalidRequest("no baseURL").errorDescription == "Invalid request: no baseURL.")
        #expect(HTTPError.invalidResponse.errorDescription == "The server returned a non-HTTP response.")
        #expect(HTTPError.transport(URLError(.timedOut)).errorDescription?.hasPrefix("Transport error:") == true)
        #expect(HTTPError.unacceptableStatus(response: HTTPResponse(statusCode: 418)).errorDescription == "Request failed with status code 418.")
        #expect(HTTPError.unknown(Dummy()).errorDescription?.hasPrefix("Unknown error:") == true)
    }
}

@Suite struct HTTPClientDecoratorTests {

    @Test func baseDecoratorForwardsRequestUnchanged() async throws {
        let mock = MockHTTPClient(response: HTTPResponse(statusCode: 204))
        let client = HTTPClientDecorator(wrapping: mock)

        let request = URLRequest(url: URL(string: "https://example.com/base")!)
        let response = try await client.send(request)

        #expect(response.statusCode == 204)
        #expect(mock.requests[0].url?.absoluteString == "https://example.com/base")
    }
}
