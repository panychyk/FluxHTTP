import Foundation

public struct HTTPClientBuilder {
    
    private var client: HTTPClient
    
    public init(base: HTTPClient) {
        self.client = base
    }
    
    public mutating func add(_ decorator: (HTTPClient) -> HTTPClient) {
        client = decorator(client)
    }
    
    public func build() -> HTTPClient {
        client
    }
}
