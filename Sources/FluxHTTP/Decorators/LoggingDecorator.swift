import Foundation

public final class LoggingDecorator: HTTPClientDecorator {
    public override func send(_ request: URLRequest) async throws -> HTTPResponse {
        print("➡️ Request:", request.url?.absoluteString ?? "")
        let result = try await wrapped.send(request)
        print("⬅️ Response:", request.url?.absoluteString ?? "", result.response.statusCode)
        return result
    }
}
