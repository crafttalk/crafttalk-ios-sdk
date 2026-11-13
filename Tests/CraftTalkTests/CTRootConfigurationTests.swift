import XCTest
import Security
@testable import CraftTalk

final class CTRootConfigurationTests: XCTestCase {
    private func root(_ number: Int = 1) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "synthetic-root-\(number)", withExtension: "der", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    func testTrustRootsDoNotGrantNavigationPermission() throws {
        let policy = try CTSecurityPolicy(configuration: CTSecurityConfiguration(trustedRootsByHost: ["FILES.example.com.": [root()]]),
                                          baseURL: URL(string: "https://chat.example.com"))
        XCTAssertEqual(policy.rootsByHost.keys.sorted(), ["files.example.com"])
        XCTAssertFalse(policy.allows(try XCTUnwrap(URL(string: "https://files.example.com/document"))))
        XCTAssertTrue(policy.allows(try XCTUnwrap(URL(string: "https://chat.example.com"))))
        XCTAssertNil(policy.rootsByHost["chat.example.com"])
    }

    func testAllowedRedirectDoesNotAddTrustRoots() throws {
        let policy = try CTSecurityPolicy(configuration: CTSecurityConfiguration(allowedRedirectHosts: ["files.example.com"]),
                                          baseURL: URL(string: "https://chat.example.com"))
        XCTAssertTrue(policy.rootsByHost.isEmpty)
        XCTAssertTrue(policy.allows(try XCTUnwrap(URL(string: "https://files.example.com"))))
    }

    func testMergesRootsForNormalizedHostWithoutLosingCertificates() throws {
        let first = try root(1), second = try root(2)
        let policy = try CTSecurityPolicy(configuration: CTSecurityConfiguration(trustedRootsByHost: [
            "CHAT.example.com": [first], "chat.example.com.": [second]
        ]), baseURL: URL(string: "https://chat.example.com"))
        let certificates = try XCTUnwrap(policy.rootsByHost["chat.example.com"])
        XCTAssertEqual(certificates.count, 2)
        XCTAssertEqual(Set(certificates.map { SecCertificateCopyData($0) as Data }), Set([first, second]))
    }

    func testRejectsInvalidHostsEmptyRootsAndInvalidDER() throws {
        let configurations: [(CTSecurityConfiguration, Int, String?)] = [
            (CTSecurityConfiguration(trustedRootsByHost: ["https://chat.example.com": [try root()]]), 1, nil),
            (CTSecurityConfiguration(allowedRedirectHosts: ["*.example.com"]), 1, nil),
            (CTSecurityConfiguration(trustedRootsByHost: ["CHAT.example.com.": []]), 2, "chat.example.com"),
            (CTSecurityConfiguration(trustedRootsByHost: ["chat.example.com": [Data()]]), 3, "chat.example.com"),
            (CTSecurityConfiguration(trustedRootsByHost: ["chat.example.com": [Data("not DER".utf8)]]), 3, "chat.example.com"),
            (CTSecurityConfiguration(trustedRootsByHost: ["chat.example.com": [try root(), Data([0, 1])]]), 3, "chat.example.com")
        ]
        for (configuration, code, host) in configurations {
            XCTAssertThrowsError(try CTSecurityPolicy(configuration: configuration, baseURL: URL(string: "https://chat.example.com"))) {
                guard let error = $0 as? CTChatError else { return XCTFail("Ожидалась CTChatError") }
                XCTAssertEqual(error.stage, .configuration)
                XCTAssertEqual(error.domain, "CTChat")
                XCTAssertEqual(error.code, code)
                XCTAssertEqual(error.host, host)
            }
        }
    }
}
