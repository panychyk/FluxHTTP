import Foundation

/// Composes a decorator pipeline around a base client.
///
/// Decorators added later wrap the ones added earlier: the last `add` becomes
/// the outermost layer and sees the request first.
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
}
