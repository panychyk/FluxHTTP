import Foundation

public protocol ETagStorage {
    func etag(for key: String) -> String?
    func save(etag: String, for key: String)
}
