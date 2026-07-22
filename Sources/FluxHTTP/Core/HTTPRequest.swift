import Foundation

/// A transport-independent description of an HTTP request.
///
/// FluxHTTP treats the body as raw `Data`. Callers are responsible for
/// encoding payloads and setting format-specific headers such as
/// `Content-Type`.
///
/// Build one with the static factories (`.get`, `.post`, …) and send it with
/// `HTTPClient.send(_:baseURL:)`:
///
/// ```swift
/// let response = try await client.send(
///     .get("/habits", query: [URLQueryItem(name: "from", value: "2026-07-01")]),
///     baseURL: URL(string: "https://api.example.com/v1")!
/// )
/// ```
///
/// `path` is either a full URL string (`"https://…"`) or a path resolved
/// against the `baseURL` given at send time. Query parameters belong in
/// `queryItems`, not in `path` — a relative path is treated as a single
/// path component and `?`/`#` inside it are percent-encoded.
public struct HTTPRequest: Sendable {

    public var method: String
    public var path: String
    public var queryItems: [URLQueryItem]
    public var headers: [String: String]
    public var body: Data?
    /// Overrides the `URLRequest` default (60 s) when set.
    public var timeoutInterval: TimeInterval?

    public init(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Data? = nil,
        timeoutInterval: TimeInterval? = nil
    ) {
        self.method = method.uppercased()
        self.path = path
        self.queryItems = queryItems
        self.headers = headers
        self.body = body
        self.timeoutInterval = timeoutInterval
    }

    /// Throws `HTTPError.invalidRequest` when `path` is relative and no
    /// `baseURL` is given, or when the combined URL cannot be formed.
    public func urlRequest(relativeTo baseURL: URL? = nil) throws -> URLRequest {
        var request = URLRequest(url: try resolvedURL(baseURL: baseURL))
        request.httpMethod = method
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = body
        if let timeoutInterval {
            request.timeoutInterval = timeoutInterval
        }
        return request
    }

    private func resolvedURL(baseURL: URL?) throws -> URL {
        let absolute: URL
        if let url = URL(string: path), url.scheme != nil {
            absolute = url
        } else if let baseURL {
            absolute = path.isEmpty ? baseURL : baseURL.appendingPathComponent(path)
        } else {
            throw HTTPError.invalidRequest("relative path \"\(path)\" requires a baseURL")
        }

        guard !queryItems.isEmpty else { return absolute }
        guard var components = URLComponents(url: absolute, resolvingAgainstBaseURL: true) else {
            throw HTTPError.invalidRequest("cannot parse URL \"\(absolute.absoluteString)\"")
        }
        components.queryItems = (components.queryItems ?? []) + queryItems
        guard let url = components.url else {
            throw HTTPError.invalidRequest("cannot append query items to \"\(absolute.absoluteString)\"")
        }
        return url
    }
}

// MARK: - Factories

public extension HTTPRequest {

    static func get(
        _ path: String,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:]
    ) -> HTTPRequest {
        HTTPRequest(method: "GET", path: path, queryItems: query, headers: headers)
    }

    static func head(
        _ path: String,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:]
    ) -> HTTPRequest {
        HTTPRequest(method: "HEAD", path: path, queryItems: query, headers: headers)
    }

    static func delete(
        _ path: String,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:]
    ) -> HTTPRequest {
        HTTPRequest(method: "DELETE", path: path, queryItems: query, headers: headers)
    }

    static func post(
        _ path: String,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Data? = nil
    ) -> HTTPRequest {
        HTTPRequest(method: "POST", path: path, queryItems: query, headers: headers, body: body)
    }

    static func put(
        _ path: String,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Data? = nil
    ) -> HTTPRequest {
        HTTPRequest(method: "PUT", path: path, queryItems: query, headers: headers, body: body)
    }

    static func patch(
        _ path: String,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Data? = nil
    ) -> HTTPRequest {
        HTTPRequest(method: "PATCH", path: path, queryItems: query, headers: headers, body: body)
    }
}

// MARK: - Sending

public extension HTTPClient {

    /// Default implementation of the `send(_:baseURL:)` requirement.
    func send(_ request: HTTPRequest, baseURL: URL?) async throws -> HTTPResponse {
        try await send(request.urlRequest(relativeTo: baseURL))
    }

    // Forwards through the requirement rather than using a default argument,
    // so a `BaseURLClient` behind `any HTTPClient` still sees the call.
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try await send(request, baseURL: nil)
    }
}
