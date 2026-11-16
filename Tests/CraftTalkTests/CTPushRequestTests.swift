import XCTest
@testable import CraftTalk

final class CTPushRequestTests: XCTestCase {
    func testBasePathAndPortArePreserved() throws {
        let request = CTPushRegistationRequest(baseURL: "https://chat.example.com:8443/prefix", namespace: "channel", fcmToken: "token", uuid: "id").urlRequest()
        XCTAssertEqual(request.url?.absoluteString, "https://chat.example.com:8443/prefix/webchat/channel/set-user-subscription")
    }

    func testTrailingSlashIsPreservedInEndpoint() throws {
        let request = CTPushRegistationRequest(baseURL: "https://chat.example.com/", namespace: "channel", fcmToken: "token", uuid: "id").urlRequest()
        XCTAssertEqual(request.url?.path, "//webchat/channel/set-user-subscription")
    }

}
