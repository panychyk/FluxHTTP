import Foundation

public struct ETagEntry: Sendable {
    public let etag: String
    public let body: Data

    public init(etag: String, body: Data) {
        self.etag = etag
        self.body = body
    }
}

/// Implementations must be thread-safe: `ETagDecorator` may call these
/// methods concurrently from multiple tasks.
public protocol ETagStorage: Sendable {
    func entry(for key: String) -> ETagEntry?
    func save(_ entry: ETagEntry, for key: String)
}

public final class InMemoryETagStorage: ETagStorage, @unchecked Sendable {

    private let lock = NSLock()
    private var entries: [String: ETagEntry] = [:]

    public init() {}

    public func entry(for key: String) -> ETagEntry? {
        lock.withLock { entries[key] }
    }

    public func save(_ entry: ETagEntry, for key: String) {
        lock.withLock { entries[key] = entry }
    }
}
