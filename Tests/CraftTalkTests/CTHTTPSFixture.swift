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
    private let test: XCTestCase
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
