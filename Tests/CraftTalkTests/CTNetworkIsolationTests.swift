import XCTest
@testable import CraftTalk

final class CTNetworkIsolationTests: XCTestCase {
    func testPushDataCallbackCannotAppendToActiveDownload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let started = expectation(description: "Оба настоящих task остановлены в тестовом транспорте")
        started.expectedFulfillmentCount = 2
        let lock = NSLock()
        var connections: [String: URLProtocol] = [:]
        let transport = CTTestTransport { connection in
            lock.lock()
            connections[connection.request.url!.lastPathComponent] = connection
            lock.unlock()
            started.fulfill()
        }
        let manager = CTNetworkManager(configuration: transport.configuration, temporaryDirectory: directory)
        defer { stop(manager) }
        manager.set(baseURL: "https://chat.example.com", namespace: "channel")
        let finished = expectation(description: "В файл попали только обе части скачивания")
        manager.loadDocumentFrom(url: URL(string: "https://chat.example.com/file")!) { result in
            do { XCTAssertEqual(try Data(contentsOf: result.get()), Data([1, 2, 3, 4])) }
            catch { XCTFail("Ошибка загрузки: \(error)") }
            finished.fulfill()
        }
        manager.registerFCMToken("synthetic-token", uuid: "synthetic-visitor")
        wait(for: [started], timeout: 5)
        lock.lock()
        let captured = connections
        lock.unlock()
        let file = try XCTUnwrap(captured["file"])
        let push = try XCTUnwrap(captured["set-user-subscription"])
        let fileTask = try XCTUnwrap(file.task as? URLSessionDataTask)
        let pushTask = try XCTUnwrap(push.task as? URLSessionDataTask)
        XCTAssertNotEqual(fileTask.taskIdentifier, pushTask.taskIdentifier)

