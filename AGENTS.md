# Repository Guidelines

## Project Structure & Module Organization

FluxHTTP is a dependency-free Swift Package Manager library. Production code lives in `Sources/FluxHTTP/`, grouped by responsibility: `Core/` defines requests, responses, errors, and the client protocol; `Transport/` contains `URLSessionClient`; `Composition/` contains `BaseURLClient`, `HTTPClientBuilder`, and `HTTPClientDecorator`; and `Decorators/` contains the opt-in `RetryDecorator` and its `RetryPolicy`. Tests live in `Tests/FluxHTTPTests/` and generally mirror source types, for example `RetryDecorator.swift` and `RetryDecoratorTests.swift`. The repository has no runtime assets or executable target.

## Architecture Overview

Keep the public surface centered on `HTTPClient` and raw `Data`. `RetryDecorator` is the only built-in policy and must remain opt-in; authentication, default headers, caching, logging, payload encoding/decoding, and domain errors belong to applications. Application-specific cross-cutting behavior should wrap an existing client through `HTTPClientDecorator` and forward requests to `wrapped`. Decorator order matters: the last item added to `HTTPClientBuilder` is the outermost layer and receives requests first. Prefer small, independent components over adding policy to the transport.

## Build, Test, and Development Commands

- `swift build` compiles the package with Swift 6 language mode.
- `swift test` runs the complete test suite.
- `swift test --filter RetryDecoratorTests` runs one suite.
- `swift test --filter RetryDecoratorTests/doesNotRetryCancellation` runs one test by name.

Use Swift tools 6.3 or newer. Supported deployment targets are iOS 16+ and macOS 13+.

## Coding Style & Naming Conventions

Follow the existing Swift style: four-space indentation, opening braces on the declaration line, and one primary public type per file. Use `UpperCamelCase` for types and `lowerCamelCase` for methods and properties. Name decorators with the `Decorator` suffix and test files with `Tests`. Preserve strict concurrency semantics: public clients are `Sendable`, and mutable state in `@unchecked Sendable` classes must be synchronized. No formatter or linter is configured, so match nearby code and keep APIs explicit.

## Testing Guidelines

Tests use Swift Testing (`import Testing`, `@Suite`, `@Test`, and `#expect`), not XCTest. Add focused tests for success, failure, cancellation, and concurrency-sensitive behavior. Use `MockHTTPClient` to avoid network access and assert both responses and recorded requests. Keep the test target buildable on iOS and macOS; guard host-only testing APIs, such as subprocess expectations, with conditional compilation. There is no enforced coverage threshold; every behavior change should include regression coverage.

## Commit & Pull Request Guidelines

Write concise, imperative commit subjects such as `Add HTTPRequest builder` or `Fix Retry-After handling`. Keep each commit focused. Pull requests should explain the motivation, summarize public API changes, list verification commands, and link relevant issues. Include screenshots only for documentation or rendered-output changes; networking changes should include tests instead.
