import Foundation

/// Base class for decorators. Subclasses inherit the `@unchecked Sendable`
/// conformance, so they must keep their stored state immutable or otherwise
/// thread-safe.
open class HTTPClientDecorator: HTTPClient, @unchecked Sendable {

    public let wrapped: any HTTPClient

    public init(wrapping: any HTTPClient) {
        self.wrapped = wrapping
    }

    open func send(_ request: URLRequest) async throws -> HTTPResponse {
        try await wrapped.send(request)
    }
}
