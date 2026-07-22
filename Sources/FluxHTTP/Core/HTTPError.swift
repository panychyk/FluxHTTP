import Foundation

public enum HTTPError: Error, LocalizedError {
    case invalidRequest(String)
    case invalidResponse
    case transport(URLError)
    case unacceptableStatus(response: HTTPResponse)
    case unknown(any Error)

    public var errorDescription: String? {
        switch self {
        case .invalidRequest(let reason):
            return "Invalid request: \(reason)."
        case .invalidResponse:
            return "The server returned a non-HTTP response."
        case .transport(let error):
            return "Transport error: \(error.localizedDescription)"
        case .unacceptableStatus(let response):
            return "Request failed with status code \(response.statusCode)."
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
}
