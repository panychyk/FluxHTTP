import Foundation

public enum HTTPError: Error, LocalizedError {
    case invalidResponse
    case transport(URLError)
    case unacceptableStatus(code: Int, data: Data)
    case unknown(any Error)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server returned a non-HTTP response."
        case .transport(let error):
            return "Transport error: \(error.localizedDescription)"
        case .unacceptableStatus(let code, _):
            return "Request failed with status code \(code)."
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
}
