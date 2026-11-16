import XCTest
@testable import CraftTalk

final class CTChatErrorTests: XCTestCase {
    func testDescriptionContainsOnlySanitizedFieldsForEveryStage() {
        let stages: [CTChatError.Stage] = [.configuration, .tls, .navigation, .download, .pushRegistration]
        for stage in stages {
            let error = CTChatError(stage: stage, host: "CHAT.Example.COM.", code: -1202, domain: NSURLErrorDomain)
            XCTAssertEqual(error.localizedDescription, "CTChat stage=\(stage.rawValue) host=chat.example.com domain=NSURLErrorDomain code=-1202")
        }
    }

    func testUnderlyingErrorDoesNotExposeVisitorRequestOrURL() {
        let url = URL(string: "https://user:password@chat.example.com/private/visitor-id?token=secret#fragment")
        let original = NSError(domain: NSURLErrorDomain, code: -1001, userInfo: [
            NSLocalizedDescriptionKey: "token=secret visitor-id request-body", NSURLErrorFailingURLErrorKey: url as Any,
            NSUnderlyingErrorKey: NSError(domain: "private", code: 7)
        ])
        let error = CTChatError(stage: .download, url: url, error: original)
        XCTAssertEqual(error.host, "chat.example.com")
        XCTAssertEqual(error.domain, NSURLErrorDomain)
        XCTAssertEqual(error.code, -1001)
        let description = (error as NSError).localizedDescription
        for secret in ["user", "password", "private", "visitor-id", "secret", "request-body", "fragment"] {
            XCTAssertFalse(description.contains(secret), secret)
        }
    }

    func testInvalidOrMissingHostIsOmitted() {
        for host in [nil, "https://chat.example.com/private", "host\nsecret", "*.example.com"] {
            let error = CTChatError(stage: .configuration, host: host, code: 1)
            XCTAssertNil(error.host)
            XCTAssertEqual(error.errorDescription, "CTChat stage=configuration host=- domain=CTChat code=1")
        }
    }

    func testReportingFromBackgroundArrivesOnMainQueueWithoutChangingError() {
        let chat = CTChat(infoValue: { _ in nil })
        let delivered = expectation(description: "Callback на главной очереди")
        chat.onError = { error in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual((error as? CTChatError)?.stage, .tls)
            XCTAssertEqual((error as? CTChatError)?.code, -1202)
            delivered.fulfill()
        }
        DispatchQueue.global().async { chat.report(CTChatError(stage: .tls, host: "chat.example.com", code: -1202)) }
        wait(for: [delivered], timeout: 2)
    }
}
