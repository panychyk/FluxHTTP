import Foundation

/// Conditional-request cache keyed by request URL.
///
/// GET responses carrying an `ETag` header are stored together with their
/// body. Subsequent requests to the same URL send `If-None-Match`, and a
/// `304 Not Modified` is transparently replaced with a `200` response built
/// from the cached body, so callers never observe an empty 304.
public final class ETagDecorator: HTTPClientDecorator, @unchecked Sendable {

    private let storage: any ETagStorage
    private let keyPrefix: String

    public init(
        wrapping: any HTTPClient,
        storage: any ETagStorage = InMemoryETagStorage(),
        keyPrefix: String = ""
    ) {
        self.storage = storage
        self.keyPrefix = keyPrefix
        super.init(wrapping: wrapping)
    }

    public override func send(_ request: URLRequest) async throws -> HTTPResponse {
        let method = (request.httpMethod ?? "GET").uppercased()
        guard method == "GET", let url = request.url else {
            return try await wrapped.send(request)
        }

        let key = keyPrefix + url.absoluteString
        let cached = storage.entry(for: key)

        var request = request
        if let cached, request.value(forHTTPHeaderField: "If-None-Match") == nil {
            request.setValue(cached.etag, forHTTPHeaderField: "If-None-Match")
        }

        let response = try await wrapped.send(request)

        if response.statusCode == 304 {
            guard let cached else { return response }
            return HTTPResponse(
                statusCode: 200,
                headers: response.headers,
                url: response.url,
                data: cached.body
            )
        }

        if response.isSuccess,
           let etag = response.value(forHTTPHeaderField: "ETag") {
            storage.save(ETagEntry(etag: etag, body: response.data), for: key)
        }

        return response
    }
}
