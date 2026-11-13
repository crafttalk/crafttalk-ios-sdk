import UIKit
import WebKit

@main
struct TestMain {
    static func main() {
        UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, NSStringFromClass(TestApplication.self), NSStringFromClass(AppDelegate.self))
    }
}

// Проверяем передачу tel/mailto системе, не совершая звонков и не отправляя писем.
final class TestApplication: UIApplication {
    var openedSchemes: [String] = []
    override func open(_ url: URL, options: [UIApplication.OpenExternalURLOptionsKey: Any] = [:], completionHandler completion: ((Bool) -> Void)? = nil) {
        if ["tel", "mailto"].contains(url.scheme ?? "") {
            openedSchemes.append(url.scheme!)
            completion?(true)
        } else { super.open(url, options: options, completionHandler: completion) }
    }
}

final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private(set) var backgroundCount = 0
    private(set) var activationCount = 0

    func applicationDidEnterBackground(_ application: UIApplication) { backgroundCount += 1 }
    func applicationDidBecomeActive(_ application: UIApplication) { activationCount += 1 }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Это отдельное тестовое приложение на одноразовом симуляторе. Уборка до
        // открытия SDK изолирует следующий сценарий даже после crash без teardown.
        var startupErrors: [String] = []
        var removedDirectoryCount = 0
        do {
            let temporary = FileManager.default.temporaryDirectory
            for folder in try FileManager.default.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil) {
                guard UUID(uuidString: folder.lastPathComponent) != nil else { continue }
                try FileManager.default.removeItem(at: folder)
                removedDirectoryCount += 1
            }
            if ProcessInfo.processInfo.arguments.contains("seed-unreadable-attachment") {
                let folder = temporary.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
                try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("unreadable.bin"),
                                                          withDestinationURL: folder.appendingPathComponent("missing.bin"))
            }
        } catch { startupErrors.append("startup: \(error)") }
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        if ProcessInfo.processInfo.arguments.contains("seed-upload-file") {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try! Data("synthetic-picker-upload".utf8).write(to: documents.appendingPathComponent("sdk-upload.txt"))
        }
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        self.window = window
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
            window.rootViewController = HarnessController(startupErrors: startupErrors, removedDirectoryCount: removedDirectoryCount)
        }
        return true
    }
}

// Наблюдатель тестового приложения не меняет WebKit delegate, скрипты и логику SDK.
final class HarnessController: UIViewController, UINavigationControllerDelegate {
    private let startupErrors: [String]
    private let removedDirectoryCount: Int
    private let launchID = UUID().uuidString
    private let home = UIViewController()
    private lazy var navigation = UINavigationController(rootViewController: home)
    private let status = UILabel()
    private weak var lastChat: CTChatViewController?
    private weak var lastWebView: WKWebView?
    private var errors: [String] = []
    private var timer: Timer?
    private var page: [String: Any] = [:]
    private var evaluating = false
    private var pageObservationStarted = 0
    private var pageObservationCompleted = 0
    private var pageObservationError = ""
    private var opened: [WeakChat] = []
    private let diagnostics = URLSession(configuration: .ephemeral)
    private var publishing = false
    private var interactiveStarts = 0
    private var interactiveCancellations = 0

