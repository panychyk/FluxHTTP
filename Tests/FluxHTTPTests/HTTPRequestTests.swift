import Foundation
import Testing
@testable import FluxHTTP

@Suite struct HTTPRequestTests {

    private let base = URL(string: "https://api.example.com/v1")!

    // MARK: URL resolution

    @Test func absolutePathIgnoresBaseURL() throws {
        let request = try HTTPRequest.get("https://other.example.com/status")
            .urlRequest(relativeTo: base)

        #expect(request.url?.absoluteString == "https://other.example.com/status")
    }

    @Test func relativePathJoinsBaseURL() throws {
        let request = try HTTPRequest.get("habits").urlRequest(relativeTo: base)

        #expect(request.url?.absoluteString == "https://api.example.com/v1/habits")
    }

    @Test func leadingSlashDoesNotDoubleUp() throws {
        let request = try HTTPRequest.get("/habits").urlRequest(relativeTo: base)

        #expect(request.url?.absoluteString == "https://api.example.com/v1/habits")
    }

    @Test func emptyPathResolvesToBaseURL() throws {
        let request = try HTTPRequest.get("").urlRequest(relativeTo: base)

        #expect(request.url?.absoluteString == "https://api.example.com/v1")
    }

    @Test func relativePathWithoutBaseURLThrows() {
        #expect(throws: HTTPError.self) {
            try HTTPRequest.get("habits").urlRequest()
        }
    }

    // MARK: Query items

    @Test func queryItemsAreAppended() throws {
        let request = try HTTPRequest.get(
            "habits",
            query: [
                URLQueryItem(name: "from", value: "2026-07-01"),
                URLQueryItem(name: "limit", value: "10")
            ]
        ).urlRequest(relativeTo: base)

        #expect(request.url?.absoluteString == "https://api.example.com/v1/habits?from=2026-07-01&limit=10")
    }

    @Test func queryItemsMergeWithQueryInAbsoluteURL() throws {
        let request = try HTTPRequest.get(
            "https://api.example.com/v1/habits?from=2026-07-01",
            query: [URLQueryItem(name: "limit", value: "10")]
        ).urlRequest()

        #expect(request.url?.absoluteString == "https://api.example.com/v1/habits?from=2026-07-01&limit=10")
    }

    @Test func queryValuesArePercentEncoded() throws {
        let request = try HTTPRequest.get(
            "search",
            query: [URLQueryItem(name: "q", value: "hello world")]
        ).urlRequest(relativeTo: base)

        #expect(request.url?.absoluteString == "https://api.example.com/v1/search?q=hello%20world")
    }

    // MARK: Request fields

    @Test func methodHeadersBodyAndTimeoutAreApplied() throws {
        var httpRequest = HTTPRequest.post(
            "habits",
            headers: ["X-Custom": "value"],
            body: Data("payload".utf8)
        )
        httpRequest.timeoutInterval = 5

        let request = try httpRequest.urlRequest(relativeTo: base)

        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "X-Custom") == "value")
        #expect(request.httpBody == Data("payload".utf8))
        #expect(request.timeoutInterval == 5)
    }

    @Test func methodIsUppercased() {
        #expect(HTTPRequest(method: "patch", path: "x").method == "PATCH")
    }

    @Test func factoriesSetExpectedMethods() {
        #expect(HTTPRequest.get("x").method == "GET")
        #expect(HTTPRequest.head("x").method == "HEAD")
        #expect(HTTPRequest.delete("x").method == "DELETE")
        #expect(HTTPRequest.post("x").method == "POST")
        #expect(HTTPRequest.put("x").method == "PUT")
        #expect(HTTPRequest.patch("x").method == "PATCH")
    }

    @Test func bodyFactoriesPreserveRawDataAndHeaders() {
        let body = Data([0x00, 0x7F, 0xFF])

        let requests = [
            HTTPRequest.post("items", headers: ["Content-Type": "application/octet-stream"], body: body),
            HTTPRequest.put("items/1", headers: ["Content-Type": "application/octet-stream"], body: body),
            HTTPRequest.patch("items/1", headers: ["Content-Type": "application/octet-stream"], body: body),
        ]

        #expect(requests.map(\.body) == [body, body, body])
        #expect(requests.allSatisfy { $0.headers["Content-Type"] == "application/octet-stream" })
    }

    // MARK: Sending

    @Test func sendResolvesAgainstBaseURLAndForwardsToClient() async throws {
        let mock = MockHTTPClient(response: HTTPResponse(statusCode: 201))
        let client = HTTPClientBuilder(base: mock).build()
        let body = Data([0x00, 0x7F, 0xFF])

        let response = try await client.send(
            .post(
                "items",
                headers: ["Content-Type": "application/octet-stream"],
                body: body
            ),
            baseURL: base
        )

        #expect(response.statusCode == 201)
        let sent = try #require(mock.requests.first)
        #expect(sent.url?.absoluteString == "https://api.example.com/v1/items")
        #expect(sent.httpMethod == "POST")
        #expect(sent.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
        #expect(sent.httpBody == body)
    }
}
