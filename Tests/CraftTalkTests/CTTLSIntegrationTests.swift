import XCTest
import Security
@testable import CraftTalk

final class CTTLSIntegrationTests: XCTestCase {
    private var fixture: CTHTTPSFixture!
    private var directory: URL!
    private var managers: [CTNetworkManager] = []

    override func setUpWithError() throws {
        fixture = try CTHTTPSFixture(test: self)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try fixture.configure(["file": CTHTTPSFixture.response(Data([0, 1, 255]))])
    }

    override func tearDownWithError() throws {
        for manager in managers {
            let stopped = expectation(description: "TLS-сессия завершена")
            manager.invalidate { stopped.fulfill() }
            wait(for: [stopped], timeout: 5)
        }
        managers.removeAll()
        fixture = nil
        if let directory = directory { try FileManager.default.removeItem(at: directory) }
    }

    func testPrivateChainAndRenewedLeafUnderSameRoot() throws {
        for profile in ["valid", "renewed"] {
            let file = try download(profile, policy: fixture.policy()).get()
            XCTAssertEqual(try Data(contentsOf: file), Data([0, 1, 255]))
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
        let result = download("valid", host: "127.0.0.1", policy: policy)
        assertTLSFailure(result)
        XCTAssertTrue(try fixture.requests().isEmpty)
    }

    func testPrivateCAIsNotInstalledAsSystemTrust() throws {
        let policy = try fixture.policy(hosts: [])
        assertTLSFailure(download("valid", policy: policy))
        XCTAssertTrue(try fixture.requests().isEmpty)
    }

    func testSystemTrustStillWorksWithUnrelatedAdditionalRoot() throws {
        // Системный CA установлен только в одноразовый симулятор, не в rootsByHost.
        let file = try download("system", policy: fixture.policy()).get()
        XCTAssertEqual(try Data(contentsOf: file), Data([0, 1, 255]))
        XCTAssertEqual(try fixture.requests().count, 1)
    }

    func testSystemTrustWorksWithoutAdditionalRoots() throws {
        XCTAssertNoThrow(try download("system", policy: fixture.policy(hosts: [])).get())
    }

    func testNativeLegacySessionUsesSystemTrustNotPrivatePin() throws {
        assertTLSFailure(download("valid", policy: nil))
        XCTAssertNoThrow(try download("system", policy: nil).get())
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
        assertTLSFailure(download(profile, policy: try fixture.policy()))
        XCTAssertTrue(try fixture.requests().isEmpty, "HTTP-запрос не должен уйти при ошибке TLS")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
    }

    private func assertTLSFailure(_ result: Result<URL, Error>, file: StaticString = #filePath, line: UInt = #line) {
        guard case .failure(let error) = result else { return XCTFail("Ожидался отказ TLS", file: file, line: line) }
        let failure = error as? CTChatError
        XCTAssertEqual(failure?.stage, .tls, file: file, line: line)
        XCTAssertEqual(failure?.domain, NSURLErrorDomain, file: file, line: line)
        XCTAssertTrue((-1206 ... -1200).contains(failure?.code ?? 0), file: file, line: line)
    }

    private func download(_ profile: String, host: String = "localhost", policy: CTSecurityPolicy?) -> Result<URL, Error> {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        let manager = CTNetworkManager(configuration: config, temporaryDirectory: directory)
        managers.append(manager)
        manager.securityPolicy = policy
        let completed = expectation(description: "Настоящее TLS-соединение: " + profile)
        var result: Result<URL, Error>?
        manager.loadDocumentFrom(url: fixture.url("file", profile: profile, host: host)) {
            XCTAssertTrue(Thread.isMainThread)
            result = $0
            completed.fulfill()
        }
        wait(for: [completed], timeout: 15)
        return result ?? .failure(URLError(.timedOut))
    }
}
