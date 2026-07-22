import Foundation
import Testing
@testable import FluxHTTP

@Suite struct BaseURLClientTests {

    private let base = URL(string: "https://api.example.com/v1")!

    private func makeClient(
        status: Int = 200,
        data: Data = Data()
    ) -> (client: any HTTPClient, mock: MockHTTPClient) {
        let mock = MockHTTPClient(response: HTTPResponse(statusCode: status, data: data))
        let client = HTTPClientBuilder(base: mock).build(baseURL: base)
        return (client, mock)
    }

    @Test func requestResolvesAgainstStoredBase() async throws {
        let (client, mock) = makeClient()

        _ = try await client.send(
            .get("habits", query: [URLQueryItem(name: "limit", value: "5")])
        )

        #expect(mock.requests.first?.url?.absoluteString == "https://api.example.com/v1/habits?limit=5")
    }

    @Test func oneArgSendUsesStoredBase() async throws {
        let (client, mock) = makeClient()

        _ = try await client.send(.post("habits", body: Data("x".utf8)))

        let sent = try #require(mock.requests.first)
        #expect(sent.url?.absoluteString == "https://api.example.com/v1/habits")
        #expect(sent.httpMethod == "POST")
    }

    @Test func perCallBaseURLOverridesStored() async throws {
        let (client, mock) = makeClient()
        let other = URL(string: "https://staging.example.com")!

        _ = try await client.send(.get("habits"), baseURL: other)

        #expect(mock.requests.first?.url?.absoluteString == "https://staging.example.com/habits")
    }

    @Test func absoluteURLIgnoresStoredBase() async throws {
        let (client, mock) = makeClient()

        _ = try await client.send(.get("https://other.example.com/status"))

        #expect(mock.requests.first?.url?.absoluteString == "https://other.example.com/status")
    }

    @Test func urlRequestPassesThroughUnchanged() async throws {
        let (client, mock) = makeClient()
        let url = URL(string: "https://direct.example.com/ping")!

        _ = try await client.send(URLRequest(url: url))

        #expect(mock.requests.first?.url == url)
    }

    @Test func responseDataPassesThroughUnchanged() async throws {
        let data = Data([0x00, 0x7F, 0xFF])
        let (client, mock) = makeClient(data: data)

        let response = try await client.send(.get("habits/1"))

        #expect(response.data == data)
        #expect(mock.requests.first?.url?.absoluteString == "https://api.example.com/v1/habits/1")
    }
}
