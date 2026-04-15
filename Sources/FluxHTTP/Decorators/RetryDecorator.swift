import Foundation

public final class RetryDecorator: HTTPClientDecorator {
    
    private let policy: RetryPolicy
    
    public init(
        wrapping: HTTPClient,
        policy: RetryPolicy
    ) {
        self.policy = policy
        super.init(wrapping: wrapping)
    }
    
    public override func send(_ request: URLRequest) async throws -> HTTPResponse {
        
        var attempt = 0
        
        while true {
            do {
                let response = try await wrapped.send(request)
                
                // retry only for bad status codes
                if policy.retryableStatusCodes.contains(response.response.statusCode),
                   attempt < policy.maxRetries {
                    
                    attempt += 1
                    try await sleep()
                    continue
                }
                
                return response
                
            } catch {
                // retry only transport errors
                if attempt < policy.maxRetries {
                    attempt += 1
                    try await sleep()
                    continue
                }
                
                throw error
            }
        }
    }
    
    private func sleep() async throws {
        try await Task.sleep(nanoseconds: UInt64(policy.delay * 1_000_000_000))
    }
}

public struct RetryPolicy {
    
    public let maxRetries: Int
    public let delay: TimeInterval
    public let retryableStatusCodes: Set<Int>
    
    public init(
        maxRetries: Int = 2,
        delay: TimeInterval = 0.3,
        retryableStatusCodes: Set<Int> = Set(500...599)
    ) {
        self.maxRetries = maxRetries
        self.delay = delay
        self.retryableStatusCodes = retryableStatusCodes
    }
}
