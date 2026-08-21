import Foundation

/// A client that adds behavior around another `HTTPClient`.
///
/// Conforming types must satisfy `HTTPClient`'s checked `Sendable`
/// requirements. Prefer immutable structs or final classes, and keep mutable
/// state behind an actor or another explicit synchronization boundary.
public protocol HTTPClientDecorator: HTTPClient {
    var wrapped: any HTTPClient { get }
}

public extension HTTPClientDecorator {
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        try await wrapped.send(request)
    }
}
