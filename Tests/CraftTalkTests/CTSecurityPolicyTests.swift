import XCTest
@testable import CraftTalk

final class CTSecurityPolicyTests: XCTestCase {
    func testAllowsHTTPSOnBaseAndExplicitlyAllowedHosts() throws {
        let policy = try CTSecurityPolicy(
            configuration: CTSecurityConfiguration(allowedRedirectHosts: ["files.example.com"]),
            baseURL: XCTUnwrap(URL(string: "https://chat.example.com"))
        )

        XCTAssertTrue(policy.allows(try XCTUnwrap(URL(string: "https://chat.example.com/webchat"))))
        XCTAssertTrue(policy.allows(try XCTUnwrap(URL(string: "https://files.example.com/document.pdf"))))
    }

    func testRejectsHTTPAndUnlistedHosts() throws {
        let policy = try CTSecurityPolicy(
            configuration: CTSecurityConfiguration(),
            baseURL: XCTUnwrap(URL(string: "https://chat.example.com"))
        )

        XCTAssertFalse(policy.allows(try XCTUnwrap(URL(string: "http://chat.example.com/webchat"))))
        XCTAssertFalse(policy.allows(try XCTUnwrap(URL(string: "https://other.example.com/document.pdf"))))
    }
}
