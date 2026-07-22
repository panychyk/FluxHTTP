import Foundation
import Testing
@testable import FluxHTTP

@Suite struct HTTPResponseTests {

    @Test func headerLookupIsCaseInsensitive() {
        let response = HTTPResponse(statusCode: 200, headers: ["Content-Type": "application/json"])
        #expect(response.value(forHTTPHeaderField: "content-type") == "application/json")
        #expect(response.value(forHTTPHeaderField: "X-Missing") == nil)
    }

    @Test func validatedErrorContainsFullResponse() {
        let url = URL(string: "https://example.com/missing")!
        let body = Data("nope".utf8)
        let response = HTTPResponse(
            statusCode: 404,
            headers: ["Content-Type": "application/problem+json"],
            url: url,
            data: body
        )

        do {
            try response.validated()
            Issue.record("Expected validation to reject status 404")
        } catch let HTTPError.unacceptableStatus(rejectedResponse) {
            #expect(rejectedResponse.statusCode == 404)
            #expect(rejectedResponse.headers == ["Content-Type": "application/problem+json"])
            #expect(rejectedResponse.url == url)
            #expect(rejectedResponse.data == body)
        } catch {
            Issue.record("Expected HTTPError.unacceptableStatus, got \(error)")
        }

        #expect(response.isSuccess == false)
    }

    @Test func validatedPassesThroughAcceptableStatus() throws {
        let response = HTTPResponse(statusCode: 200)
        let same = try response.validated()
        #expect(same.statusCode == 200)
        #expect(response.isSuccess)
    }

    @Test func validatedUsesCustomAcceptableRange() throws {
        let response = HTTPResponse(statusCode: 304)

        let same = try response.validated(acceptable: 300..<400)

        #expect(same.statusCode == 304)
        #expect(throws: HTTPError.self) {
            try response.validated(acceptable: 200..<300)
        }
    }
}
