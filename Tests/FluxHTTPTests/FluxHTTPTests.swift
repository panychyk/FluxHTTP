import Foundation
import Testing
@testable import FluxHTTP

@Suite struct HTTPResponseTests {

    @Test func headerLookupIsCaseInsensitive() {
        let response = HTTPResponse(statusCode: 200, headers: ["Content-Type": "application/json"])
        #expect(response.value(forHTTPHeaderField: "content-type") == "application/json")
        #expect(response.value(forHTTPHeaderField: "X-Missing") == nil)
    }

    @Test func validatedThrowsOnUnacceptableStatus() {
        let response = HTTPResponse(statusCode: 404, data: Data("nope".utf8))
        #expect(throws: HTTPError.self) {
            try response.validated()
        }
        #expect(response.isSuccess == false)
    }

    @Test func validatedPassesThroughAcceptableStatus() throws {
        let response = HTTPResponse(statusCode: 200)
        let same = try response.validated()
        #expect(same.statusCode == 200)
        #expect(response.isSuccess)
    }

    @Test func decodesJSONBody() throws {
        struct Payload: Decodable, Equatable {
            let name: String
        }
        let response = HTTPResponse(statusCode: 200, data: Data(#"{"name":"flux"}"#.utf8))
        #expect(try response.decode(Payload.self) == Payload(name: "flux"))
    }
}
