import Foundation

public final class ETagDecorator: HTTPClientDecorator {

    private let storage: ETagStorage
    private let etagKey: String
    
    public init(
        wrapping: HTTPClient,
        storage: ETagStorage,
        etagKey: String
    ) {
        self.storage = storage
        self.etagKey = etagKey
        super.init(wrapping: wrapping)
    }
    
    public override func send(_ request: URLRequest) async throws -> HTTPResponse {
        var request = request
        if let etag = storage.etag(for: etagKey) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        let response = try await wrapped.send(request)
        if response.response.statusCode == 304 {
            return response
        }
        if let etag = response.response.value(forHTTPHeaderField: "Etag") {
            storage.save(etag: etag, for: etagKey)
        }
        return response
    }
}
