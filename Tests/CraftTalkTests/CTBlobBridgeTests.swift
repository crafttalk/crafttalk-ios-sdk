import XCTest
import WebKit
@testable import CraftTalk

@MainActor
final class CTBlobBridgeTests: XCTestCase {
    func testEachBridgeMessageSchedulesPushRegardlessOfBody() throws {
        let scheduler = CTManualScheduler()
        let chat = CTChat(infoValue: { _ in nil }, schedulePush: scheduler.schedule)
        chat.registerVisitor(CTVisitor(uuid: "visitor", salt: "salt"))
        chat.saveFCMToken("token")
        let controller = CTChatViewController(nibName: nil, bundle: nil)
        controller.chat = chat
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(controller, name: "handler")
        let completed = expectation(description: "Сообщения WebKit доставлены")
        let observer = CTScriptMessageObserver { completed.fulfill() }
        configuration.userContentController.add(observer, name: "done")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        defer {
            webView.stopLoading()
            configuration.userContentController.removeScriptMessageHandler(forName: "handler")
            configuration.userContentController.removeScriptMessageHandler(forName: "done")
            scheduler.discardAll()
        }
        webView.loadHTMLString("""
            <script>
            webkit.messageHandlers.handler.postMessage("unrelated");
            webkit.messageHandlers.handler.postMessage({event: "User registred"});
            webkit.messageHandlers.handler.postMessage("User registred");
            webkit.messageHandlers.handler.postMessage("User registred");
            webkit.messageHandlers.done.postMessage("done");
            </script>
            """, baseURL: nil)
        wait(for: [completed], timeout: 30)
        XCTAssertEqual(scheduler.pendingCount, 4)
    }

    func testMalformedMessagesReportDecodingErrors() {
        let controller = CTChatViewController(nibName: nil, bundle: nil)
        let chat = CTChat(infoValue: { _ in nil })
        controller.chat = chat
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(controller, name: "readBlob")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        defer {
            webView.stopLoading()
            configuration.userContentController.removeScriptMessageHandler(forName: "readBlob")
        }
        let errors = expectation(description: "Ошибочные сообщения из настоящего WebKit")
        errors.expectedFulfillmentCount = 3
        chat.onError = { error in
            XCTAssertTrue(Thread.isMainThread)
            guard let error = error as? CTChatError else { return XCTFail("Ожидалась CTChatError") }
            XCTAssertEqual(error.stage, .download)
            XCTAssertEqual(error.code, NSURLErrorCannotDecodeContentData)
            errors.fulfill()
        }
        webView.loadHTMLString("""
            <script>
            webkit.messageHandlers.readBlob.postMessage(42);
            webkit.messageHandlers.readBlob.postMessage("");
            webkit.messageHandlers.readBlob.postMessage("data:application/pdf;base64,invalid!");
            </script>
            """, baseURL: nil)
        wait(for: [errors], timeout: 30)

    }
}

private final class CTScriptMessageObserver: NSObject, WKScriptMessageHandler {
    private let received: () -> Void

    init(received: @escaping () -> Void) { self.received = received }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        received()
    }
}
