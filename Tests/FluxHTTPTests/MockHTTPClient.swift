import Foundation
@testable import FluxHTTP

/// Scripted client: returns queued results in order; the last result repeats
/// once the queue is exhausted. Records every request it receives.
final class MockHTTPClient: HTTPClient, @unchecked Sendable {

    private let lock = NSLock()
    private var results: [Result<HTTPResponse, Error>]
    private var recorded: [URLRequest] = []

    init(results: [Result<HTTPResponse, Error>]) {
        precondition(!results.isEmpty, "MockHTTPClient needs at least one result")
        self.results = results
    }

    convenience init(response: HTTPResponse) {
        self.init(results: [.success(response)])
    }

    var requests: [URLRequest] {
        lock.withLock { recorded }
    }

    var requestCount: Int {
        lock.withLock { recorded.count }
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let result = lock.withLock {
            recorded.append(request)
            return results.count > 1 ? results.removeFirst() : results[0]
        }
        return try result.get()
    }
}
