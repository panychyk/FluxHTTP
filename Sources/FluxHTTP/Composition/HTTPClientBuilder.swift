import Foundation

/// Composes a decorator pipeline around a base client.
///
/// Decorators added later wrap the ones added earlier: the last `add` becomes
/// the outermost decorator and sees the request first. `build(baseURL:)` then
/// places `BaseURLClient` outside the completed decorator pipeline.
public struct HTTPClientBuilder {

    private let client: any HTTPClient

    public init(base: any HTTPClient = URLSessionClient()) {
        self.client = base
    }

    public func add(_ decorator: (any HTTPClient) -> any HTTPClient) -> HTTPClientBuilder {
        HTTPClientBuilder(base: decorator(client))
    }

    public func build() -> any HTTPClient {
        client
    }

    /// Builds the pipeline wrapped in a `BaseURLClient`, so relative
    /// request paths resolve against `baseURL` before the outermost decorator
    /// receives the resulting `URLRequest`.
    public func build(baseURL: URL) -> any HTTPClient {
        BaseURLClient(wrapping: client, baseURL: baseURL)
    }
}
