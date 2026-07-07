import Foundation
import Testing
@testable import FluxHTTP

private final class StubURLProtocol: URLProtocol {

    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (URLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func makeClient() -> URLSessionClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return URLSessionClient(session: URLSession(configuration: config))
}

@Suite(.serialized) struct URLSessionClientTests {

    @Test func mapsHTTPURLResponseIntoHTTPResponse() async throws {
        let url = URL(string: "https://example.com/data")!
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 201,
                httpVersion: "HTTP/1.1",
                headerFields: ["ETag": "\"v1\""]
            )!
            return (response, Data("hello".utf8))
        }
        defer { StubURLProtocol.handler = nil }

        let response = try await makeClient().send(URLRequest(url: url))

        #expect(response.statusCode == 201)
        #expect(response.data == Data("hello".utf8))
        #expect(response.value(forHTTPHeaderField: "etag") == "\"v1\"")
        #expect(response.url == url)
    }

    @Test func wrapsURLErrorIntoTransportError() async throws {
        StubURLProtocol.handler = { _ in throw URLError(.timedOut) }
        defer { StubURLProtocol.handler = nil }

        do {
            _ = try await makeClient().send(URLRequest(url: URL(string: "https://example.com")!))
            Issue.record("Expected an error")
        } catch let HTTPError.transport(urlError) {
            #expect(urlError.code == .timedOut)
        }
    }

    @Test func throwsInvalidResponseForNonHTTPResponse() async throws {
        StubURLProtocol.handler = { request in
            let response = URLResponse(
                url: request.url!,
                mimeType: nil,
                expectedContentLength: 0,
                textEncodingName: nil
            )
            return (response, Data())
        }
        defer { StubURLProtocol.handler = nil }

        do {
            _ = try await makeClient().send(URLRequest(url: URL(string: "https://example.com")!))
            Issue.record("Expected an error")
        } catch let error as HTTPError {
            guard case .invalidResponse = error else {
                Issue.record("Expected invalidResponse, got \(error)")
                return
            }
        }
    }

    @Test func normalizesCancelledURLErrorIntoCancellationError() async throws {
        StubURLProtocol.handler = { _ in throw URLError(.cancelled) }
        defer { StubURLProtocol.handler = nil }

        await #expect(throws: CancellationError.self) {
            _ = try await makeClient().send(URLRequest(url: URL(string: "https://example.com")!))
        }
    }

    @Test func wrapsNonURLErrorIntoUnknown() async throws {
        StubURLProtocol.handler = { _ in
            throw NSError(domain: "TestDomain", code: 42)
        }
        defer { StubURLProtocol.handler = nil }

        do {
            _ = try await makeClient().send(URLRequest(url: URL(string: "https://example.com")!))
            Issue.record("Expected an error")
        } catch let error as HTTPError {
            guard case .unknown = error else {
                Issue.record("Expected unknown, got \(error)")
                return
            }
        }
    }
}
