# FluxHTTP

![Swift 6](https://img.shields.io/badge/Swift-6-orange.svg)
![Platforms](https://img.shields.io/badge/platforms-iOS%2016%2B%20%7C%20macOS%2013%2B-lightgrey.svg)
![License](https://img.shields.io/badge/license-MIT-blue.svg)

FluxHTTP is a small, dependency-free HTTP component for Swift. It sends
`URLRequest` or `HTTPRequest` values and returns an `HTTPResponse` whose body is
raw `Data`.

The library deliberately does not own payload formats, authentication, default
headers, logging, caching, or domain errors. Applications can add those policies
as decorators without changing the transport.

## Features

- A small, `Sendable` `HTTPClient` protocol built for async/await.
- Raw `Data` request and response bodies with no encoding convention imposed.
- Convenient `.get`, `.post`, `.put`, `.patch`, `.delete`, and `.head` request
  factories.
- Relative request paths through an optional pipeline-wide base URL.
- Explicit status validation that preserves the complete rejected response.
- Composable application-owned decorators.
- One opt-in built-in policy: safe, bounded retries.
- Swift 6 strict-concurrency support and easy test doubles.

## Requirements

- Swift tools 6.3+
- iOS 16+
- macOS 13+

## Installation

Add FluxHTTP to the dependencies in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/panychyk/FluxHTTP", from: "3.0.0")
]
```

Then add the product to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "FluxHTTP", package: "FluxHTTP")
    ]
)
```

In Xcode, choose **File → Add Package Dependencies…** and enter
`https://github.com/panychyk/FluxHTTP`, then select version `3.0.0` or later.

## Quick start

```swift
import Foundation
import FluxHTTP

let client = HTTPClientBuilder()
    .build(baseURL: URL(string: "https://api.example.com/v1")!)

let response = try await client.send(.get("users/1")).validated()
print(response.statusCode)
print(String(decoding: response.data, as: UTF8.self))
```

`send` returns every valid HTTP response, including non-2xx responses.
`validated()` is opt-in and throws only when the status is outside the accepted
range.

## Payloads belong to the application

FluxHTTP never guesses the format of a body. Decode a response in the application
with the serializer and configuration that its API requires:

```swift
struct User: Decodable {
    let id: Int
    let name: String
}

let response = try await client.send(.get("users/1")).validated()
let user = try JSONDecoder().decode(User.self, from: response.data)
```

Likewise, encode request values in the application and set format-specific
headers explicitly:

```swift
struct NewHabit: Encodable {
    let name: String
}

let body = try JSONEncoder().encode(NewHabit(name: "Run"))
let request = HTTPRequest.post(
    "habits",
    headers: ["Content-Type": "application/json"],
    body: body
)

let response = try await client.send(request).validated(acceptable: 200..<300)
```

This keeps custom encoders, envelopes, DTO mapping, and domain errors outside
the networking component.

## Core API

### `HTTPClient`

The transport, decorators, and finished pipeline all use the same protocol:

```swift
public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
    func send(_ request: HTTPRequest, baseURL: URL?) async throws -> HTTPResponse
}
```

The second requirement has a default implementation that resolves the
`HTTPRequest` and forwards a `URLRequest`. It remains a protocol requirement so
`BaseURLClient` dispatches correctly through `any HTTPClient`.

`URLSessionClient` is the default transport:

```swift
let shared = URLSessionClient()
let injected = URLSessionClient(session: configuredSession)
```

It converts Foundation responses to `HTTPResponse`, normalizes cancellation to
`CancellationError`, and maps transport failures to `HTTPError`.

### `HTTPRequest`

`HTTPRequest` is a transport-independent request description with mutable
`method`, `path`, `queryItems`, `headers`, `body`, and `timeoutInterval` fields.
Its body is always `Data?`.

```swift
let request = HTTPRequest.get(
    "habits",
    query: [URLQueryItem(name: "from", value: "2026-07-01")],
    headers: ["Accept": "application/json"]
)

let response = try await client.send(request)
```

Factories are available for `get`, `head`, `delete`, `post`, `put`, and `patch`.
The body-taking factories accept raw `Data?`. Put query parameters in `query:`;
a relative path is resolved against the supplied or stored base URL. A path that
already contains an absolute URL is sent without applying the base URL.

You can also construct and send a `URLRequest` directly:

```swift
var request = URLRequest(url: URL(string: "https://example.com/health")!)
request.httpMethod = "HEAD"
let response = try await client.send(request)
```

### `HTTPResponse`

Every response preserves the information applications need for their own
policies:

```swift
public struct HTTPResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let url: URL?
    public let data: Data
}
```

- `isSuccess` is `true` for a 2xx response.
- `value(forHTTPHeaderField:)` performs case-insensitive header lookup.
- `validated(acceptable:)` returns the same response or throws
  `HTTPError.unacceptableStatus(response:)`; the default range is `200..<300`.

### Status and transport errors

`HTTPError` describes failures produced by the component:

```swift
public enum HTTPError: Error, LocalizedError {
    case invalidRequest(String)
    case invalidResponse
    case transport(URLError)
    case unacceptableStatus(response: HTTPResponse)
    case unknown(any Error)
}
```

The rejected `HTTPResponse` is retained so the application can inspect its
status, headers, URL, and raw body:

```swift
do {
    try await client.send(.get("users/1")).validated()
} catch HTTPError.unacceptableStatus(let response) {
    let message = String(decoding: response.data, as: UTF8.self)
    print("Server returned \(response.statusCode): \(message)")
}
```

FluxHTTP does not turn status responses into application-specific errors.

## Composition

### Base URL

`build(baseURL:)` places a `BaseURLClient` around the completed pipeline. Call
sites can then omit the repeated host:

```swift
let client = HTTPClientBuilder()
    .build(baseURL: URL(string: "https://api.example.com/v1")!)

let habits = try await client.send(.get("habits"))
let staging = try await client.send(.get("habits"), baseURL: stagingURL)
let health = try await client.send(.get("https://status.example.com/health"))
```

A per-call `baseURL:` overrides the stored base URL, while an absolute request
path wins over both. Raw `URLRequest` values are never rewritten.

### Application-owned decorators

Policies specific to an application should live in its own target. Subclass
`HTTPClientDecorator`, override `send(_:)`, and forward the request through
`wrapped`:

```swift
final class APIKeyDecorator: HTTPClientDecorator, @unchecked Sendable {
    private let apiKey: String

    init(wrapping: any HTTPClient, apiKey: String) {
        self.apiKey = apiKey
        super.init(wrapping: wrapping)
    }

    override func send(_ request: URLRequest) async throws -> HTTPResponse {
        var request = request
        if request.value(forHTTPHeaderField: "X-API-Key") == nil {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }
        return try await wrapped.send(request)
    }
}
```

Subclasses inherit unchecked sendability. Keep stored values immutable, or
synchronize mutable state explicitly.

### Decorator order

Each `add` wraps the current pipeline. The last decorator added is outermost and
receives a request first:

```swift
let client = HTTPClientBuilder()
    .add { APIKeyDecorator(wrapping: $0, apiKey: apiKey) }
    .add { RetryDecorator(wrapping: $0) }
    .build(baseURL: URL(string: "https://api.example.com")!)
```

The request flow is:

```text
BaseURLClient → RetryDecorator → APIKeyDecorator → URLSessionClient
```

Here each retry passes through the API-key layer again. Change the order when a
policy should apply once around the complete retry operation.

## Opt-in retries

`RetryDecorator` is the only built-in decorator, and FluxHTTP never adds it
automatically:

```swift
let policy = RetryPolicy(
    maxRetries: 3,
    delay: 0.5,
    maximumDelay: 10,
    usesExponentialBackoff: true,
    usesJitter: true
)

let client = HTTPClientBuilder()
    .add { RetryDecorator(wrapping: $0, policy: policy) }
    .build(baseURL: URL(string: "https://api.example.com")!)
```

The defaults are intentionally conservative:

| Option | Default |
| --- | --- |
| `maxRetries` | `2` |
| `delay` | `0.3` seconds |
| `maximumDelay` | `30` seconds |
| `usesExponentialBackoff` | `true` |
| `usesJitter` | `true` |
| `retryableStatusCodes` | `408`, `429`, `500`, `502`, `503`, `504` |
| `retryableMethods` | `GET`, `HEAD`, `PUT`, `DELETE`, `OPTIONS`, `TRACE` |

Retries also cover a small set of transient `URLError` codes. Cancellation is
never retried. Requests with an `httpBodyStream` are never retried, and
non-idempotent methods such as `POST` and `PATCH` require explicit opt-in through
`retryableMethods`.

Both `Retry-After` forms are supported: delta-seconds and HTTP-date. A valid
server delay is never shortened; if it exceeds `maximumDelay`, the response is
returned without retrying.

## Testing

Because clients depend on `HTTPClient`, tests can inject a small implementation
that returns canned `HTTPResponse` values and records the `URLRequest` values it
receives. The package's test helper is available at
[`MockHTTPClient.swift`](Tests/FluxHTTPTests/MockHTTPClient.swift).

Run the package checks with:

```bash
swift build
swift test
```

## License

FluxHTTP is available under the MIT License. See [LICENSE](LICENSE) for details.
