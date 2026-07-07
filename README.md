# FluxHTTP

![Swift 6](https://img.shields.io/badge/Swift-6-orange.svg)
![Platforms](https://img.shields.io/badge/platforms-iOS%2016%2B%20%7C%20macOS%2013%2B-lightgrey.svg)
![License](https://img.shields.io/badge/license-MIT-blue.svg)

FluxHTTP is a lightweight, composable HTTP networking framework for Swift built
around a decorator-based pipeline architecture.

It lets you extend networking behavior — retry, ETag caching, logging, and more —
by wrapping a base client in independent layers, without ever modifying core
networking logic. Every layer is just an `HTTPClient`, so you compose exactly the
behavior you need and nothing else.

---

## ✨ Features

- **Async/await native** — a single `send(_:) async throws` entry point.
- **Decorator-based architecture** — compose behavior as stackable layers.
- **Automatic retries** — exponential backoff, jitter, and `Retry-After` support.
- **ETag conditional caching** — transparent `304 Not Modified` handling.
- **Structured logging** — built on Apple's unified logging (`os.Logger`).
- **Typed errors** — a single `HTTPError` enum for every failure mode.
- **Codable decoding & validation** — first-class `HTTPResponse` helpers.
- **Swift 6 ready** — full `Sendable` correctness under strict concurrency.
- **Easy to mock and test** — the whole surface is one small protocol.

---

## Requirements

- Swift 6 (tools version 6.3+)
- iOS 16+ / macOS 13+

---

## Installation

### Swift Package Manager

Add FluxHTTP to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/panychyk/FluxHTTP", from: "1.0.0")
]
```

Then add it to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: ["FluxHTTP"]
)
```

### Xcode

In Xcode, go to **File → Add Package Dependencies…**, enter
`https://github.com/panychyk/FluxHTTP`, and choose the `1.0.0` version rule.

---

## Quick Start

```swift
import FluxHTTP

// Compose a client: URLSession base + retry + logging.
let client = HTTPClientBuilder()
    .add { RetryDecorator(wrapping: $0) }
    .add { LoggingDecorator(wrapping: $0) }
    .build()

struct User: Decodable {
    let id: Int
    let name: String
}

let request = URLRequest(url: URL(string: "https://api.example.com/users/1")!)

let response = try await client.send(request)
let user = try response
    .validated()          // throws HTTPError.unacceptableStatus on non-2xx
    .decode(User.self)    // JSON → your Codable model

print(user.name)
```

---

## Core Concepts

### `HTTPClient`

Everything in FluxHTTP is an `HTTPClient`: the base transport, every decorator,
and your composed pipeline all share the same one-method protocol.

```swift
public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}
```

The default transport is `URLSessionClient`, which wraps a `URLSession`
(`.shared` by default) and normalizes cancellation and transport failures into
`HTTPError`:

```swift
let base = URLSessionClient()                       // uses URLSession.shared
let custom = URLSessionClient(session: myURLSession) // or inject your own
```

### `HTTPResponse`

`send(_:)` returns a value-type `HTTPResponse` with convenient helpers:

```swift
public struct HTTPResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let url: URL?
    public let data: Data
}
```

| Member | Description |
| --- | --- |
| `isSuccess` | `true` for a 2xx status code. |
| `value(forHTTPHeaderField:)` | Case-insensitive header lookup. |
| `validated(acceptable:)` | Throws `HTTPError.unacceptableStatus` outside `200..<300` (customizable); `@discardableResult`. |
| `decode(_:decoder:)` | Decodes the body into any `Decodable` (uses `JSONDecoder` by default). |

### `HTTPClientBuilder`

The builder composes decorators around a base client:

```swift
let client = HTTPClientBuilder(base: URLSessionClient())
    .add { ETagDecorator(wrapping: $0) }
    .add { RetryDecorator(wrapping: $0) }
    .add { LoggingDecorator(wrapping: $0) }
    .build()
```

> **Layer ordering matters.** Decorators added later wrap the ones added earlier,
> so the **last** `add` becomes the **outermost** layer and sees the request
> first. In the example above, a request flows
> `Logging → Retry → ETag → URLSession`, which means each retry is logged and each
> retried request still benefits from ETag caching.

### Writing a custom decorator

Subclass `HTTPClientDecorator` and override `send(_:)`. Call `wrapped.send(_:)`
to pass the request down the pipeline:

```swift
final class AuthDecorator: HTTPClientDecorator, @unchecked Sendable {
    private let token: String

    init(wrapping: any HTTPClient, token: String) {
        self.token = token
        super.init(wrapping: wrapping)
    }

    override func send(_ request: URLRequest) async throws -> HTTPResponse {
        var request = request
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await wrapped.send(request)
    }
}
```

`HTTPClientDecorator` is `@unchecked Sendable`, so keep any stored state
immutable or otherwise thread-safe.

---

## Built-in Decorators

### RetryDecorator

Retries failed requests according to a configurable `RetryPolicy`. It retries on
retryable status codes and transient transport errors, honors a `Retry-After`
header (delta-seconds form), and respects task cancellation.

```swift
let policy = RetryPolicy(
    maxRetries: 3,
    delay: 0.5,
    usesExponentialBackoff: true,
    usesJitter: true
)

let client = HTTPClientBuilder()
    .add { RetryDecorator(wrapping: $0, policy: policy) }
    .build()
```

`RetryPolicy` defaults:

| Option | Default |
| --- | --- |
| `maxRetries` | `2` |
| `delay` | `0.3` seconds |
| `usesExponentialBackoff` | `true` |
| `usesJitter` | `true` |
| `retryableStatusCodes` | `500...599`, `408`, `429` |
| `retryableURLErrorCodes` | `timedOut`, `networkConnectionLost`, `notConnectedToInternet`, `dnsLookupFailed`, `cannotFindHost`, `cannotConnectToHost` |
| `retryableMethods` | `GET`, `HEAD`, `PUT`, `DELETE`, `OPTIONS`, `TRACE` |

> Only idempotent methods are retried by default. Opt `POST`/`PATCH` in
> explicitly via `retryableMethods` if it's safe for your endpoint.

### LoggingDecorator

Logs each request, its outcome (status code and duration), and any error using
Apple's unified logging system.

```swift
let client = HTTPClientBuilder()
    .add { LoggingDecorator(wrapping: $0) }
    .build()

// Or provide a custom logger:
import os
let logger = Logger(subsystem: "com.myapp.network", category: "http")
let custom = LoggingDecorator(wrapping: URLSessionClient(), logger: logger)
```

The default logger uses subsystem `FluxHTTP` and category `network`.

### ETagDecorator

Adds transparent conditional caching for `GET` requests. It stores the `ETag` and
body of successful responses, sends `If-None-Match` on subsequent requests to the
same URL, and rebuilds a full `200` response from the cache when the server
replies `304 Not Modified` — so callers never observe an empty `304`.

```swift
let client = HTTPClientBuilder()
    .add { ETagDecorator(wrapping: $0) } // in-memory storage by default
    .build()
```

Storage is pluggable via the `ETagStorage` protocol. The built-in
`InMemoryETagStorage` is thread-safe; provide your own for persistent caching:

```swift
final class DiskETagStorage: ETagStorage, @unchecked Sendable {
    func entry(for key: String) -> ETagEntry? { /* ... */ }
    func save(_ entry: ETagEntry, for key: String) { /* ... */ }
}

let client = HTTPClientBuilder()
    .add { ETagDecorator(wrapping: $0, storage: DiskETagStorage(), keyPrefix: "v1:") }
    .build()
```

---

## Error Handling

All failures surface as a single `HTTPError` enum:

```swift
public enum HTTPError: Error, LocalizedError {
    case invalidResponse                        // non-HTTP response
    case transport(URLError)                    // network/URL loading failure
    case unacceptableStatus(code: Int, data: Data) // failed validation
    case unknown(any Error)                     // anything else
}
```

Combine it with `validated()` to turn unexpected status codes into typed errors:

```swift
do {
    let user = try await client.send(request)
        .validated()
        .decode(User.self)
} catch let HTTPError.unacceptableStatus(code, data) {
    print("Server returned \(code): \(String(decoding: data, as: UTF8.self))")
} catch {
    print("Request failed: \(error.localizedDescription)")
}
```

---

## Testing

Because the entire framework is built on the one-method `HTTPClient` protocol,
mocking is trivial — no `URLProtocol` subclassing or network stubbing required.
Inject a scripted client that returns canned responses and records the requests
it receives (see [`Tests/FluxHTTPTests/MockHTTPClient.swift`](Tests/FluxHTTPTests/MockHTTPClient.swift)):

```swift
let mock = MockHTTPClient(response: HTTPResponse(statusCode: 200, data: jsonData))

let client = HTTPClientBuilder(base: mock)
    .add { RetryDecorator(wrapping: $0) }
    .build()

let response = try await client.send(request)
#expect(mock.requestCount == 1)
```

Run the test suite with:

```bash
swift test
```

---

## License

FluxHTTP is available under the MIT License. See [LICENSE](LICENSE) for details.
