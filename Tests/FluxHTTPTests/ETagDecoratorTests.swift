import Foundation
import Testing
@testable import FluxHTTP

private func getRequest(_ url: String) -> URLRequest {
    URLRequest(url: URL(string: url)!)
}

@Suite struct ETagDecoratorTests {

    @Test func savesETagAndBodyFromSuccessfulResponse() async throws {
        let storage = InMemoryETagStorage()
        let body = Data("payload".utf8)
        let mock = MockHTTPClient(response: HTTPResponse(
            statusCode: 200,
            headers: ["ETag": "\"v1\""],
            data: body
        ))
        let client = ETagDecorator(wrapping: mock, storage: storage)

        _ = try await client.send(getRequest("https://example.com/a"))

        let entry = storage.entry(for: "https://example.com/a")
        #expect(entry?.etag == "\"v1\"")
        #expect(entry?.body == body)
        // First request must not carry a conditional header.
        #expect(mock.requests[0].value(forHTTPHeaderField: "If-None-Match") == nil)
    }

    @Test func sendsIfNoneMatchAndReturnsCachedBodyOn304() async throws {
        let storage = InMemoryETagStorage()
        let body = Data("cached".utf8)
        storage.save(ETagEntry(etag: "\"v1\"", body: body), for: "https://example.com/a")

        let mock = MockHTTPClient(response: HTTPResponse(statusCode: 304))
        let client = ETagDecorator(wrapping: mock, storage: storage)

        let response = try await client.send(getRequest("https://example.com/a"))

        #expect(mock.requests[0].value(forHTTPHeaderField: "If-None-Match") == "\"v1\"")
        #expect(response.statusCode == 200)
        #expect(response.data == body)
    }

    @Test func keysByRequestURL() async throws {
        let storage = InMemoryETagStorage()
        let mock = MockHTTPClient(results: [
            .success(HTTPResponse(statusCode: 200, headers: ["ETag": "\"a\""], data: Data("a".utf8))),
            .success(HTTPResponse(statusCode: 200, headers: ["ETag": "\"b\""], data: Data("b".utf8)))
        ])
        let client = ETagDecorator(wrapping: mock, storage: storage)

        _ = try await client.send(getRequest("https://example.com/a"))
        _ = try await client.send(getRequest("https://example.com/b"))

        #expect(storage.entry(for: "https://example.com/a")?.etag == "\"a\"")
        #expect(storage.entry(for: "https://example.com/b")?.etag == "\"b\"")
        // Different URL must not inherit a foreign ETag.
        #expect(mock.requests[1].value(forHTTPHeaderField: "If-None-Match") == nil)
    }

    @Test func doesNotOverrideCallerProvidedIfNoneMatch() async throws {
        let storage = InMemoryETagStorage()
        storage.save(ETagEntry(etag: "\"stored\"", body: Data()), for: "https://example.com/a")

        let mock = MockHTTPClient(response: HTTPResponse(statusCode: 200))
        let client = ETagDecorator(wrapping: mock, storage: storage)

        var request = getRequest("https://example.com/a")
        request.setValue("\"manual\"", forHTTPHeaderField: "If-None-Match")
        _ = try await client.send(request)

        #expect(mock.requests[0].value(forHTTPHeaderField: "If-None-Match") == "\"manual\"")
    }

    @Test func passesThroughNonGETRequests() async throws {
        let storage = InMemoryETagStorage()
        let mock = MockHTTPClient(response: HTTPResponse(
            statusCode: 200,
            headers: ["ETag": "\"v1\""]
        ))
        let client = ETagDecorator(wrapping: mock, storage: storage)

        var request = getRequest("https://example.com/a")
        request.httpMethod = "POST"
        _ = try await client.send(request)

        #expect(storage.entry(for: "https://example.com/a") == nil)
        #expect(mock.requests[0].value(forHTTPHeaderField: "If-None-Match") == nil)
    }

    @Test func defaultStorageCachesAcrossRequests() async throws {
        let body = Data("fresh".utf8)
        let mock = MockHTTPClient(results: [
            .success(HTTPResponse(statusCode: 200, headers: ["ETag": "\"v1\""], data: body)),
            .success(HTTPResponse(statusCode: 304))
        ])
        let client = ETagDecorator(wrapping: mock)

        let first = try await client.send(getRequest("https://example.com/a"))
        let second = try await client.send(getRequest("https://example.com/a"))

        #expect(first.data == body)
        #expect(mock.requests[1].value(forHTTPHeaderField: "If-None-Match") == "\"v1\"")
        #expect(second.statusCode == 200)
        #expect(second.data == body)
    }

    @Test func returns304AsIsWhenNothingCached() async throws {
        let mock = MockHTTPClient(response: HTTPResponse(statusCode: 304))
        let client = ETagDecorator(wrapping: mock, storage: InMemoryETagStorage())

        let response = try await client.send(getRequest("https://example.com/a"))

        #expect(response.statusCode == 304)
        #expect(response.data.isEmpty)
    }
}
