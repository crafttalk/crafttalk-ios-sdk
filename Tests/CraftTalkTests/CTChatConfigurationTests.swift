import XCTest
@testable import CraftTalk

final class CTChatConfigurationTests: XCTestCase {
    private let settings: [String: Any] = [
        "CTChatBaseURL": "https://chat.example.com",
        "CTChatNamespace": "test-channel",
        "CTSalt": "test-salt"
    ]

    func testVisitorHashUsesSaltInsteadOfBaseURL() {
        let chat = CTChat(infoValue: { self.settings[$0] })
        chat.configure()
        // Барьер позволяет отдельно воспроизвести ошибку salt в прежнем асинхронном коде.
        chat.ctqueue.sync(flags: .barrier) {}

        let visitor = CTVisitor(firstName: "Анна", lastName: "Иванова", email: "anna@example.com",
                                phone: "+79990000000", contract: "C-42", birthday: "2000-01-02",
                                uuid: "visitor-123", salt: chat.salt)
        // Независимое значение: SHA256(salt + hex(SHA256(salt + поля))) через Python hashlib.
        XCTAssertEqual(visitor.hash, "86f3889a42e867e71518c8740b09ca2bb932a4855fc3b4e647667ee8615195ad")
        XCTAssertEqual(chat.salt, "test-salt")
    }

    func testLegacyConfigurationIsReadyOnReturn() {
        let chat = CTChat(infoValue: { self.settings[$0] })
        assertReadyOnReturn(chat) { chat.configure() }
        XCTAssertNil(chat.securityPolicy)
    }

    func testExplicitVisitorHashRemainsUnchanged() {
        let visitor = CTVisitor(firstName: "Анна", uuid: "visitor-123", hash: "server-hash")
        XCTAssertEqual(visitor.hash, "server-hash")
    }

    func testTrailingBaseURLSlashIsPreservedInWebchatURL() throws {
        var values = settings
        values["CTChatBaseURL"] = "https://chat.example.com/prefix/"
        let chat = CTChat(infoValue: { values[$0] })
        try chat.configure(security: CTSecurityConfiguration())
        XCTAssertEqual(chat.webchatURL.absoluteString, "https://chat.example.com/prefix//webchat/test-channel")
    }

    func testSecureConfigurationIsReadyOnReturn() throws {
        let chat = CTChat(infoValue: { self.settings[$0] })
        try assertReadyOnReturn(chat) { try chat.configure(security: CTSecurityConfiguration()) }
        XCTAssertEqual(chat.securityPolicy?.allowedHosts, ["chat.example.com"])
    }

    func testSecureConfigurationRejectsInvalidSettingsWithoutApplyingAnything() throws {
        let invalidValues: [(String, Any?, Int)] = [
            ("CTChatBaseURL", nil, 4), ("CTChatBaseURL", 42, 4),
            ("CTChatBaseURL", "", 4), ("CTChatBaseURL", "/relative", 4),
            ("CTChatBaseURL", "file:///tmp/chat", 4),
            ("CTChatBaseURL", "http://chat.example.com", 4),
            ("CTChatBaseURL", "https://chat.example.com?token=private", 4),
            ("CTChatBaseURL", "https://chat.example.com#fragment", 4),
            ("CTSalt", nil, 7), ("CTSalt", 42, 7),
            ("CTChatNamespace", nil, 8), ("CTChatNamespace", ["channel"], 8),
            ("CTChatNamespace", "channel?token=private", 8),
            ("CTChatNamespace", "channel#fragment", 8)
        ]
        for (key, value, code) in invalidValues {
            var values = settings
            let chat = CTChat(infoValue: { values[$0] })
            let originalPolicy = CTSecurityConfiguration(allowedRedirectHosts: ["files.example.com"])
            try chat.configure(security: originalPolicy)
            values["CTChatBaseURL"] = "https://new.example.com"
            values["CTSalt"] = "changed-salt"
            values["CTChatNamespace"] = "changed-channel"
            values[key] = value

            XCTAssertThrowsError(try chat.configure(security: CTSecurityConfiguration())) { error in
                self.assertConfigurationError(error, code: code)
            }
            assertOriginalSettings(chat)
            XCTAssertEqual(chat.securityPolicy?.allowedHosts, ["chat.example.com", "files.example.com"])
        }
    }

