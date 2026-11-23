import XCTest
import Security
@testable import CraftTalk

final class CTTLSIntegrationTests: XCTestCase {
    private var fixture: CTHTTPSFixture!

    override func setUpWithError() throws {
        fixture = try CTHTTPSFixture(test: self)
        try fixture.configure(["file": CTHTTPSFixture.response(Data([0, 1, 255]))])
    }

    func testPrivateChainAndRenewedLeafUnderSameRoot() throws {
        for profile in ["valid", "renewed"] {
            XCTAssertEqual(try fixture.requestWithTrustEvaluator(profile: profile, policy: fixture.policy()).get(), Data([0, 1, 255]))
        }
        XCTAssertEqual(try fixture.requests().count, 2)
    }

    func testRejectsWrongHostnameOverRealTLS() throws { try rejects("wrong-host") }
    func testRejectsExpiredLeafOverRealTLS() throws { try rejects("expired") }
    func testRejectsNotYetValidLeafOverRealTLS() throws { try rejects("future") }
    func testRejectsMissingIntermediateOverRealTLS() throws { try rejects("missing") }
    func testRejectsWrongRootOverRealTLS() throws { try rejects("untrusted") }

    func testRootIsScopedToChallengeHost() throws {
        let policy = try fixture.policy(hosts: ["localhost"])
        let result = try fixture.requestWithTrustEvaluator(profile: "valid", host: "127.0.0.1", policy: policy)
        assertTLSFailure(result)
        XCTAssertTrue(try fixture.requests().isEmpty)
    }

    func testPrivateCAIsNotInstalledAsSystemTrust() throws {
        let policy = try fixture.policy(hosts: [])
        assertTLSFailure(try fixture.requestWithTrustEvaluator(profile: "valid", policy: policy))
        XCTAssertTrue(try fixture.requests().isEmpty)
    }

    func testSystemTrustStillWorksWithUnrelatedAdditionalRoot() throws {
        // Системный CA установлен только в одноразовый симулятор, не в rootsByHost.
        XCTAssertEqual(try fixture.requestWithTrustEvaluator(profile: "system", policy: fixture.policy()).get(), Data([0, 1, 255]))
        XCTAssertEqual(try fixture.requests().count, 1)
    }

    func testSystemTrustWorksWithoutAdditionalRoots() throws {
        XCTAssertEqual(try fixture.requestWithTrustEvaluator(profile: "system", policy: fixture.policy(hosts: [])).get(), Data([0, 1, 255]))
        XCTAssertEqual(try fixture.requests().count, 1)
    }

    func testSecTrustAtFixedDateChecksChainHostnameAndValidity() throws {
        let root = try fixture.certificate("root")
        for (leaf, host, expected) in [("valid", "localhost", true), ("renewed", "127.0.0.1", true),
                                       ("valid", "wrong.invalid", false), ("expired", "localhost", false),
                                       ("future", "localhost", false), ("untrusted", "localhost", false),
                                       ("missing", "localhost", false)] {
            let certificates = try [fixture.certificate(leaf), fixture.certificate("intermediate")]
            var trust: SecTrust?
            XCTAssertEqual(SecTrustCreateWithCertificates(certificates as CFArray, SecPolicyCreateSSL(true, host as CFString), &trust), errSecSuccess)
            let value = try XCTUnwrap(trust)
            XCTAssertEqual(SecTrustSetNetworkFetchAllowed(value, false), errSecSuccess)
            XCTAssertEqual(SecTrustSetVerifyDate(value, Date(timeIntervalSince1970: fixture.configuration.verifyTime) as CFDate), errSecSuccess)
            XCTAssertEqual(CTTrustEvaluator.evaluate(value, host: host, roots: [root]), expected, leaf + " / " + host)
        }
    }

    private func rejects(_ profile: String) throws {
        assertTLSFailure(try fixture.requestWithTrustEvaluator(profile: profile, policy: fixture.policy()))
        XCTAssertTrue(try fixture.requests().isEmpty, "HTTP-запрос не должен уйти при ошибке TLS")
    }

    private func assertTLSFailure(_ result: Result<Data, Error>, file: StaticString = #filePath, line: UInt = #line) {
        guard case .failure(let error) = result else { return XCTFail("Ожидался отказ TLS", file: file, line: line) }
        let failure = error as? CTChatError
        XCTAssertEqual(failure?.stage, .tls, file: file, line: line)
        XCTAssertEqual(failure?.domain, NSURLErrorDomain, file: file, line: line)
        XCTAssertTrue((-1206 ... -1200).contains(failure?.code ?? 0), file: file, line: line)
    }
}
