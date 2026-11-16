import XCTest
import WebKit
@testable import CraftTalk

@MainActor
final class CTBlobBridgeTests: XCTestCase {
    func testEachBridgeMessageSchedulesPushRegardlessOfBody() async throws {
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
        let page = CTBridgeTestPage(configuration: configuration)
        defer {
            page.close()
            configuration.userContentController.removeScriptMessageHandler(forName: "handler")
            configuration.userContentController.removeScriptMessageHandler(forName: "done")
            scheduler.discardAll()
        }
        try await page.load()
        _ = try await page.webView.evaluateJavaScript("""
            webkit.messageHandlers.handler.postMessage("unrelated");
            webkit.messageHandlers.handler.postMessage({event: "User registred"});
            webkit.messageHandlers.handler.postMessage("User registred");
            webkit.messageHandlers.handler.postMessage("User registred");
            webkit.messageHandlers.done.postMessage("done");
            true;
            """)
        await fulfillment(of: [completed], timeout: 30)
        XCTAssertEqual(scheduler.pendingCount, 4)
    }

    func testMalformedMessagesReportDecodingErrors() async throws {
        let controller = CTChatViewController(nibName: nil, bundle: nil)
        let chat = CTChat(infoValue: { _ in nil })
        controller.chat = chat
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(controller, name: "readBlob")
        let page = CTBridgeTestPage(configuration: configuration)
        defer {
            page.close()
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
        try await page.load()
        _ = try await page.webView.evaluateJavaScript("""
            webkit.messageHandlers.readBlob.postMessage(42);
            webkit.messageHandlers.readBlob.postMessage("");
            webkit.messageHandlers.readBlob.postMessage("data:application/pdf;base64,invalid!");
            true;
            """)
        await fulfillment(of: [errors], timeout: 30)
    }
}

@MainActor
private final class CTBridgeTestPage: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    private let window: UIWindow
    private weak var previousKeyWindow: UIWindow?
    private let navigation = XCTestExpectation(description: "Страница моста загружена")
    private var navigationFinished = false
    private var navigationError: Error?

    init(configuration: WKWebViewConfiguration) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        previousKeyWindow = scene?.windows.first { $0.isKeyWindow }
        window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        webView = WKWebView(frame: window.bounds, configuration: configuration)
        super.init()
        // Видимое окно даёт WebKit обычный жизненный цикл; ожидания не блокируют MainActor.
        let host = UIViewController()
        host.view = webView
        window.rootViewController = host
        window.makeKeyAndVisible()
        webView.navigationDelegate = self
    }

    func load() async throws {
        webView.loadHTMLString("<!doctype html><html><body>Bridge test</body></html>", baseURL: nil)
        let result = await XCTWaiter.fulfillment(of: [navigation], timeout: 30)
        if let error = navigationError { throw error }
        guard result == .completed else {
            throw NSError(domain: "CTBridgeTestPage", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "WebKit не завершил загрузку страницы моста за 30 секунд"])
        }
    }

    func close() {
        webView.stopLoading()
        webView.navigationDelegate = nil
        window.isHidden = true
        window.rootViewController = nil
        previousKeyWindow?.makeKey()
    }

    private func finishNavigation(error: Error? = nil) {
        navigationError = error
        if !navigationFinished {
            navigationFinished = true
            navigation.fulfill()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishNavigation()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishNavigation(error: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishNavigation(error: error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        let error = NSError(domain: "CTBridgeTestPage", code: 2,
                            userInfo: [NSLocalizedDescriptionKey: "Процесс WebKit завершился во время проверки моста"])
        if navigationFinished { XCTFail(error.localizedDescription) }
        finishNavigation(error: error)
    }
}

private final class CTScriptMessageObserver: NSObject, WKScriptMessageHandler {
    private let received: () -> Void

    init(received: @escaping () -> Void) { self.received = received }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        received()
    }
}
