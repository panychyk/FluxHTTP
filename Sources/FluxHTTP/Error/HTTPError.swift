import Foundation

public enum HTTPError: Error {
    case invalidResponse
    case transport(URLError)
}
