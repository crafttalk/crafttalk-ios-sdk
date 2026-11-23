import XCTest
import Security
@testable import CraftTalk

// Управление стендом идёт по отдельному HTTPS-порту с системным тестовым CA.
final class CTHTTPSFixture {
    struct Configuration: Decodable {
        let ports: [String: Int]
        let verifyTime: TimeInterval
    }

    struct Request: Decodable {
        let route: String
        let method: String
        let host: String
        let headers: [String: String]
        let body: String
        var data: Data { Data(base64Encoded: body)! }
    }

    let configuration: Configuration
    let identifier = UUID().uuidString
    private unowned let test: XCTestCase
    private let controlSession = URLSession(configuration: .ephemeral)
    private let resources: URL

    init(test: XCTestCase) throws {
        self.test = test
        resources = try XCTUnwrap(Bundle.module.url(forResource: "config", withExtension: "json", subdirectory: "Fixtures/Runtime"),
                                  "Запустите bash scripts/ci.sh test-spm: нужны HTTPS-стенд и отдельный симулятор")
            .deletingLastPathComponent()
        configuration = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: resources.appendingPathComponent("config.json")))
    }

    func der(_ name: String) throws -> Data {
        try Data(contentsOf: resources.appendingPathComponent(name + ".der"))
    }

    func certificate(_ name: String) throws -> SecCertificate {
        try XCTUnwrap(SecCertificateCreateWithData(nil, der(name) as CFData))
    }

    func url(_ route: String, profile: String = "valid", host: String = "localhost") -> URL {
        URL(string: "\(profile == "http" ? "http" : "https")://\(host):\(configuration.ports[profile]!)/case/\(identifier)/\(route)")!
    }

    func policy(root: String = "root", hosts: [String] = ["localhost", "127.0.0.1"], allowed: Set<String> = ["127.0.0.1"]) throws -> CTSecurityPolicy {
        let roots = try Dictionary(uniqueKeysWithValues: hosts.map { ($0, [try der(root)]) })
        return try CTSecurityPolicy(configuration: CTSecurityConfiguration(trustedRootsByHost: roots, allowedRedirectHosts: allowed), baseURL: url(""))
    }

    func configure(_ routes: [String: [String: Any]]) throws {
        _ = try control(["routes": routes])
    }

    func requests(waitFor route: String? = nil) throws -> [Request] {
        try control(route.map { ["wait": $0] } ?? [:])
    }

    func release(_ route: String) throws { _ = try control(["release": route]) }

    func requestWithTrustEvaluator(profile: String, host: String = "localhost", policy: CTSecurityPolicy?,
                                   legacyCertificate: Data? = nil, legacyBaseURL: String? = nil) throws -> Result<Data, Error> {
        let stopped = test.expectation(description: "Проверочная TLS-сессия остановлена")
        let probe = CTTrustChallengeProbe(policy: policy, pin: legacyCertificate, base: legacyBaseURL,
                                          stopped: { stopped.fulfill() })
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: configuration, delegate: probe, delegateQueue: nil)
        let completed = test.expectation(description: "Настоящее TLS-соединение: " + profile)
        var result: Result<Data, Error>?
        session.dataTask(with: url("file", profile: profile, host: host)) { data, response, error in
            if let error = error {
                result = .failure(probe.failure ?? error)
            } else if (response as? HTTPURLResponse)?.statusCode == 200, let data = data {
                result = .success(data)
            } else {
                result = .failure(URLError(.badServerResponse))
            }
            completed.fulfill()
        }.resume()
        test.wait(for: [completed], timeout: 15)
        session.invalidateAndCancel()
        test.wait(for: [stopped], timeout: 5)
        return try XCTUnwrap(result)
    }

    static func response(_ data: Data = Data("attachment".utf8), status: Int = 200, headers: [String: String] = [:]) -> [String: Any] {
        ["body": data.base64EncodedString(), "status": status, "headers": headers]
    }

    private func control(_ command: [String: Any]) throws -> [Request] {
        let url = URL(string: "https://127.0.0.1:\(configuration.ports["system"]!)/control/\(identifier)")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: command)
        let completed = test.expectation(description: "Управление локальным HTTPS-стендом")
        var result: Result<Data, Error>?
        controlSession.dataTask(with: request) { data, response, error in
            if let error = error { result = .failure(error) }
            else if (response as? HTTPURLResponse)?.statusCode == 200, let data = data { result = .success(data) }
            else { result = .failure(URLError(.badServerResponse)) }
            completed.fulfill()
        }.resume()
        test.wait(for: [completed], timeout: 20)
        return try JSONDecoder().decode([Request].self, from: XCTUnwrap(result).get())
    }

    deinit { controlSession.invalidateAndCancel() }
}

// Challenge приходит из реального TLS-соединения. Оценку доверия выполняет SDK.
private final class CTTrustChallengeProbe: NSObject, URLSessionDelegate {
    private let policy: CTSecurityPolicy?
    private let pin: Data?
    private let base: String?
    private let stopped: () -> Void
    private(set) var failure: CTChatError?

    init(policy: CTSecurityPolicy?, pin: Data?, base: String?, stopped: @escaping () -> Void) {
        self.policy = policy
        self.pin = pin
        self.base = base
        self.stopped = stopped
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        CTTrustEvaluator.handle(challenge, policy: policy, legacyCertificate: pin, legacyBaseURL: base,
                                reportError: { self.failure = $0 }, completion: completionHandler)
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) { stopped() }
}
