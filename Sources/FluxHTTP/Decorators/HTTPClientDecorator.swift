import Foundation

open class HTTPClientDecorator: @unchecked Sendable, HTTPClient {
    
    public let wrapped: HTTPClient
    
    public init(wrapping: HTTPClient) {
        self.wrapped = wrapping
    }
    
    open func send(_ request: URLRequest) async throws -> HTTPResponse {
        try await wrapped.send(request)
    }
}
