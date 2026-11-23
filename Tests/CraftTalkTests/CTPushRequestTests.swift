import XCTest
@testable import CraftTalk

final class CTPushRequestTests: XCTestCase {
    func testBasePathAndPortArePreserved() throws {
        let request = CTPushRegistationRequest(baseURL: "https://chat.example.com:8443/prefix", namespace: "channel", fcmToken: "token", uuid: "id").urlRequest()
        XCTAssertEqual(request.url?.absoluteString, "https://chat.example.com:8443/prefix/webchat/channel/set-user-subscription")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? [String: String],
                       ["subscription": "token", "uuid": "id"])
    }

    func testTrailingSlashIsPreservedInEndpoint() throws {
        let request = CTPushRegistationRequest(baseURL: "https://chat.example.com/", namespace: "channel", fcmToken: "token", uuid: "id").urlRequest()
        XCTAssertEqual(request.url?.path, "//webchat/channel/set-user-subscription")
    }
}
