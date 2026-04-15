import Foundation

public final class URLSessionClient: HTTPClient {
    
    private let session: URLSession
    
    public init(session: URLSession = .shared) {
        self.session = session
    }
    
    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw HTTPError.invalidResponse
            }
            return HTTPResponse(data: data, response: http)
            
        } catch let error as URLError {
            throw HTTPError.transport(error)
        }
    }
}
