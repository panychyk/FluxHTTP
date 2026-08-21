import Foundation
@testable import FluxHTTP

/// Scripted client: returns queued results in order; the last result repeats
/// once the queue is exhausted. Records every request it receives.
actor MockHTTPClient: HTTPClient {

    private var results: [Result<HTTPResponse, Error>]
    private var recorded: [URLRequest] = []

    init(results: [Result<HTTPResponse, Error>]) {
        precondition(!results.isEmpty, "MockHTTPClient needs at least one result")
        self.results = results
    }

    init(response: HTTPResponse) {
        self.init(results: [.success(response)])
    }

    var requests: [URLRequest] {
        recorded
    }

    var requestCount: Int {
        recorded.count
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        recorded.append(request)
        let result = results.count > 1 ? results.removeFirst() : results[0]
        return try result.get()
    }
}
