import Foundation

public protocol HTTPClient {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}