    func testInvalidPolicyPreservesSettingsAndAllowsImmediateRetry() throws {
        var values = settings
        let chat = CTChat(infoValue: { values[$0] })
        try chat.configure(security: CTSecurityConfiguration(allowedRedirectHosts: ["files.example.com"]))
        values = ["CTChatBaseURL": "https://new.example.com", "CTSalt": "new-salt", "CTChatNamespace": "new-channel"]

        XCTAssertThrowsError(try chat.configure(security: CTSecurityConfiguration(allowedRedirectHosts: ["*.example.com"]))) {
            self.assertConfigurationError($0, code: 1)
        }
        assertOriginalSettings(chat)
        XCTAssertEqual(chat.securityPolicy?.allowedHosts, ["chat.example.com", "files.example.com"])

        try chat.configure(security: CTSecurityConfiguration())
        XCTAssertEqual(chat.salt, "new-salt")
        XCTAssertEqual(chat.webchatURL.absoluteString, "https://new.example.com/webchat/new-channel")
        XCTAssertEqual(chat.securityPolicy?.allowedHosts, ["new.example.com"])
    }

    func testLegacyFailureReportsOnMainQueueAndPreservesSecureConfiguration() throws {
        var values = settings
        let chat = CTChat(infoValue: { values[$0] })
        try chat.configure(security: CTSecurityConfiguration())
        values["CTSalt"] = nil
        let reported = expectation(description: "Ошибка конфигурации на главной очереди")
        chat.onError = { error in
            XCTAssertTrue(Thread.isMainThread)
            self.assertConfigurationError(error, code: 7)
            reported.fulfill()
        }
        chat.configure()
        assertOriginalSettings(chat)
        XCTAssertEqual(chat.securityPolicy?.allowedHosts, ["chat.example.com"])
        wait(for: [reported], timeout: 2)
    }

    func testFailedFirstConfigurationLeavesInitialState() {
        let chat = CTChat(infoValue: { _ in nil })
        XCTAssertThrowsError(try chat.configure(security: CTSecurityConfiguration())) {
            self.assertConfigurationError($0, code: 4)
        }
        XCTAssertEqual(chat.baseURL, "")
        XCTAssertEqual(chat.salt, "")
        XCTAssertEqual(chat.namespace, "")
        XCTAssertNil(chat.securityPolicy)
    }

    func testLegacyReconfigurationClearsPolicyAndPreservesLegacyHosts() throws {
        var values = settings
        let chat = CTChat(infoValue: { values[$0] })
        try chat.configure(security: CTSecurityConfiguration())
        for baseURL in ["http://chat_internal", "https://[::1]:8443"] {
            values["CTChatBaseURL"] = baseURL
            chat.configure()
            XCTAssertNil(chat.securityPolicy)
            XCTAssertEqual(chat.webchatURL.absoluteString, baseURL + "/webchat/test-channel")
        }
    }

    func testExplicitEmptySaltAndNamespaceRemainSupported() throws {
        var values = settings
        values["CTSalt"] = ""
        values["CTChatNamespace"] = ""
        let chat = CTChat(infoValue: { values[$0] })
        try chat.configure(security: CTSecurityConfiguration())
        XCTAssertEqual(chat.salt, "")
        XCTAssertEqual(chat.webchatURL.absoluteString, "https://chat.example.com/webchat/")
    }

    private func assertConfigurationError(_ error: Error, code: Int,
                                          file: StaticString = #filePath, line: UInt = #line) {
        guard let error = error as? CTChatError else {
            XCTFail("Ожидалась CTChatError", file: file, line: line)
            return
        }
        XCTAssertEqual(error.stage, .configuration, file: file, line: line)
        XCTAssertEqual(error.domain, "CTChat", file: file, line: line)
        XCTAssertEqual(error.code, code, file: file, line: line)
        XCTAssertNil(error.host, file: file, line: line)
    }

    private func assertOriginalSettings(_ chat: CTChat, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(chat.baseURL, "https://chat.example.com", file: file, line: line)
        XCTAssertEqual(chat.salt, "test-salt", file: file, line: line)
        XCTAssertEqual(chat.namespace, "test-channel", file: file, line: line)
        XCTAssertEqual(chat.webchatURL.absoluteString, "https://chat.example.com/webchat/test-channel", file: file, line: line)
    }

    private func assertReadyOnReturn(_ chat: CTChat, configure: () throws -> Void,
                                     file: StaticString = #filePath, line: UInt = #line) rethrows {
        // Занятая очередь не должна задерживать применение настроек; sleep не нужен.
        chat.ctqueue.suspend()
        defer {
            chat.ctqueue.resume()
            chat.ctqueue.sync(flags: .barrier) {}
        }
        try configure()
        XCTAssertEqual(chat.baseURL, "https://chat.example.com", file: file, line: line)
        XCTAssertEqual(chat.namespace, "test-channel", file: file, line: line)
        XCTAssertEqual(chat.salt, "test-salt", file: file, line: line)
        if !chat.baseURL.isEmpty {
            XCTAssertEqual(chat.webchatURL.absoluteString, "https://chat.example.com/webchat/test-channel",
                           file: file, line: line)
        }
    }
}
