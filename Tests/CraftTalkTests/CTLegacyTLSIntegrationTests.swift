import XCTest
@testable import CraftTalk

final class CTLegacyTLSIntegrationTests: XCTestCase {
    private var fixture: CTHTTPSFixture!

    override func setUpWithError() throws {
        fixture = try CTHTTPSFixture(test: self)
        try fixture.configure(["file": CTHTTPSFixture.response(Data("legacy".utf8))])
    }

    override func tearDown() { fixture = nil }

    func testMatchingLegacyLeafAcceptsPrivateChain() throws {
        let result = try request(profile: "valid", pin: "valid")
        XCTAssertEqual(try result.get(), Data("legacy".utf8))
        XCTAssertEqual(try fixture.requests().count, 1)
    }

    func testLegacyPinRejectsRenewedLeafUnderSameRoot() throws {
        let result = try request(profile: "renewed", pin: "valid")
        assertEvaluatorRejects(result)
    }

    func testLegacyPinDoesNotApplyToUnmatchedHost() throws {
        let result = try request(profile: "valid", pin: "valid", base: "https://other.invalid")
        XCTAssertThrowsError(try result.get()) { error in
            let failure = error as NSError
            XCTAssertEqual(failure.domain, NSURLErrorDomain)
            XCTAssertEqual(failure.code, NSURLErrorServerCertificateUntrusted)
        }
        XCTAssertTrue(try fixture.requests().isEmpty)
    }

    func testNewModeDoesNotAcceptLegacyPinInsteadOfTrustedRoot() throws {
        let result = try request(profile: "valid", pin: "valid", policy: fixture.policy(root: "other-root"))
        assertEvaluatorRejects(result)
    }

    private func request(profile: String, pin: String, base: String = "https://localhost",
                         policy: CTSecurityPolicy? = nil) throws -> Result<Data, Error> {
        try fixture.requestWithTrustEvaluator(profile: profile, policy: policy,
                                              legacyCertificate: fixture.der(pin), legacyBaseURL: base)
    }

    private func assertEvaluatorRejects(_ result: Result<Data, Error>,
                                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try result.get(), file: file, line: line) { error in
            let failure = error as? CTChatError
            XCTAssertEqual(failure?.stage, .tls, file: file, line: line)
            XCTAssertEqual(failure?.domain, NSURLErrorDomain, file: file, line: line)
            XCTAssertEqual(failure?.code, NSURLErrorServerCertificateUntrusted, file: file, line: line)
        }
        XCTAssertTrue(try fixture.requests().isEmpty, file: file, line: line)
    }
}