    init(startupErrors: [String], removedDirectoryCount: Int) {
        self.startupErrors = startupErrors
        self.removedDirectoryCount = removedDirectoryCount
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Используйте init(startupErrors:)") }
    private lazy var controlURL: URL = {
        let data = try! Data(contentsOf: Bundle.main.url(forResource: "config", withExtension: "json", subdirectory: "Runtime")!)
        let config = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        let port = (config["ports"] as! [String: Int])["system"]!
        return URL(string: "https://127.0.0.1:\(port)/control/\(config["uiCase"] as! String)")!
    }()

    private final class WeakChat {
        weak var controller: CTChatViewController?
        weak var web: WKWebView?
        init(_ controller: CTChatViewController, _ web: WKWebView?) { self.controller = controller; self.web = web }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        home.view.backgroundColor = .systemBackground
        home.title = "SDK test host"
        navigation.delegate = self
        addChild(navigation)
        view.addSubview(navigation.view)
        navigation.didMove(toParent: self)
        navigation.view.translatesAutoresizingMaskIntoConstraints = false
        status.accessibilityIdentifier = "HarnessState"
        status.isAccessibilityElement = true
        status.text = "Test diagnostics"
        status.font = .systemFont(ofSize: 11)
        status.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(status)
        NSLayoutConstraint.activate([
            navigation.view.topAnchor.constraint(equalTo: view.topAnchor),
            navigation.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigation.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            navigation.view.bottomAnchor.constraint(equalTo: status.topAnchor),
            status.heightAnchor.constraint(equalToConstant: 28),
            status.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            status.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            status.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        let buttons = UIStackView(arrangedSubviews: [button("Open secure", action: #selector(openSecure)), button("Open legacy", action: #selector(openLegacy))])
        buttons.axis = .vertical
        buttons.spacing = 20
        buttons.translatesAutoresizingMaskIntoConstraints = false
        home.view.addSubview(buttons)
        NSLayoutConstraint.activate([buttons.centerXAnchor.constraint(equalTo: home.view.centerXAnchor), buttons.centerYAnchor.constraint(equalTo: home.view.centerYAnchor)])
        CTChat.shared.onError = { [weak self] error in self?.errors.append(error.localizedDescription) }
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.observe() }
    }

    private func button(_ title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc private func openSecure() { open(legacy: false) }
    @objc private func openLegacy() { open(legacy: true) }

    private func open(legacy: Bool) {
        errors = []
        page = [:]
        pageObservationError = ""
        do {
            if legacy { CTChat.shared.configure() }
            else {
                let data = try Data(contentsOf: Bundle.main.url(forResource: "root", withExtension: "der", subdirectory: "Runtime")!)
                let allowed: Set<String> = ProcessInfo.processInfo.arguments.contains("allow-target") ? ["127.0.0.1"] : []
                try CTChat.shared.configure(security: CTSecurityConfiguration(trustedRootsByHost: ["localhost": [data], "127.0.0.1": [data]], allowedRedirectHosts: allowed))
            }
            let hash: String? = ProcessInfo.processInfo.arguments.contains("compute-visitor-hash") ? nil : "ui-hash"
            CTChat.shared.registerVisitor(CTVisitor(firstName: "Тест", uuid: "ui-visitor", hash: hash, customProperties: ["nested": ["value": 7]]))
            let token = ProcessInfo.processInfo.arguments.contains("without-push-token") ? "" : "synthetic-ui-token"
            CTChat.shared.saveFCMToken(token)
            let chat = CTChatViewController(nibName: nil, bundle: nil)
            chat.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Close Chat", style: .plain, target: self, action: #selector(closeChat))
            if !ProcessInfo.processInfo.arguments.contains("interactive-back") {
                chat.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Block UI", style: .plain, target: self, action: #selector(blockUI))
            }
            lastChat = chat
            navigation.pushViewController(chat, animated: false)
            lastWebView = findWebView(chat.view)
            opened.append(WeakChat(chat, lastWebView))
        } catch { errors.append(error.localizedDescription) }
    }

    @objc private func closeChat() {
        lastChat?.dismiss(animated: false)
        navigation.popViewController(animated: false)
    }

    // Наблюдаем штатный переход UIKit, не подменяя gesture delegate или animator.
    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        guard let transition = navigationController.transitionCoordinator, transition.isInteractive else { return }
        interactiveStarts += 1
        transition.notifyWhenInteractionChanges { [weak self] context in
            if context.isCancelled { self?.interactiveCancellations += 1 }
        }
    }

    @objc private func blockUI() {
        let alert = UIAlertController(title: "Another presentation", message: "Download must clean up", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Dismiss blocker", style: .cancel))
        lastChat?.present(alert, animated: true)
    }

    private func findWebView(_ view: UIView) -> WKWebView? {
        if let webView = view as? WKWebView { return webView }
        return view.subviews.lazy.compactMap { self.findWebView($0) }.first
    }

    private func observe() {
        if ProcessInfo.processInfo.arguments.contains("label-preview-buttons"), let chat = lastChat {
            labelPreviewButtons(in: chat.view, controller: chat)
        }
        if let web = lastWebView, !evaluating {
            evaluating = true
            pageObservationStarted += 1
            let attempt = pageObservationStarted
            web.evaluateJavaScript("""
                ({url:location.href,pageID:window.testPageID || '',draft:document.getElementById('draft')?.value || '',
                  visitor:window.testVisitor || null,accept:document.getElementById('webchat-file-input')?.getAttribute('accept'),
                  autocorrect:document.getElementById('draft')?.getAttribute('autocorrect'),
                  marker:document.getElementById('marker')?.textContent || ''})
                """) { [weak self, weak web] value, error in
                    guard let self = self else { return }
                    self.evaluating = false
                    // Ответ закрытого WebView не должен перезаписать состояние нового чата.
                    guard let web = web, self.lastWebView === web else { return }
                    self.pageObservationCompleted = attempt
                    if let error = error as NSError? {
                        self.page = [:]
                        self.pageObservationError = "evaluateJavaScript: \(error.domain) code=\(error.code)"
                    } else if let value = value as? [String: Any] {
                        self.page = value
                        self.pageObservationError = ""
                    } else {
                        self.page = [:]
                        self.pageObservationError = "evaluateJavaScript: неожиданный формат снимка"
                    }
                }
        } else if lastWebView == nil {
            page = [:]
        }
        // Учитываем только каталоги вложений SDK; системные кеши WebKit не входят в отчёт.
        let temporary = FileManager.default.temporaryDirectory
        var files: [[String: Any]] = []
        var directories: [String] = []
        var observationErrors = startupErrors
        do {
            for folder in try FileManager.default.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil) {
                guard UUID(uuidString: folder.lastPathComponent) != nil else { continue }
                directories.append(folder.lastPathComponent)
                do {
                    for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
                        do {
                            let data = try Data(contentsOf: file)
                            files.append(["name": file.lastPathComponent, "body": data.base64EncodedString()])
                        } catch { observationErrors.append("read \(file.lastPathComponent): \(error)") }
                    }
                } catch { observationErrors.append("list \(folder.lastPathComponent): \(error)") }
            }
        } catch { observationErrors.append("list temporary: \(error)") }
        directories.sort()
        let lifecycle = UIApplication.shared.delegate as? AppDelegate
        let snapshot: [String: Any] = ["launchID": launchID, "observationErrors": observationErrors,
                                       "resetDirectoryCount": removedDirectoryCount,
                                       "controllerAlive": lastChat != nil, "webViewAlive": lastWebView != nil,
                                       "idiom": UIDevice.current.userInterfaceIdiom == .pad ? "pad" : "phone",
                                       "viewWidth": lastChat?.view.bounds.width ?? 0,
                                       "viewHeight": lastChat?.view.bounds.height ?? 0,
                                       "chatOnTop": lastChat != nil && navigation.topViewController === lastChat,
                                       "interactiveStarts": interactiveStarts, "interactiveCancellations": interactiveCancellations,
                                       "backgroundCount": lifecycle?.backgroundCount ?? 0,
                                       "activationCount": lifecycle?.activationCount ?? 0,
                                       "aliveCount": opened.filter { $0.controller != nil || $0.web != nil }.count,
                                       "openedSchemes": (UIApplication.shared as? TestApplication)?.openedSchemes ?? [],
                                       "errors": errors, "files": files, "page": page,
                                       "pageObservationStarted": pageObservationStarted,
                                       "pageObservationCompleted": pageObservationCompleted,
                                       "pageObservationError": pageObservationError,
                                       "directories": directories,
                                       "presented": lastChat?.presentedViewController.map { String(describing: type(of: $0)) } ?? ""]
        if let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) {
            status.accessibilityValue = text
        }
        // Диагностика доступна UI-тесту и при закрывающем экран системном меню.
        if !publishing, let data = try? JSONSerialization.data(withJSONObject: ["snapshot": snapshot]) {
            publishing = true
            var request = URLRequest(url: controlURL)
            request.httpMethod = "POST"
            request.httpBody = data
            diagnostics.dataTask(with: request) { [weak self] data, _, _ in
                let reply = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] }
                DispatchQueue.main.async {
                    self?.publishing = false
                    // Приложение-владелец может закрыть чат, пока SDK показывает меню.
                    if reply?.first?["hostCommand"] as? String == "closeChat" { self?.closeChat() }
                }
            }.resume()
        }
    }

    // Только метки для XCUITest: не меняем targets/actions, геометрию или поведение кнопок SDK.
    private func labelPreviewButtons(in view: UIView, controller: CTChatViewController) {
        if let button = view as? UIButton {
            let actions = button.actions(forTarget: controller, forControlEvent: .touchUpInside) ?? []
            if actions.contains("goBack:") { button.accessibilityIdentifier = "LegacyPreviewBack" }
            if actions.contains("share:") { button.accessibilityIdentifier = "LegacyPreviewShare" }
        }
        view.subviews.forEach { labelPreviewButtons(in: $0, controller: controller) }
    }
}
