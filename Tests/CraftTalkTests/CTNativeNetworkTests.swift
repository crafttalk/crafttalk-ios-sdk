import XCTest
import WebKit
@testable import CraftTalk

final class CTNativeNetworkTests: XCTestCase {
    private var fixture: CTHTTPSFixture!
    private var directory: URL!
    private var manager: CTNetworkManager!
    private let payload = Data([0, 255, 1, 2, 3, 128])

    override func setUpWithError() throws {
        fixture = try CTHTTPSFixture(test: self)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 12
        manager = CTNetworkManager(configuration: configuration, temporaryDirectory: directory)
        manager.securityPolicy = try fixture.policy()
    }

    override func tearDownWithError() throws {
        if let manager = manager {
            let stopped = expectation(description: "Нативная сессия остановлена")
            manager.invalidate { stopped.fulfill() }
            wait(for: [stopped], timeout: 5)
        }
        manager = nil
        fixture = nil
        if let directory = directory { try FileManager.default.removeItem(at: directory) }
    }

    func testGETRedirectStatusesPreserveOneRequestPerHop() throws {
        for code in [301, 302, 303, 307, 308] {
            let first = "get-\(code)", last = "file-\(code)"
            try fixture.configure([first: redirect(code, to: fixture.url(last)), last: CTHTTPSFixture.response(payload)])
            XCTAssertEqual(try bytes(download(first)), payload)
            let records = try fixture.requests().filter { $0.route == first || $0.route == last }
            XCTAssertEqual(records.map { $0.route }, [first, last])
            XCTAssertEqual(records.map { $0.method }, ["GET", "GET"])
            XCTAssertTrue(records.allSatisfy { $0.data.isEmpty })
        }
    }

