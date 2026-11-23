import XCTest
@testable import CraftTalk

final class CTSecurityPolicyTests: XCTestCase {
    func testNormalizesCaseAndOneTrailingDot() throws {
        let policy = try CTSecurityPolicy(configuration: CTSecurityConfiguration(allowedRedirectHosts: ["FILES.Example.COM."]),
                                          baseURL: URL(string: "https://CHAT.Example.COM."))
        for address in ["HTTPS://chat.example.com/a", "https://CHAT.EXAMPLE.COM./b", "https://files.example.com"] {
            XCTAssertTrue(policy.allows(try XCTUnwrap(URL(string: address))), address)
        }
        XCTAssertEqual(policy.allowedHosts, ["chat.example.com", "files.example.com"])
    }

    func testHostLengthBoundaries() {
        let label = String(repeating: "a", count: 63)
        let maximum = [label, label, label, String(repeating: "b", count: 61)].joined(separator: ".")
        XCTAssertEqual(CTSecurityPolicy.normalizedHost(maximum), maximum)
        XCTAssertEqual(CTSecurityPolicy.normalizedHost(maximum + "."), maximum)
        XCTAssertNil(CTSecurityPolicy.normalizedHost(maximum + "b"))
        XCTAssertEqual(CTSecurityPolicy.normalizedHost(label + ".com"), label + ".com")
        XCTAssertNil(CTSecurityPolicy.normalizedHost(String(repeating: "a", count: 64) + ".com"))
    }

    func testRejectsMalformedHostInputs() {
        for host in ["", ".", "chat..example.com", "chat.example.com..", "-chat.example.com", "chat-.example.com",
                     "chat_example.com", " chat.example.com", "chat.example.com ", "chat.example.com\n",
                     "*.example.com", "https://chat.example.com", "chat.example.com:443", "chat.example.com/path",
                     "user@chat.example.com", "пример.рф", "[::1]", "chat%2eexample.com"] {
            XCTAssertNil(CTSecurityPolicy.normalizedHost(host), host)
        }
    }

    func testAllowsPunycodeAndIPv4() throws {
        for host in ["xn--e1afmkfd.xn--p1ai", "192.0.2.1"] {
            XCTAssertEqual(CTSecurityPolicy.normalizedHost(host), host)
            let url = try XCTUnwrap(URL(string: "https://" + host))
            let policy = try CTSecurityPolicy(configuration: CTSecurityConfiguration(), baseURL: url)
            XCTAssertTrue(policy.allows(url))
        }
    }

    func testDoesNotMatchSubdomainsOrLookalikeHosts() throws {
        let policy = try CTSecurityPolicy(configuration: CTSecurityConfiguration(), baseURL: URL(string: "https://chat.example.com"))
        for host in ["sub.chat.example.com", "chat.example.com.evil.test", "evilchat.example.com", "example.com", "chat-example.com"] {
            XCTAssertFalse(policy.allows(try XCTUnwrap(URL(string: "https://" + host))), host)
        }
    }

    func testAllowsPathQueryAndPortChangesOnAllowedHost() throws {
        let policy = try CTSecurityPolicy(configuration: CTSecurityConfiguration(), baseURL: URL(string: "https://chat.example.com:8443"))
        for address in ["https://chat.example.com:9443/file?a=b#fragment", "https://chat.example.com/other", "https://chat.example.com"] {
            XCTAssertTrue(policy.allows(try XCTUnwrap(URL(string: address))))
        }
    }

    func testRejectsCredentialsOtherSchemesAndRelativeURLs() throws {
        let policy = try CTSecurityPolicy(configuration: CTSecurityConfiguration(), baseURL: URL(string: "https://chat.example.com"))
        for address in ["https://user:password@chat.example.com", "https://user@chat.example.com", "https://@chat.example.com",
                        "http://chat.example.com", "ftp://chat.example.com", "file:///tmp/chat", "//chat.example.com", "/path"] {
            XCTAssertFalse(policy.allows(try XCTUnwrap(URL(string: address))), address)
        }
    }

    func testRejectsInvalidBaseURLsWithConfigurationError() {
        for address in [nil, "http://chat.example.com", "/path", "https://user@chat.example.com"] as [String?] {
            XCTAssertThrowsError(try CTSecurityPolicy(configuration: CTSecurityConfiguration(), baseURL: address.flatMap(URL.init(string:)))) {
                XCTAssertEqual(($0 as? CTChatError)?.stage, .configuration)
                XCTAssertEqual(($0 as? CTChatError)?.code, 4)
            }
        }
    }

    func testRejectionPreservesRequestedStageAndSanitizesURL() throws {
        let policy = try CTSecurityPolicy(configuration: CTSecurityConfiguration(), baseURL: URL(string: "https://chat.example.com"))
        let error = policy.rejection(for: URL(string: "https://OTHER.example.com/private?token=secret"), stage: .download)
        XCTAssertEqual(error.stage, .download)
        XCTAssertEqual(error.host, "other.example.com")
        XCTAssertEqual(error.domain, "CTChat")
        XCTAssertEqual(error.code, 5)
        XCTAssertEqual(policy.rejection(for: nil).stage, .navigation)
        XCTAssertNil(policy.rejection(for: nil).host)
    }

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
