import XCTest
import WebKit
@testable import CraftTalk

final class CTNativeNetworkTests: XCTestCase {
    private var fixture: CTHTTPSFixture!
    private let chat = CTChat.shared
    private var manager: CTNetworkManager { chat.networkManager }
    private var originalErrorHandler: ((Error) -> Void)?
    private var existingDirectories: Set<URL> = []
    private var downloadedDirectories: Set<URL> = []
    private let payload = Data([0, 255, 1, 2, 3, 128])

    override func setUpWithError() throws {
        originalErrorHandler = chat.onError
        existingDirectories = try attachmentDirectories()
        fixture = try CTHTTPSFixture(test: self)
    }

    override func tearDownWithError() throws {
        chat.onError = originalErrorHandler
        for directory in downloadedDirectories { try FileManager.default.removeItem(at: directory) }
    }

    func testGETRedirectStatusesPreserveOneRequestPerHop() throws {
        for code in [301, 302, 303, 307, 308] {
            let first = "get-\(code)", last = "file-\(code)"
            try fixture.configure([first: redirect(code, to: fixture.url(last, profile: "system")), last: CTHTTPSFixture.response(payload)])
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
            try fixture.configure([first: redirect(code, to: fixture.url(last, profile: "system")), last: CTHTTPSFixture.response(payload)])
            var request = URLRequest(url: fixture.url(first, profile: "system"))
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

    func testRedirectLoopTerminatesAndAllowsImmediateRetry() throws {
        try fixture.configure(["loop": redirect(302, to: fixture.url("loop", profile: "system")), "retry": CTHTTPSFixture.response(payload)])
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
        var request = URLRequest(url: fixture.url(route, profile: "system"))
        request.setValue("injected=must-not-leak", forHTTPHeaderField: "Cookie")
        XCTAssertEqual(try bytes(download(request, cookies: webCookies)), payload)
        XCTAssertEqual(try fixture.requests().last?.headers["cookie"], "session=webview")
    }

    func testSetCookieOnRedirectIsSentOnlyToMatchingPath() throws {
        let path = "/case/\(fixture.identifier)/allowed"
        try fixture.configure([
            "start": redirect(302, to: fixture.url("allowed/next", profile: "system"), headers: ["Set-Cookie": "server=value; Path=\(path); Secure; HttpOnly"]),
            "allowed/next": redirect(302, to: fixture.url("outside/file", profile: "system")),
            "outside/file": CTHTTPSFixture.response(payload)
        ])
        XCTAssertEqual(try bytes(download(URLRequest(url: fixture.url("start", profile: "system")), cookies: [])), payload)
        let requests = try fixture.requests()
        XCTAssertEqual(requests.count, 3)
        XCTAssertNil(requests[0].headers["cookie"])
        XCTAssertEqual(requests[1].headers["cookie"], "server=value")
        XCTAssertNil(requests[2].headers["cookie"])
    }

    func testCrossHost307PreservesPOSTBodyAndSelectsCookiesForEachHost() throws {
        let source = fixture.url("submit", profile: "system")
        let target = fixture.url("document", profile: "system", host: "127.0.0.1")
        try fixture.configure([
            "submit": redirect(307, to: target),
            "document": CTHTTPSFixture.response(payload)
        ])
        let body = Data("format=pdf&document=synthetic".utf8)
        var request = URLRequest(url: source)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let path = "/case/\(fixture.identifier)/"
        let cookies = try [cookie("source", value: "one", domain: "localhost", path: path),
                           cookie("target", value: "two", domain: "127.0.0.1", path: path)]

        XCTAssertEqual(try bytes(download(request, cookies: cookies)), payload)
        let requests = try fixture.requests()
        XCTAssertEqual(requests.map { $0.route }, ["submit", "document"])
        XCTAssertEqual(requests.map { $0.method }, ["POST", "POST"])
        XCTAssertEqual(requests.map { $0.data }, [body, body])
        XCTAssertEqual(requests.map { $0.headers["cookie"] }, ["source=one", "target=two"])
    }

    func testCrossHostResponseCookieSurvivesWebViewMainDocumentURL() throws {
        try fixture.configure([
            "start": redirect(302, to: fixture.url("middle", profile: "system", host: "127.0.0.1")),
            "middle": redirect(302, to: fixture.url("final", profile: "system", host: "127.0.0.1"),
                               headers: ["Set-Cookie": "targetSession=value; Path=/; Secure; HttpOnly"]),
            "final": CTHTTPSFixture.response(payload)
        ])
        var request = URLRequest(url: fixture.url("start", profile: "system"))
        request.mainDocumentURL = fixture.url("chat-page", profile: "system")
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

    func testUnconfiguredNativeSessionUsesSystemTrust() throws {
        try fixture.configure(["file": CTHTTPSFixture.response(payload)])
        let error = try failure(download(URLRequest(url: fixture.url("file"))))
        XCTAssertEqual(error.stage, .tls)
        XCTAssertEqual(error.domain, NSURLErrorDomain)
        XCTAssertTrue((-1206 ... -1200).contains(error.code))
        XCTAssertTrue(try fixture.requests().isEmpty)
        try assertNoFiles()
        XCTAssertEqual(try bytes(download("file")), payload)
        XCTAssertEqual(try fixture.requests().map { $0.route }, ["file"])
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

    func testMissingRequestURLReportsBadURLAndAllowsRetry() throws {
        try fixture.configure(["retry": CTHTTPSFixture.response(payload)])
        let reported = expectation(description: "SDK сообщает об отсутствующем URL")
        reported.assertForOverFulfill = true
        chat.onError = { error in
            XCTAssertTrue(Thread.isMainThread)
            let failure = error as? CTChatError
            XCTAssertEqual(failure?.stage, .download)
            XCTAssertEqual(failure?.domain, NSURLErrorDomain)
            XCTAssertEqual(failure?.code, NSURLErrorBadURL)
            XCTAssertNil(failure?.host)
            reported.fulfill()
        }
        var request = URLRequest(url: fixture.url("retry", profile: "system"))
        request.url = nil
        let error = try failure(download(request))
        wait(for: [reported], timeout: 2)
        XCTAssertEqual(error.stage, .download)
        XCTAssertEqual(error.domain, NSURLErrorDomain)
        XCTAssertEqual(error.code, NSURLErrorBadURL)
        XCTAssertNil(error.host)
        XCTAssertTrue(try fixture.requests().isEmpty)
        try assertNoFiles()
        XCTAssertEqual(try bytes(download("retry")), payload)
        XCTAssertEqual(try fixture.requests().map { $0.route }, ["retry"])
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
        // Короткий таймаут нужен только сценарию с намеренно удерживаемым ответом.
        let request = URLRequest(url: fixture.url("slow", profile: "system"), timeoutInterval: 3)
        let error = try failure(download(request))
        try fixture.release("slow")
        XCTAssertEqual(error.code, NSURLErrorTimedOut)
        XCTAssertEqual(error.domain, NSURLErrorDomain)
        try assertNoFiles()
    }

    func testSecondDownloadIsRejectedWhileFirstIsHeldByServer() throws {
        var held = CTHTTPSFixture.response(payload)
        held["hold"] = true
        try fixture.configure(["first": held, "second": CTHTTPSFixture.response(payload)])
        defer { try? fixture.release("first") }
        let first = expectation(description: "Первая загрузка завершена")
        manager.loadDocumentFrom(url: fixture.url("first", profile: "system")) { result in
            XCTAssertEqual(try? self.bytes(result), self.payload)
            first.fulfill()
        }
        XCTAssertEqual(try fixture.requests(waitFor: "first").map { $0.route }, ["first"])
        XCTAssertEqual(try failure(download("second")).code, 6)
        XCTAssertEqual(try fixture.requests().map { $0.route }, ["first"])
        try fixture.release("first")
        wait(for: [first], timeout: 5)
    }

    func testPushHTTPFailureDoesNotFailConcurrentDownload() throws {
        var held = CTHTTPSFixture.response(payload)
        held["hold"] = true
        let push = "webchat/channel/set-user-subscription"
        try fixture.configure(["file": held, push: CTHTTPSFixture.response(status: 503)])
        defer { try? fixture.release("file") }
        let failed = expectation(description: "Ошибка push получена отдельно")
        chat.onError = { reported in
            guard let error = reported as? CTChatError else { return XCTFail("Ожидалась CTChatError") }
            XCTAssertEqual(error.stage, .pushRegistration)
            XCTAssertEqual(error.domain, "HTTP")
            XCTAssertEqual(error.code, 503)
            failed.fulfill()
        }
        let done = expectation(description: "Файл не отменён ошибкой push")
        manager.loadDocumentFrom(url: fixture.url("file", profile: "system")) { result in
            XCTAssertEqual(try? self.bytes(result), self.payload)
            done.fulfill()
        }
        _ = try fixture.requests(waitFor: "file")
        manager.set(baseURL: String(fixture.url("", profile: "system").absoluteString.dropLast()), namespace: "channel")
        manager.registerFCMToken("synthetic-token", uuid: "synthetic-visitor")
        wait(for: [failed], timeout: 5)
        let requests = try fixture.requests()
        XCTAssertEqual(requests.map { $0.route }, ["file", push])
        XCTAssertEqual(requests.map { $0.method }, ["GET", "POST"])
        let body = try XCTUnwrap(requests.last?.data)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? [String: String],
                       ["subscription": "synthetic-token", "uuid": "synthetic-visitor"])
        try fixture.release("file")
        wait(for: [done], timeout: 5)
    }

    func testScheduledPushesKeepTheirOwnTokenAndVisitor() throws {
        let push = "webchat/channel/set-user-subscription"
        try fixture.configure([push: CTHTTPSFixture.response(status: 503)])
        manager.set(baseURL: String(fixture.url("", profile: "system").absoluteString.dropLast()), namespace: "channel")
        let previousVisitor = chat.visitor
        defer {
            chat.saveFCMToken("")
            chat.visitor = previousVisitor
        }

        // У успешного push нет callback. Статус 503 даёт наблюдаемое завершение каждого запроса.
        let completed = expectation(description: "Три отложенных push получили ответ сервера")
        completed.expectedFulfillmentCount = 3
        completed.assertForOverFulfill = true
        chat.onError = { error in
            XCTAssertTrue(Thread.isMainThread)
            let failure = error as? CTChatError
            XCTAssertEqual(failure?.stage, .pushRegistration)
            XCTAssertEqual(failure?.domain, "HTTP")
            XCTAssertEqual(failure?.code, 503)
            completed.fulfill()
        }
        chat.registerVisitor(CTVisitor(uuid: "first-visitor", hash: "fixture-hash"))
        chat.saveFCMToken("first-token")
        chat.registerPushNotifications()
        chat.registerVisitor(CTVisitor(uuid: "second-visitor", hash: "fixture-hash"))
        chat.saveFCMToken("second-token")
        chat.registerPushNotifications()
        chat.registerPushNotifications()
        wait(for: [completed], timeout: 10)

        let requests = try fixture.requests()
        XCTAssertEqual(requests.map { $0.route }, [push, push, push])
        XCTAssertEqual(requests.map { $0.method }, ["POST", "POST", "POST"])
        let bodies = try requests.map { try JSONDecoder().decode([String: String].self, from: $0.data) }
        XCTAssertEqual(bodies.filter { $0 == ["subscription": "first-token", "uuid": "first-visitor"] }.count, 1)
        XCTAssertEqual(bodies.filter { $0 == ["subscription": "second-token", "uuid": "second-visitor"] }.count, 2)
    }

    func testErrorCallbackCanStartImmediateRetry() throws {
        try fixture.configure(["failure": CTHTTPSFixture.response(status: 500), "retry": CTHTTPSFixture.response(payload)])
        let original = expectation(description: "Исходный callback получил ошибку")
        let retried = expectation(description: "Повтор из onError получил файл")
        let retryURL = fixture.url("retry", profile: "system")
        chat.onError = { reported in
            guard let error = reported as? CTChatError else { return XCTFail("Ожидалась CTChatError") }
            XCTAssertEqual(error.code, 500)
            self.manager.loadDocumentFrom(url: retryURL) { result in
                XCTAssertEqual(try? self.bytes(result), self.payload)
                retried.fulfill()
            }
        }
        manager.loadDocumentFrom(url: fixture.url("failure", profile: "system")) { result in
            XCTAssertEqual(try? self.failure(result).code, 500)
            original.fulfill()
        }
        wait(for: [original, retried], timeout: 10)
        chat.onError = originalErrorHandler
        XCTAssertEqual(try fixture.requests().map { $0.route }, ["failure", "retry"])
    }

    func testCompletionCanStartImmediateRetryAfterFailure() throws {
        try fixture.configure(["failure": CTHTTPSFixture.response(status: 404), "retry": CTHTTPSFixture.response(payload)])
        let retried = expectation(description: "Повтор из completion получил файл")
        let retryURL = fixture.url("retry", profile: "system")
        manager.loadDocumentFrom(url: fixture.url("failure", profile: "system")) { result in
            XCTAssertEqual(try? self.failure(result).code, 404)
            self.manager.loadDocumentFrom(url: retryURL) { result in
                XCTAssertEqual(try? self.bytes(result), self.payload)
                retried.fulfill()
            }
        }
        wait(for: [retried], timeout: 10)
        XCTAssertEqual(try fixture.requests().map { $0.route }, ["failure", "retry"])
    }

    func testSameResponseFilenamesUseSeparateDirectoriesAndExactBytes() throws {
        try fixture.configure(["file": CTHTTPSFixture.response(payload, headers: ["Content-Disposition": "attachment; filename=\"same.pdf\""])])
        let request = URLRequest(url: fixture.url("file", profile: "system"))
        let first = try download(request, cookies: []).get(), second = try download(request, cookies: []).get()
        XCTAssertNotEqual(first.deletingLastPathComponent(), second.deletingLastPathComponent())
        XCTAssertEqual(first.lastPathComponent, "same.pdf")
        XCTAssertEqual(second.lastPathComponent, "same.pdf")
        for url in [first, second] {
            XCTAssertEqual(url.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL.path,
                           FileManager.default.temporaryDirectory.standardizedFileURL.path)
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
        var request = URLRequest(url: fixture.url("ticket", profile: "system"))
        request.httpMethod = "POST"
        request.httpBody = Data("one-use-body".utf8)
        XCTAssertEqual(try bytes(download(request)), payload)
        let requests = try fixture.requests()
        XCTAssertEqual(requests.map { $0.method }, ["POST"])
        XCTAssertEqual(requests.first?.data, request.httpBody)
    }

    private func redirect(_ status: Int, to url: URL, headers: [String: String] = [:]) -> [String: Any] {
        var fields = headers
        fields["Location"] = url.absoluteString
        return CTHTTPSFixture.response(status: status, headers: fields)
    }

    private func cookie(_ name: String, value: String, domain: String, path: String) throws -> HTTPCookie {
        try XCTUnwrap(HTTPCookie(properties: [.name: name, .value: value, .domain: domain, .path: path, .secure: "TRUE"]))
    }

    private func download(_ route: String) -> Result<URL, Error> { download(URLRequest(url: fixture.url(route, profile: "system"))) }

    private func download(_ request: URLRequest, cookies: [HTTPCookie]? = nil) -> Result<URL, Error> {
        let done = expectation(description: "Нативная загрузка завершила callback")
        done.assertForOverFulfill = true
        var result: Result<URL, Error>?
        manager.loadDocumentFrom(request: request, webCookies: cookies) {
            XCTAssertTrue(Thread.isMainThread)
            result = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 15)
        return trackFile(result ?? .failure(URLError(.timedOut)))
    }

    private func bytes(_ result: Result<URL, Error>) throws -> Data {
        try Data(contentsOf: trackFile(result).get())
    }

    private func trackFile(_ result: Result<URL, Error>) -> Result<URL, Error> {
        if case .success(let file) = result {
            let directory = file.deletingLastPathComponent().standardizedFileURL
            if directory.deletingLastPathComponent().path == FileManager.default.temporaryDirectory.standardizedFileURL.path,
               !existingDirectories.contains(directory), UUID(uuidString: directory.lastPathComponent) != nil {
                downloadedDirectories.insert(directory)
            }
        }
        return result
    }

    private func failure(_ result: Result<URL, Error>) throws -> CTChatError {
        guard case .failure(let error) = result else { return try XCTUnwrap(nil as CTChatError?, "Ожидалась ошибка") }
        return try XCTUnwrap(error as? CTChatError)
    }

    private func assertNoFiles(file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try attachmentDirectories().subtracting(existingDirectories), [], file: file, line: line)
    }

    private func attachmentDirectories() throws -> Set<URL> {
        let temporary = FileManager.default.temporaryDirectory
        let entries = try FileManager.default.contentsOfDirectory(at: temporary, includingPropertiesForKeys: [.isDirectoryKey])
        return Set(try entries.filter {
            try UUID(uuidString: $0.lastPathComponent) != nil && $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        }.map { $0.standardizedFileURL })
    }
}
