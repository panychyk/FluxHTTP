import Foundation

/// Sends HTTP requests and returns responses with an unprocessed `Data` body.
///
/// FluxHTTP does not encode request models or interpret response payloads.
/// Use `send(_:)` with a `URLRequest`, or build an `HTTPRequest` with raw body
/// data.
public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse

    /// Resolves `request` against `baseURL` and sends it. Has a default
    /// implementation; `BaseURLClient` overrides it to supply a stored base.
    func send(_ request: HTTPRequest, baseURL: URL?) async throws -> HTTPResponse
}
