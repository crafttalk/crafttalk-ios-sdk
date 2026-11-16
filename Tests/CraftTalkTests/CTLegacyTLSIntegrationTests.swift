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
        XCTAssertThrowsError(try result.get())
        XCTAssertTrue(try fixture.requests().isEmpty)
    }

    func testLegacyPinDoesNotApplyToUnmatchedHost() throws {
        let result = try request(profile: "valid", pin: "valid", base: "https://other.invalid")
        XCTAssertThrowsError(try result.get())
        XCTAssertTrue(try fixture.requests().isEmpty)
    }

    func testNewModeDoesNotAcceptLegacyPinInsteadOfTrustedRoot() throws {
        let result = try request(profile: "valid", pin: "valid", policy: fixture.policy(root: "other-root"))
        XCTAssertThrowsError(try result.get())
        XCTAssertTrue(try fixture.requests().isEmpty)
    }

    func testLegacyExpiredLeafRetainsLeafComparisonSemantics() throws {
        // Это существующая legacy-семантика; новый режим обязан отвергать этот leaf.
        XCTAssertEqual(try request(profile: "expired", pin: "expired").get(), Data("legacy".utf8))
    }

    private func request(profile: String, pin: String, base: String = "https://localhost", policy: CTSecurityPolicy? = nil) throws -> Result<Data, Error> {
        let stopped = expectation(description: "Проверочная TLS-сессия остановлена")
        let probe = CTLegacyTLSProbe(policy: policy, pin: try fixture.der(pin), base: base, stopped: { stopped.fulfill() })
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: configuration, delegate: probe, delegateQueue: nil)
        let completed = expectation(description: "Legacy-проверка на настоящем TLS challenge")
        var result: Result<Data, Error>?
        session.dataTask(with: fixture.url("file", profile: profile)) { data, _, error in
            result = error.map { .failure($0) } ?? .success(data ?? Data())
            completed.fulfill()
        }.resume()
        wait(for: [completed], timeout: 15)
        session.invalidateAndCancel()
        wait(for: [stopped], timeout: 5)
        return try XCTUnwrap(result)
    }
}

// Challenge приходит от URLSession; тест не вызывает delegate вручную.
private final class CTLegacyTLSProbe: NSObject, URLSessionDelegate {
    private let policy: CTSecurityPolicy?
    private let pin: Data
    private let base: String
    private let stopped: () -> Void

    init(policy: CTSecurityPolicy?, pin: Data, base: String, stopped: @escaping () -> Void) {
        self.policy = policy
        self.pin = pin
        self.base = base
        self.stopped = stopped
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        CTTrustEvaluator.handle(challenge, policy: policy, legacyCertificate: pin, legacyBaseURL: base,
                                reportError: { _ in }, completion: completionHandler)
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) { stopped() }
}
