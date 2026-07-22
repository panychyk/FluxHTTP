# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
this repository.

## Commands

```bash
swift build
swift test
swift test --filter RetryDecoratorTests
swift test --filter RetryDecoratorTests/doesNotRetryCancellation
```

Use Swift tools 6.3 or newer. The package targets iOS 16+ and macOS 13+.
Tests use Swift Testing (`@Suite`, `@Test`, and `#expect`), not XCTest.

## Product boundary

FluxHTTP is a dependency-free Swift 6 library centered on `HTTPClient` and raw
`Data`. It sends requests and preserves HTTP responses; it does not own payload
formats, DTOs, authentication, default headers, caching, logging, or domain
errors. Those policies belong in application targets and can wrap a client with
`HTTPClientDecorator`.

`RetryDecorator` is the only built-in policy. It is always opt-in.

## Source layout

```text
Sources/FluxHTTP/
├── Core/
│   ├── HTTPClient.swift
│   ├── HTTPRequest.swift
│   ├── HTTPResponse.swift
│   └── HTTPError.swift
├── Transport/
│   └── URLSessionClient.swift
├── Composition/
│   ├── HTTPClientDecorator.swift
│   ├── HTTPClientBuilder.swift
│   └── BaseURLClient.swift
└── Decorators/
    ├── RetryDecorator.swift
    └── RetryPolicy.swift
```

Keep new code small and independent. Do not move application policy into the
transport.

## Core protocol and requests

`HTTPClient` has two requirements:

- `send(_ request: URLRequest)` is the raw transport entry point.
- `send(_ request: HTTPRequest, baseURL: URL?)` resolves the convenience request.

The second method has a default implementation, but it must remain a protocol
requirement. That preserves dynamic dispatch when `BaseURLClient` is stored as
`any HTTPClient`. Conformers normally need to implement only the `URLRequest`
method.

`HTTPRequest` is a value type whose body is `Data?`. Its factories are `.get`,
`.head`, `.delete`, `.post`, `.put`, and `.patch`. Callers own encoding and must
set format-specific headers themselves. Query values belong in `queryItems`, not
inside a relative `path`. A relative path needs a supplied base URL; an absolute
path ignores it.

## Responses and errors

`HTTPResponse` preserves `statusCode`, `headers`, `url`, and raw `data`.
`send` does not reject non-2xx responses. `validated(acceptable:)` is an opt-in,
format-independent check and throws
`HTTPError.unacceptableStatus(response: HTTPResponse)`, retaining the complete
response. Header lookup through `value(forHTTPHeaderField:)` is
case-insensitive.

`URLSessionClient` converts a Foundation response to `HTTPResponse`, maps URL
loading failures to `.transport`, non-HTTP responses to
`.invalidResponse`, and other errors to `.unknown`. Both task cancellation and
`URLError.cancelled` must emerge as `CancellationError`.

## Composition

`HTTPClientDecorator` is an open forwarding base class. Subclasses override
`send(_ request: URLRequest)` and call `wrapped.send(request)`. They inherit
`@unchecked Sendable`, so mutable stored state must be synchronized.

`HTTPClientBuilder.add` wraps the current pipeline. The last decorator added is
the outermost one and receives requests first. `build(baseURL:)` then places
`BaseURLClient` outside the completed pipeline. A per-call base URL overrides the
stored one; absolute paths and raw `URLRequest` values are not rewritten.

## Retry semantics

`RetryPolicy` defaults to idempotent methods only and statuses `408`, `429`,
`500`, `502`, `503`, and `504`. Non-idempotent methods require explicit opt-in,
and a request with `httpBodyStream` must not be retried. Cancellation is never
retried.

Backoff and jitter are bounded by `maximumDelay`. `Retry-After` accepts both
delta-seconds and HTTP-date forms. A valid server delay is never shortened; if
it exceeds the configured maximum, return the response without retrying. Keep
delay calculation in the internal pure helper so edge cases stay deterministic
under test.

## Testing and concurrency

Tests live in `Tests/FluxHTTPTests/` and generally mirror their source type.
Use `MockHTTPClient` for canned results and request recording instead of network
access. Cover success, failure, cancellation, retry exhaustion, and relevant
concurrency behavior.

All public clients must remain `Sendable`. Any mutable state in an
`@unchecked Sendable` type must use explicit synchronization. Match the existing
four-space Swift style and keep one primary public type per file.
