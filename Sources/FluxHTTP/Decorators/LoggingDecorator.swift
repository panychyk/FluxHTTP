import Foundation
import os

public final class LoggingDecorator: HTTPClientDecorator, @unchecked Sendable {

    private let logger: Logger

    public init(
        wrapping: any HTTPClient,
        logger: Logger = Logger(subsystem: "FluxHTTP", category: "network")
    ) {
        self.logger = logger
        super.init(wrapping: wrapping)
    }

    public override func send(_ request: URLRequest) async throws -> HTTPResponse {
        let method = (request.httpMethod ?? "GET").uppercased()
        let url = request.url?.absoluteString ?? "<no url>"
        logger.debug("➡️ \(method, privacy: .public) \(url, privacy: .public)")

        let start = ContinuousClock.now
        do {
            let response = try await wrapped.send(request)
            let duration = ContinuousClock.now - start
            logger.debug("⬅️ \(method, privacy: .public) \(url, privacy: .public) \(response.statusCode) in \(String(describing: duration), privacy: .public)")
            return response
        } catch {
            let duration = ContinuousClock.now - start
            logger.error("❌ \(method, privacy: .public) \(url, privacy: .public) failed in \(String(describing: duration), privacy: .public): \(String(describing: error), privacy: .public)")
            throw error
        }
    }
}