        // Компонентная проверка порядка callbacks: транспорт ещё не завершил ни один task.
        // Синхронные вызовы проверяют SDK, а доставку событий URLSession покрывает HTTPS-набор.
        manager.urlSession(.shared, dataTask: fileTask, didReceive: Data([1, 2]))
        manager.urlSession(.shared, dataTask: pushTask, didReceive: Data("PUSH-MUST-NOT-ENTER-FILE".utf8))
        for connection in [push, file] {
            let response = try XCTUnwrap(HTTPURLResponse(url: connection.request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil))
            connection.client?.urlProtocol(connection, didReceive: response, cacheStoragePolicy: .notAllowed)
            if connection === file { connection.client?.urlProtocol(connection, didLoad: Data([3, 4])) }
            connection.client?.urlProtocolDidFinishLoading(connection)
        }
        wait(for: [finished], timeout: 5)
    }

    func testMissingRequestURLFailsWithoutTransportOrFilesAndAllowsRetry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = CTTestTransport()
        let manager = CTNetworkManager(configuration: transport.configuration, temporaryDirectory: directory)
        defer { stop(manager) }
        var reported: [CTChatError] = []
        manager.reportError = { reported.append($0) }
        var request = URLRequest(url: try XCTUnwrap(URL(string: "https://chat.example.com/file.txt")))
        request.url = nil
        let rejected = expectation(description: "Запрос без URL отклонён")
        rejected.assertForOverFulfill = true
        manager.loadDocumentFrom(request: request, webCookies: nil) { result in
            XCTAssertTrue(Thread.isMainThread)
            guard case .failure(let failure) = result else {
                XCTFail("Ожидался отказ запроса без URL")
                rejected.fulfill()
                return
            }
            let error = failure as? CTChatError
            XCTAssertEqual(error?.stage, .download)
            XCTAssertEqual(error?.code, NSURLErrorBadURL)
            XCTAssertEqual(error?.domain, NSURLErrorDomain)
            XCTAssertNil(error?.host)
            rejected.fulfill()
        }
        wait(for: [rejected], timeout: 2)
        XCTAssertEqual(reported.count, 1)
        XCTAssertEqual(reported.first?.stage, .download)
        XCTAssertEqual(reported.first?.code, NSURLErrorBadURL)
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])

        let retried = expectation(description: "Следующий запрос выполнен")
        manager.loadDocumentFrom(url: try XCTUnwrap(URL(string: "https://chat.example.com/file.txt"))) { result in
            do { XCTAssertEqual(try Data(contentsOf: result.get()), Data("ok".utf8)) }
            catch { XCTFail("Повтор не завершён: \(error)") }
            retried.fulfill()
        }
        wait(for: [retried], timeout: 5)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(reported.count, 1)
    }

    func testPushToForbiddenHostIsReportedBeforeTransportAndAllowedPushStillWorks() throws {
        let transport = CTTestTransport()
        let manager = CTNetworkManager(configuration: transport.configuration)
        defer { stop(manager) }
        manager.securityPolicy = try CTSecurityPolicy(configuration: CTSecurityConfiguration(),
                                                      baseURL: URL(string: "https://chat.example.com"))
        manager.set(baseURL: "https://blocked.example.com/private", namespace: "channel")
        var errors: [CTChatError] = []
        manager.reportError = { errors.append($0) }
        manager.registerFCMToken("synthetic-token", uuid: "synthetic-visitor")
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertEqual(errors.count, 1)
        let error = try XCTUnwrap(errors.first)
        XCTAssertEqual(error.stage, .pushRegistration)
        XCTAssertEqual(error.host, "blocked.example.com")
        XCTAssertEqual(error.code, 5)
        XCTAssertEqual(error.domain, "CTChat")
        for secret in ["private", "synthetic-token", "synthetic-visitor"] {
            XCTAssertFalse(error.localizedDescription.contains(secret))
        }

        let sent = expectation(description: "Разрешённый push отправлен после отказа")
        transport.onRequest = { _ in sent.fulfill() }
        manager.set(baseURL: "https://chat.example.com", namespace: "channel")
        manager.registerFCMToken("synthetic-token", uuid: "synthetic-visitor")
        wait(for: [sent], timeout: 5)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.url?.host, "chat.example.com")
        XCTAssertEqual(errors.count, 1)
    }

    func testNetworkUsesOwningChatsPolicyAndErrorCallback() throws {
        let transport = CTTestTransport()
        let manager = CTNetworkManager(configuration: transport.configuration)
        let settings = ["CTChatBaseURL": "https://chat.example.com", "CTChatNamespace": "channel", "CTSalt": "salt"]
        let chat = CTChat(infoValue: { settings[$0] }, networkManager: manager)
        try chat.configure(security: CTSecurityConfiguration())
        let reported = expectation(description: "Ошибка принадлежит настроенному экземпляру")
        chat.onError = { error in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual((error as? CTChatError)?.host, "blocked.example.com")
            XCTAssertEqual((error as? CTChatError)?.stage, .download)
            reported.fulfill()
        }
        let completed = expectation(description: "Загрузка отклонена до транспорта")
        manager.loadDocumentFrom(url: try XCTUnwrap(URL(string: "https://blocked.example.com/private?token=synthetic"))) { result in
            guard case .failure(let error) = result else { return XCTFail("Ожидался отказ") }
            XCTAssertEqual((error as? CTChatError)?.code, 5)
            completed.fulfill()
        }
        wait(for: [reported, completed], timeout: 2)
        XCTAssertTrue(transport.requests.isEmpty)
        stop(manager)
    }

    func testInjectedFileDirectoryContainsOnlyThisDownloadsBytes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: nil)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = CTTestTransport()
        let manager = CTNetworkManager(configuration: transport.configuration, temporaryDirectory: directory)
        let completed = expectation(description: "Тестовый транспорт завершил загрузку")
        manager.loadDocumentFrom(url: try XCTUnwrap(URL(string: "https://chat.example.com/file.txt"))) { result in
            do {
                let url = try result.get()
                XCTAssertEqual(url.deletingLastPathComponent().deletingLastPathComponent(), directory)
                XCTAssertEqual(url.lastPathComponent, "file.txt")
                XCTAssertEqual(try Data(contentsOf: url), Data("ok".utf8))
            } catch { XCTFail("Загрузка не завершена: \(error)") }
            completed.fulfill()
        }
        wait(for: [completed], timeout: 5)
        stop(manager)
    }

    func testSeparateSessionConfigurationsUseSeparateTransports() throws {
        let first = CTTestTransport(), second = CTTestTransport()
        let managers = [CTNetworkManager(configuration: first.configuration), CTNetworkManager(configuration: second.configuration)]
        let completed = expectation(description: "Два независимых транспорта")
        completed.expectedFulfillmentCount = 2
        first.onRequest = { _ in completed.fulfill() }
        second.onRequest = { _ in completed.fulfill() }
        for (index, manager) in managers.enumerated() {
            manager.set(baseURL: "https://chat.example.com", namespace: "channel")
            manager.registerFCMToken("token-\(index)", uuid: "visitor-\(index)")
        }
        wait(for: [completed], timeout: 5)
        managers.forEach(stop)
        XCTAssertEqual(first.requests.count, 1)
        XCTAssertEqual(second.requests.count, 1)
        XCTAssertNotEqual(first.requests.first?.httpBody, second.requests.first?.httpBody)
    }

    private func stop(_ manager: CTNetworkManager) {
        let stopped = expectation(description: "Сессия остановлена")
        manager.invalidate { stopped.fulfill() }
        wait(for: [stopped], timeout: 5)
    }
}
