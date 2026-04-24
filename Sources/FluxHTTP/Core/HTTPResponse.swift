import Foundation

public struct HTTPResponse: @unchecked Sendable {
    public let data: Data
    public let response: HTTPURLResponse
    
    public init(data: Data, response: HTTPURLResponse) {
        self.data = data
        self.response = response
    }
}
