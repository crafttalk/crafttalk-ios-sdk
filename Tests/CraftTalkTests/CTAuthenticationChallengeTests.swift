import XCTest
@testable import CraftTalk

// Эти проверки охватывают диспетчеризацию challenge, а не настоящую TLS-сессию.
final class CTAuthenticationChallengeTests: XCTestCase {
    func testNonServerTrustChallengesUseDefaultHandlingInBothModes() throws {
        let secure = try policy()
        for method in [NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest,
                       NSURLAuthenticationMethodClientCertificate] {
            for policy in [nil, secure] as [CTSecurityPolicy?] {
                let errors = handle(method: method, policy: policy, pin: Data([1]),
                                    expected: .performDefaultHandling)
                XCTAssertTrue(errors.isEmpty, method)
            }
        }
    }

    func testMissingServerTrustIsRejectedInSecureModeEvenWithLegacyPin() throws {
        for (host, expectedHost) in [("CHAT.Example.COM.", "chat.example.com"), ("invalid_host", nil)] as [(String, String?)] {
            let errors = handle(host: host, policy: try policy(), pin: Data([1]),
                                expected: .cancelAuthenticationChallenge)
            XCTAssertEqual(errors.count, 1)
            let error = try XCTUnwrap(errors.first)
            XCTAssertEqual(error.stage, .tls)
            XCTAssertEqual(error.host, expectedHost)
            XCTAssertEqual(error.domain, NSURLErrorDomain)
            XCTAssertEqual(error.code, NSURLErrorServerCertificateUntrusted)
        }
    }

    func testMissingServerTrustPreservesLegacyDefaultHandling() {
        for (pin, base) in [(Data([1]), "https://chat.example.com"),
                            (nil, "https://chat.example.com"),
                            (Data([1]), "https://other.example.com")] as [(Data?, String)] {
            XCTAssertTrue(handle(policy: nil, pin: pin, base: base,
                                 expected: .performDefaultHandling).isEmpty)
        }
    }

    private func policy() throws -> CTSecurityPolicy {
        try CTSecurityPolicy(configuration: CTSecurityConfiguration(), baseURL: URL(string: "https://chat.example.com"))
    }

    private func handle(host: String = "chat.example.com", method: String = NSURLAuthenticationMethodServerTrust,
                        policy: CTSecurityPolicy?, pin: Data?, base: String = "https://chat.example.com",
                        expected: URLSession.AuthChallengeDisposition) -> [CTChatError] {
        let space = URLProtectionSpace(host: host, port: 443, protocol: "https", realm: nil,
                                       authenticationMethod: method)
        XCTAssertNil(space.serverTrust)
        let challenge = URLAuthenticationChallenge(protectionSpace: space, proposedCredential: nil,
                                                  previousFailureCount: 0, failureResponse: nil,
                                                  error: nil, sender: ChallengeSender())
        let completed = expectation(description: "Challenge завершён один раз")
        completed.assertForOverFulfill = true
        var errors: [CTChatError] = []
        CTTrustEvaluator.handle(challenge, policy: policy, legacyCertificate: pin, legacyBaseURL: base,
                                reportError: { errors.append($0) }) { disposition, credential in
            XCTAssertEqual(disposition, expected)
            XCTAssertNil(credential)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2)
        return errors
    }
}

private final class ChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) { XCTFail("Ожидался completion") }
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) { XCTFail("Ожидался completion") }
    func cancel(_ challenge: URLAuthenticationChallenge) { XCTFail("Ожидался completion") }
}
