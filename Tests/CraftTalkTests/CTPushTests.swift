import XCTest
@testable import CraftTalk

final class CTPushTests: XCTestCase {
    private var transport: CTTestTransport!
    private var manager: CTNetworkManager!
    private var scheduler: CTManualScheduler!
    private var chat: CTChat!

    override func setUpWithError() throws {
        transport = CTTestTransport()
        manager = CTNetworkManager(configuration: transport.configuration)
        scheduler = CTManualScheduler()
        let settings = ["CTChatBaseURL": "https://chat.example.com", "CTChatNamespace": "канал", "CTSalt": "salt"]
        let scheduler = self.scheduler!
        chat = CTChat(infoValue: { settings[$0] }, networkManager: manager, schedulePush: scheduler.schedule)
        try chat.configure(security: CTSecurityConfiguration())
        chat.registerVisitor(CTVisitor(uuid: "visitor-1", salt: "salt"))
    }

    override func tearDownWithError() throws {
        let invalidated = expectation(description: "Сессия завершена до следующего теста")
        manager.invalidate { invalidated.fulfill() }
        wait(for: [invalidated], timeout: 5)
        scheduler.discardAll()
        chat = nil
        manager = nil
        transport = nil
        scheduler = nil
    }

    func testDoesNotScheduleWithoutToken() {
        chat.registerPushNotifications()
        chat.saveFCMToken("")
        chat.registerPushNotifications()
        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testRequestContainsEndpointMethodHeadersAndVisitor() throws {
        chat.saveFCMToken("token\"\n🔑")
        chat.registerPushNotifications()
        XCTAssertEqual(scheduler.jobs.map { $0.delay }, [5])
        let request = try executePushes()
        XCTAssertEqual(request.url?.scheme, "https")
        XCTAssertEqual(request.url?.host, "chat.example.com")
        XCTAssertEqual(request.url?.path, "/webchat/канал/set-user-subscription")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
        XCTAssertEqual(object, ["subscription": "token\"\n🔑", "uuid": "visitor-1"])
    }

    func testRepeatedEventsScheduleIndependentRequests() throws {
        chat.saveFCMToken("token")
        for _ in 0..<3 { chat.registerPushNotifications() }
        XCTAssertEqual(scheduler.jobs.map { $0.delay }, [5, 5, 5])
        _ = try executePushes(count: 3)
        chat.registerPushNotifications()
        _ = try executePushes()
        XCTAssertEqual(transport.requests.count, 4)
    }

    func testTokenChangePreservesScheduledSnapshotAndNextEventUsesNewToken() throws {
        chat.saveFCMToken("old-token")
        chat.registerPushNotifications()
        chat.saveFCMToken("new-token")
        let previous = try executePushes()
        XCTAssertEqual(try body(previous)["subscription"], "old-token")
        chat.registerPushNotifications()
        XCTAssertEqual(try body(executePushes())["subscription"], "new-token")
    }

    func testVisitorChangePreservesScheduledSnapshotAndNextEventUsesNewVisitor() throws {
        chat.saveFCMToken("token")
        chat.registerPushNotifications()
        chat.registerVisitor(CTVisitor(uuid: "visitor-2", salt: "salt"))
        XCTAssertEqual(try body(executePushes())["uuid"], "visitor-1")
        chat.registerPushNotifications()
        XCTAssertEqual(try body(executePushes())["uuid"], "visitor-2")
    }

    func testClearingTokenPreservesPendingRequestButPreventsNewRequests() throws {
        chat.saveFCMToken("token")
        chat.registerPushNotifications()
        chat.saveFCMToken("")
        chat.registerPushNotifications()
        XCTAssertEqual(scheduler.pendingCount, 1)
        XCTAssertEqual(try body(executePushes())["subscription"], "token")
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    func testSavingSameTokenAndVisitorKeepsPendingRequest() throws {
        chat.saveFCMToken("token")
        chat.registerPushNotifications()
        chat.saveFCMToken("token")
        chat.registerVisitor(CTVisitor(firstName: "changed", uuid: "visitor-1", salt: "salt"))
        XCTAssertEqual(scheduler.pendingCount, 1)
        _ = try executePushes()
    }

    func testScheduledClosureRetainsChatUntilSchedulerReleasesIt() {
        chat.saveFCMToken("token")
        chat.registerPushNotifications()
        weak var retained = chat
        chat = nil
        XCTAssertNotNil(retained)
        scheduler.discardAll()
        XCTAssertNil(retained)
    }

    private func body(_ request: URLRequest) throws -> [String: String] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
    }

    private func executePushes(count: Int = 1) throws -> URLRequest {
        let received = expectation(description: "Push переданы в изолированный транспорт")
        received.expectedFulfillmentCount = count
        transport.onRequest = { _ in received.fulfill() }
        let previousCount = transport.requests.count
        scheduler.runAll()
        wait(for: [received], timeout: 5)
        XCTAssertEqual(transport.requests.count, previousCount + count)
        return try XCTUnwrap(transport.requests.last)
    }
}