    func testPOSTRedirectStatusesHaveExpectedMethodAndBodyOnServer() throws {
        for code in [301, 302, 303, 307, 308] {
            let first = "post-\(code)", last = "file-\(code)"
            try fixture.configure([first: redirect(code, to: fixture.url(last)), last: CTHTTPSFixture.response(payload)])
            var request = URLRequest(url: fixture.url(first))
            request.httpMethod = "POST"
            request.httpBody = Data("synthetic=body".utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            XCTAssertEqual(try bytes(download(request)), payload)
            let records = try fixture.requests().filter { $0.route == first || $0.route == last }
            XCTAssertEqual(records.count, 2)
            XCTAssertEqual(records.first?.method, "POST")
            XCTAssertEqual(records.first?.data, request.httpBody)
            XCTAssertEqual(records.last?.method, code >= 307 ? "POST" : "GET")
            XCTAssertEqual(records.last?.data, code >= 307 ? request.httpBody : Data())
        }
    }

    func testEveryRedirectHopIsCheckedBeforeForbiddenHostRequest() throws {
        manager.securityPolicy = try fixture.policy(allowed: [])
        try fixture.configure([
            "first": redirect(302, to: fixture.url("second", profile: "renewed")),
            "second": redirect(307, to: fixture.url("blocked", host: "127.0.0.1")),
            "blocked": CTHTTPSFixture.response(payload)
        ])
        let error = try failure(download("first"))
        XCTAssertEqual(error.stage, .navigation)
        XCTAssertEqual(error.code, 5)
        XCTAssertEqual(error.host, "127.0.0.1")
        XCTAssertEqual(try fixture.requests().map { $0.route }, ["first", "second"])
        try assertNoFiles()
    }

    func testRedirectToHTTPIsRejectedBeforeInsecureRequest() throws {
        try fixture.configure(["first": redirect(302, to: fixture.url("insecure", profile: "http")), "insecure": CTHTTPSFixture.response(payload)])
        XCTAssertEqual(try failure(download("first")).code, 5)
        XCTAssertEqual(try fixture.requests().map { $0.route }, ["first"])
        try assertNoFiles()
    }

    func testRedirectLoopTerminatesAndAllowsImmediateRetry() throws {
        try fixture.configure(["loop": redirect(302, to: fixture.url("loop")), "retry": CTHTTPSFixture.response(payload)])
        let error = try failure(download("loop"))
        XCTAssertEqual(error.domain, NSURLErrorDomain)
        XCTAssertEqual(error.code, NSURLErrorHTTPTooManyRedirects)
        let requests = try fixture.requests()
        XCTAssertGreaterThan(requests.count, 1)
        XCTAssertLessThan(requests.count, 25)
        try assertNoFiles()
        XCTAssertEqual(try bytes(download("retry")), payload)
    }

    func testCookiesFromWebKitStoreAreSelectedByDomainAndPath() throws {
        let route = "allowed/file"
        try fixture.configure([route: CTHTTPSFixture.response(payload)])
        let store = WKWebsiteDataStore.nonPersistent().httpCookieStore
        let cookies = try [cookie("session", value: "webview", domain: "localhost", path: "/case/\(fixture.identifier)/allowed"),
                           cookie("otherPath", value: "hidden", domain: "localhost", path: "/other"),
                           cookie("otherHost", value: "hidden", domain: "127.0.0.1", path: "/")]
        for cookie in cookies {
            let stored = expectation(description: "Cookie записана в WKHTTPCookieStore")
            store.setCookie(cookie) { stored.fulfill() }
            wait(for: [stored], timeout: 5)
        }
        var webCookies: [HTTPCookie] = []
        let read = expectation(description: "Cookies прочитаны из WebKit")
        store.getAllCookies { webCookies = $0; read.fulfill() }
        wait(for: [read], timeout: 5)
        XCTAssertEqual(webCookies.count, 3)
        var request = URLRequest(url: fixture.url(route))
        request.setValue("injected=must-not-leak", forHTTPHeaderField: "Cookie")
        XCTAssertEqual(try bytes(download(request, cookies: webCookies)), payload)
        XCTAssertEqual(try fixture.requests().last?.headers["cookie"], "session=webview")
    }

    func testSetCookieOnRedirectIsSentOnlyToMatchingPath() throws {
        let path = "/case/\(fixture.identifier)/allowed"
        try fixture.configure([
            "start": redirect(302, to: fixture.url("allowed/next"), headers: ["Set-Cookie": "server=value; Path=\(path); Secure; HttpOnly"]),
            "allowed/next": redirect(302, to: fixture.url("outside/file")),
            "outside/file": CTHTTPSFixture.response(payload)
        ])
        XCTAssertEqual(try bytes(download(URLRequest(url: fixture.url("start")), cookies: [])), payload)
        let requests = try fixture.requests()
        XCTAssertEqual(requests.count, 3)
        XCTAssertNil(requests[0].headers["cookie"])
        XCTAssertEqual(requests[1].headers["cookie"], "server=value")
        XCTAssertNil(requests[2].headers["cookie"])
    }

    func testCrossHostPOSTRedirectPreservesBodyWithoutLeakingCredentials() throws {
        try fixture.configure([
            "start": redirect(307, to: fixture.url("final", host: "127.0.0.1"), headers: ["Set-Cookie": "fromSource=private; Path=/; Secure"]),
            "final": CTHTTPSFixture.response(payload)
        ])
        var request = URLRequest(url: fixture.url("start"))
        request.httpMethod = "POST"
        request.httpBody = Data("one-use-post".utf8)
        request.setValue("Bearer synthetic-token", forHTTPHeaderField: "Authorization")
        request.setValue("source=manually-copied", forHTTPHeaderField: "Cookie")
        let cookies = try [cookie("source", value: "private", domain: "localhost", path: "/"),
                           cookie("target", value: "allowed", domain: "127.0.0.1", path: "/")]
        XCTAssertEqual(try bytes(download(request, cookies: cookies)), payload)
        let requests = try fixture.requests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].headers["authorization"], "Bearer synthetic-token")
        XCTAssertEqual(requests[0].headers["cookie"], "source=private")
        XCTAssertNil(requests[1].headers["authorization"])
        XCTAssertEqual(requests[1].headers["cookie"], "target=allowed")
        XCTAssertEqual(requests[1].method, "POST")
        XCTAssertEqual(requests[1].data, request.httpBody)
    }

    func testCrossHostResponseCookieSurvivesWebViewMainDocumentURL() throws {
        try fixture.configure([
            "start": redirect(302, to: fixture.url("middle", host: "127.0.0.1")),
            "middle": redirect(302, to: fixture.url("final", host: "127.0.0.1"),
                               headers: ["Set-Cookie": "targetSession=value; Path=/; Secure; HttpOnly"]),
            "final": CTHTTPSFixture.response(payload)
        ])
        var request = URLRequest(url: fixture.url("start"))
        request.mainDocumentURL = fixture.url("chat-page")
        XCTAssertEqual(try bytes(download(request, cookies: [])), payload)
        let requests = try fixture.requests()
        XCTAssertEqual(requests.map { $0.route }, ["start", "middle", "final"])
        XCTAssertNil(requests[0].headers["cookie"])
        XCTAssertNil(requests[1].headers["cookie"])
        XCTAssertEqual(requests[2].headers["cookie"], "targetSession=value")
    }

    func testEmptySuccessfulResponseCreatesEmptyFile() throws {
        try fixture.configure(["empty": CTHTTPSFixture.response(Data(), status: 204)])
        XCTAssertEqual(try bytes(download("empty")), Data())
        XCTAssertEqual(try fixture.requests().count, 1)
    }

    func testHTTPFailuresHaveStatusAndDoNotCreateFiles() throws {
        for status in [400, 404, 500, 503] {
            try fixture.configure(["error": CTHTTPSFixture.response(Data("synthetic-error-body".utf8), status: status)])
            let error = try failure(download("error"))
            XCTAssertEqual(error.stage, .download)
            XCTAssertEqual(error.domain, "HTTP")
            XCTAssertEqual(error.code, status)
            XCTAssertFalse(error.localizedDescription.contains("synthetic-error-body"))
            try assertNoFiles()
        }
    }

    func testTruncatedResponseFailsWithoutPartialFileAndCanRetry() throws {
        var truncated = CTHTTPSFixture.response(payload)
        truncated["truncate"] = true
        try fixture.configure(["broken": truncated, "retry": CTHTTPSFixture.response(payload)])
        let error = try failure(download("broken"))
        XCTAssertEqual(error.stage, .download)
        XCTAssertEqual(error.domain, NSURLErrorDomain)
        XCTAssertEqual(error.code, NSURLErrorNetworkConnectionLost)
        try assertNoFiles()
        XCTAssertEqual(try bytes(download("retry")), payload)
    }

    func testConnectionDropFailsWithoutFile() throws {
        try fixture.configure(["drop": ["disconnect": true]])
        let error = try failure(download("drop"))
        XCTAssertEqual(error.stage, .download)
        XCTAssertEqual(error.domain, NSURLErrorDomain)
        XCTAssertEqual(error.code, NSURLErrorNetworkConnectionLost)
        try assertNoFiles()
    }

    func testDelayedResponseTimesOutAndDoesNotLeaveFile() throws {
        var held = CTHTTPSFixture.response(payload)
        held["hold"] = true
        try fixture.configure(["slow": held])
        let error = try failure(download("slow"))
        try fixture.release("slow")
        XCTAssertEqual(error.code, NSURLErrorTimedOut)
        XCTAssertEqual(error.domain, NSURLErrorDomain)
        try assertNoFiles()
    }

    func testSecondDownloadIsRejectedWhileFirstIsHeldByServer() throws {
        var held = CTHTTPSFixture.response(payload)
        held["hold"] = true
        try fixture.configure(["first": held, "second": CTHTTPSFixture.response(payload)])
        let first = expectation(description: "Первая загрузка завершена")
        manager.loadDocumentFrom(url: fixture.url("first")) { result in
            XCTAssertEqual(try? self.bytes(result), self.payload)
            first.fulfill()
        }
        XCTAssertEqual(try fixture.requests(waitFor: "first").map { $0.route }, ["first"])
        XCTAssertEqual(try failure(download("second")).code, 6)
        XCTAssertEqual(try fixture.requests().map { $0.route }, ["first"])
        try fixture.release("first")
        wait(for: [first], timeout: 5)
    }

    func testPushAndDownloadUseSeparateRoutesAndBodies() throws {
        var held = CTHTTPSFixture.response(payload)
        held["hold"] = true
        let push = "webchat/channel/set-user-subscription"
        try fixture.configure(["file": held, push: CTHTTPSFixture.response(Data("PUSH-BODY-MUST-NOT-BE-IN-FILE".utf8))])
        let done = expectation(description: "Файл получен отдельно от push")
        manager.loadDocumentFrom(url: fixture.url("file")) { result in
            XCTAssertEqual(try? self.bytes(result), self.payload)
            done.fulfill()
        }
        _ = try fixture.requests(waitFor: "file")
        manager.set(baseURL: String(fixture.url("").absoluteString.dropLast()), namespace: "channel")
        manager.registerFCMToken("synthetic-token", uuid: "synthetic-visitor")
        let requests = try fixture.requests(waitFor: push)
        XCTAssertEqual(requests.map { $0.route }, ["file", push])
        let body = try XCTUnwrap(requests.last?.data)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? [String: String],
                       ["subscription": "synthetic-token", "uuid": "synthetic-visitor"])
        try fixture.release("file")
        wait(for: [done], timeout: 5)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 1)
    }

    func testPushHTTPFailureDoesNotFailConcurrentDownload() throws {
        var held = CTHTTPSFixture.response(payload)
        held["hold"] = true
        let push = "webchat/channel/set-user-subscription"
        try fixture.configure(["file": held, push: CTHTTPSFixture.response(status: 503)])
        let failed = expectation(description: "Ошибка push получена отдельно")
        manager.reportError = { error in
            XCTAssertEqual(error.stage, .pushRegistration)
            XCTAssertEqual(error.domain, "HTTP")
            XCTAssertEqual(error.code, 503)
            failed.fulfill()
        }
        let done = expectation(description: "Файл не отменён ошибкой push")
        manager.loadDocumentFrom(url: fixture.url("file")) { result in
            XCTAssertEqual(try? self.bytes(result), self.payload)
            done.fulfill()
        }
        _ = try fixture.requests(waitFor: "file")
        manager.set(baseURL: String(fixture.url("").absoluteString.dropLast()), namespace: "channel")
        manager.registerFCMToken("synthetic-token", uuid: "synthetic-visitor")
        wait(for: [failed], timeout: 5)
        try fixture.release("file")
        wait(for: [done], timeout: 5)
    }

    func testErrorCallbackCanStartImmediateRetry() throws {
        try fixture.configure(["failure": CTHTTPSFixture.response(status: 500), "retry": CTHTTPSFixture.response(payload)])
        let original = expectation(description: "Исходный callback получил ошибку")
        let retried = expectation(description: "Повтор из onError получил файл")
        let retryURL = fixture.url("retry")
        manager.reportError = { error in
            XCTAssertEqual(error.code, 500)
            self.manager.loadDocumentFrom(url: retryURL) { result in
                XCTAssertEqual(try? self.bytes(result), self.payload)
                retried.fulfill()
            }
        }
        manager.loadDocumentFrom(url: fixture.url("failure")) { result in
            XCTAssertEqual(try? self.failure(result).code, 500)
            original.fulfill()
        }
        wait(for: [original, retried], timeout: 10)
        manager.reportError = { _ in }
        XCTAssertEqual(try fixture.requests().map { $0.route }, ["failure", "retry"])
    }

    func testCompletionCanStartImmediateRetryAfterFailure() throws {
        try fixture.configure(["failure": CTHTTPSFixture.response(status: 404), "retry": CTHTTPSFixture.response(payload)])
        let retried = expectation(description: "Повтор из completion получил файл")
        let retryURL = fixture.url("retry")
        manager.loadDocumentFrom(url: fixture.url("failure")) { result in
            XCTAssertEqual(try? self.failure(result).code, 404)
            self.manager.loadDocumentFrom(url: retryURL) { result in
                XCTAssertEqual(try? self.bytes(result), self.payload)
                retried.fulfill()
            }
        }
        wait(for: [retried], timeout: 10)
        XCTAssertEqual(try fixture.requests().map { $0.route }, ["failure", "retry"])
    }

    func testWriteFailureLeavesNoPartialFilesAndAllowsRetry() throws {
        try FileManager.default.removeItem(at: directory)
        try Data("occupied".utf8).write(to: directory)
        try fixture.configure(["file": CTHTTPSFixture.response(payload)])
        let error = try failure(download("file"))
        XCTAssertEqual(error.stage, .download)
        XCTAssertEqual(error.domain, NSCocoaErrorDomain)
        XCTAssertEqual(try Data(contentsOf: directory), Data("occupied".utf8))
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        XCTAssertEqual(try bytes(download("file")), payload)
    }

    func testSameResponseFilenamesUseSeparateDirectoriesAndExactBytes() throws {
        try fixture.configure(["file": CTHTTPSFixture.response(payload, headers: ["Content-Disposition": "attachment; filename=\"same.pdf\""])])
        let request = URLRequest(url: fixture.url("file"))
        let first = try download(request, cookies: []).get(), second = try download(request, cookies: []).get()
        XCTAssertNotEqual(first.deletingLastPathComponent(), second.deletingLastPathComponent())
        XCTAssertEqual(first.lastPathComponent, "same.pdf")
        XCTAssertEqual(second.lastPathComponent, "same.pdf")
        for url in [first, second] {
            XCTAssertEqual(url.deletingLastPathComponent().deletingLastPathComponent(), directory)
            XCTAssertEqual(try Data(contentsOf: url), payload)
        }
    }

    func testWriteErrorAfterDirectoryCreationRemovesOwnedDirectory() throws {
        // Файловая система отклоняет basename длиннее NAME_MAX после создания каталога.
        let name = String(repeating: "a", count: 300)
        try fixture.configure([name: CTHTTPSFixture.response(payload), "retry": CTHTTPSFixture.response(payload)])
        let error = try failure(download(name))
        XCTAssertEqual(error.stage, .download)
        XCTAssertEqual(error.domain, NSCocoaErrorDomain)
        try assertNoFiles()
        XCTAssertEqual(try bytes(download("retry")), payload)
    }

    func testUnsafeOrEmptyResponseNamesRemainInsideOwnedDirectory() throws {
        for name in ["../report.pdf", "/", "..", "", "..\\\\report.pdf"] {
            try fixture.configure(["file": CTHTTPSFixture.response(payload, headers: ["Content-Disposition": "attachment; filename=\"\(name)\""])])
            let url = try download(URLRequest(url: fixture.url("file")), cookies: []).get()
            XCTAssertEqual(url.deletingLastPathComponent().deletingLastPathComponent(), directory)
            XCTAssertFalse(["", ".", "..", "/"].contains(url.lastPathComponent))
            XCTAssertEqual(try Data(contentsOf: url), payload)
        }
    }

    func testOneUseDownloadIsNotProbedOrReplayed() throws {
        var once = CTHTTPSFixture.response(payload)
        once["oneUse"] = true
        try fixture.configure(["ticket": once])
        XCTAssertEqual(try bytes(download("ticket")), payload)
        XCTAssertEqual(try fixture.requests().map { $0.method }, ["GET"])
        XCTAssertEqual(try fixture.requests().map { $0.route }, ["ticket"])
    }

    func testOneUsePOSTIsNotReplayed() throws {
        var once = CTHTTPSFixture.response(payload)
        once["oneUse"] = true
        try fixture.configure(["ticket": once])
        var request = URLRequest(url: fixture.url("ticket"))
        request.httpMethod = "POST"
        request.httpBody = Data("one-use-body".utf8)
        XCTAssertEqual(try bytes(download(request)), payload)
        let requests = try fixture.requests()
        XCTAssertEqual(requests.map { $0.method }, ["POST"])
        XCTAssertEqual(requests.first?.data, request.httpBody)
    }

    func testInvalidationCancelsActiveDownloadAndDoesNotCreateFile() throws {
        var held = CTHTTPSFixture.response(payload)
        held["hold"] = true
        try fixture.configure(["file": held])
        let cancelled = expectation(description: "Отмена завершает callback загрузки")
        manager.loadDocumentFrom(url: fixture.url("file")) { result in
            XCTAssertEqual(try? self.failure(result).code, NSURLErrorCancelled)
            cancelled.fulfill()
        }
        _ = try fixture.requests(waitFor: "file")
        manager.invalidate()
        wait(for: [cancelled], timeout: 5)
        try fixture.release("file")
        try assertNoFiles()
    }

    private func redirect(_ status: Int, to url: URL, headers: [String: String] = [:]) -> [String: Any] {
        var fields = headers
        fields["Location"] = url.absoluteString
        return CTHTTPSFixture.response(status: status, headers: fields)
    }

    private func cookie(_ name: String, value: String, domain: String, path: String) throws -> HTTPCookie {
        try XCTUnwrap(HTTPCookie(properties: [.name: name, .value: value, .domain: domain, .path: path, .secure: "TRUE"]))
    }

    private func download(_ route: String) -> Result<URL, Error> { download(URLRequest(url: fixture.url(route))) }

    private func download(_ request: URLRequest, cookies: [HTTPCookie]? = nil) -> Result<URL, Error> {
        let done = expectation(description: "Нативная загрузка завершила callback")
        var result: Result<URL, Error>?
        manager.loadDocumentFrom(request: request, webCookies: cookies) {
            XCTAssertTrue(Thread.isMainThread)
            result = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 15)
        return result ?? .failure(URLError(.timedOut))
    }

    private func bytes(_ result: Result<URL, Error>) throws -> Data { try Data(contentsOf: result.get()) }

    private func failure(_ result: Result<URL, Error>) throws -> CTChatError {
        guard case .failure(let error) = result else { return try XCTUnwrap(nil as CTChatError?, "Ожидалась ошибка") }
        return try XCTUnwrap(error as? CTChatError)
    }

    private func assertNoFiles(file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [], file: file, line: line)
    }
}
