import Foundation

/// Resolves relative `HTTPRequest` paths against a fixed base URL, so call
/// sites can write `client.send(.get("habits"))` without repeating the host.
///
/// A per-call `baseURL:` still wins, and absolute-URL paths are sent as-is.
/// Wrap the finished pipeline (or use `HTTPClientBuilder.build(baseURL:)`):
/// resolution happens where the `HTTPRequest` enters the client, so this
/// must be the outermost layer.
public struct BaseURLClient: HTTPClient {

    public let baseURL: URL
    private let wrapped: any HTTPClient

    public init(wrapping: any HTTPClient, baseURL: URL) {
        self.wrapped = wrapping
        self.baseURL = baseURL
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        try await wrapped.send(request)
    }

    public func send(_ request: HTTPRequest, baseURL: URL?) async throws -> HTTPResponse {
        try await wrapped.send(request.urlRequest(relativeTo: baseURL ?? self.baseURL))
    }
}
