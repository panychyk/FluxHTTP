import Foundation

public struct HTTPResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let url: URL?
    public let data: Data

    public init(
        statusCode: Int,
        headers: [String: String] = [:],
        url: URL? = nil,
        data: Data = Data()
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.url = url
        self.data = data
    }

    public init(data: Data, response: HTTPURLResponse) {
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            if let key = key as? String, let value = value as? String {
                headers[key] = value
            }
        }
        self.init(
            statusCode: response.statusCode,
            headers: headers,
            url: response.url,
            data: data
        )
    }

    public var isSuccess: Bool {
        (200..<300).contains(statusCode)
    }

    /// Case-insensitive header lookup, matching `HTTPURLResponse.value(forHTTPHeaderField:)` semantics.
    public func value(forHTTPHeaderField field: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(field) == .orderedSame }?.value
    }

    /// Throws `HTTPError.unacceptableStatus` when the status code falls outside `acceptable`.
    @discardableResult
    public func validated(acceptable: Range<Int> = 200..<300) throws -> HTTPResponse {
        guard acceptable.contains(statusCode) else {
            throw HTTPError.unacceptableStatus(response: self)
        }
        return self
    }
}
