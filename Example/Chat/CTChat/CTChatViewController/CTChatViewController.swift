//
//  CTChatViewController.swift
//  Chat
//
//  Copyright © 2020 Crafttalk. All rights reserved.
//

import UIKit
import WebKit
import SafariServices

public final class CTChatViewController: UIViewController {
    
    internal let mimeTypes = CTAttachmentRules.mimeTypes
    internal var chat: CTChat = .shared

    private var blobFile: CTBlobFile?
    private weak var blobPreview: UIView?
    
    
    
    // MARK: - Properties
    private var wkWebView: WKWebView!
    private var chatURL: URL!
    private var visitor: CTVisitor!
    private var fileLoader: FileLoader!
    private lazy var scriptMessageHandler = CTWeakScriptMessageHandler(self)
    private let secureLinkToken = UUID().uuidString
    private var pendingUserLink: (url: URL, download: Bool, frameURL: URL?, mainFrame: Bool, expiresAt: TimeInterval)?
    private var attachmentTransfers: [ObjectIdentifier: CTAttachmentTransfer] = [:]
    private var attachmentNavigationURLs = Set<URL>()
    private var shouldDownloadMainFrame = false

    private var supportsResponseDownloads: Bool {
        if #available(iOS 14.5, *) { return true }
        return false
    }
    
    // MARK: - Lifecycle
    
    convenience init() {
        self.init(nibName: nil, bundle: nil)
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        chatURL = chat.webchatURL
        visitor = chat.visitor
        fileLoader = chat.networkManager
        setupWebView()
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isBeingDismissed || isMovingFromParent || navigationController?.isBeingDismissed == true {
            closeBlobPreview()
        }
    }
    
    // MARK: - Methods
    var philip = 1
    
    var tapStatusSwift: Int = 0
    
    private func setupWebView() {
        func getZoomDisableScript() -> WKUserScript {
            let source: String = "var meta = document.createElement('meta');" +
                "meta.name = 'viewport';" +
                "meta.content = 'width=device-width, initial-scale=1.0, maximum- scale=1.0, user-scalable=no';" +
                "var head = document.getElementsByTagName('head')[0];" + "head.appendChild(meta);"
            return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        }
        func getUserAuthScript() -> WKUserScript {
            let visitor = self.visitor.toJSON() ?? ""
            let source: String = """
                \( chat.isConsoleEnabled ? "javascript:(function () { var script = document.createElement('script'); script.src=\"//cdn.jsdelivr.net/npm/eruda\"; document.body.appendChild(script); script.onload = function () { eruda.init() } })();" : "")
                window.__WebchatUserCallback = function() {
                    webkit.messageHandlers.handler.postMessage("User registred");
                    return \(visitor);
                };
                """
            return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        }
        
        func setupWebViewLongPressure() -> WKUserScript {
            let source: String = """
            let longTapTimeout;
            let longtapTimeoutRest;
            const longTapThreshold = 350;
            const longTapThresholdRestTime = 200;
            var tapPressureStatus = false;

            function onTouchStart(event) {
              longTapTimeout = setTimeout(() => {
                console.log("Long tap detected!");
                tapPressureStatus = true;
              }, longTapThreshold);
            };
            function onTouchEnd(event) {
                longtapTimeoutRest = setTimeout(() => {
                    clearTimeout(longTapTimeout);
                    console.log("Long tap Rest!");
                    tapPressureStatus = false;
                }, longTapThresholdRestTime);
            };
            document.addEventListener("touchstart", onTouchStart);
            document.addEventListener("touchend", onTouchEnd);
            """
            return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        }
       
        
        let wkWebViewConfig = WKWebViewConfiguration()
        wkWebViewConfig.preferences.javaScriptEnabled = true
        wkWebViewConfig.userContentController.addUserScript(getZoomDisableScript())
        wkWebViewConfig.userContentController.addUserScript(getUserAuthScript())
        wkWebViewConfig.userContentController.addUserScript(setupWebViewLongPressure())
        wkWebViewConfig.userContentController.add(scriptMessageHandler, name: "handler")
        if chat.securityPolicy != nil {
            observeUserLinks(in: wkWebViewConfig.userContentController)
        }
        
        let wkWebView = WKWebView(frame: self.view.frame, configuration: wkWebViewConfig)
        wkWebView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(wkWebView)
        NSLayoutConstraint.activate([
            wkWebView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            wkWebView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            wkWebView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            wkWebView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        wkWebView.navigationDelegate = self
        wkWebView.uiDelegate = self
        wkWebView.allowsLinkPreview = false
        wkWebView.load(URLRequest(url: chatURL))
        self.wkWebView = wkWebView
    }

    private func observeUserLinks(in controller: WKUserContentController) {
        // navigationType also says linkActivated for a.click() and subsequent HTTP redirects.
        // Record the original URL of a real click; do not prevent or replace normal DOM navigation.
        func source(document: Bool, shadowRoots: Bool) -> String { return """
        (function() {
            var handler = window.webkit.messageHandlers.ctSecureLinkActivation;
            var post = handler.postMessage.bind(handler);
            var token = '\(secureLinkToken)';
            // Capture DOM methods before page scripts run. The page-world shadow observer
            // must not expose its token or rely on methods subsequently replaced by the page.
            var call = function(method) { return Function.prototype.call.bind(method); };
            var getAttribute = call(Element.prototype.getAttribute);
            var nodeType = call(Object.getOwnPropertyDescriptor(Node.prototype, 'nodeType').get);
            var localName = call(Object.getOwnPropertyDescriptor(Element.prototype, 'localName').get);
            var addListener = call(Node.prototype.addEventListener);
            var eventTarget = call(Object.getOwnPropertyDescriptor(Event.prototype, 'target').get);
            var prevented = call(Object.getOwnPropertyDescriptor(Event.prototype, 'defaultPrevented').get);
            var parentElement = call(Object.getOwnPropertyDescriptor(Node.prototype, 'parentElement').get);
            var composedPath = Event.prototype.composedPath && call(Event.prototype.composedPath);
            var createElement = document.createElement.bind(document);
            var hrefProperty = Object.getOwnPropertyDescriptor(HTMLAnchorElement.prototype, 'href');
            var readHref = call(hrefProperty.get);
            var writeHref = call(hrefProperty.set);
            var createMessage = Object.create.bind(Object, null);
            function href(element) {
                // composedPath also contains Window, which is not a Node.
                try { if (!element || nodeType(element) !== 1) return null; } catch (_) { return null; }
                var name = localName(element);
                if (name !== 'a' && name !== 'area') return null;
                return (getAttribute(element, 'href') !== null || getAttribute(element, 'xlink:href') !== null) ? element : null;
            }
            function clicked(event) {
                if (!event.isTrusted) return;
                var value = null;
                var path = composedPath ? composedPath(event) : [];
                for (var i = 0; i < path.length && value === null; i++) value = href(path[i]);
                for (var element = eventTarget(event); element && value === null; element = parentElement(element)) {
                    value = href(element);
                }
                var url = null;
                if (value !== null && !prevented(event)) {
                    var link = createElement('a');
                    writeHref(link, getAttribute(value, 'href') || getAttribute(value, 'xlink:href'));
                    url = readHref(link);
                }
                var message = createMessage();
                message.token = token;
                message.url = url;
                message.download = !!value && getAttribute(value, 'download') !== null;
                post(message);
            }
            if (\(document ? "true" : "false")) addListener(document, 'click', clicked, true);
            if (\(shadowRoots ? "true" : "false") && Element.prototype.attachShadow) {
                var descriptor = Object.getOwnPropertyDescriptor(Element.prototype, 'attachShadow');
                var attachShadow = call(descriptor.value);
                descriptor.value = function attachShadowWithClickObserver(options) {
                    var root = attachShadow(this, options);
                    // Listen inside the root, where composedPath includes its actual link.
                    // Preserve the requested mode: closed roots remain closed to the page.
                    addListener(root, 'click', clicked, true);
                    return root;
                };
                Object.defineProperty(Element.prototype, 'attachShadow', descriptor);
            }
        })();
        """ }
        if #available(iOS 14.0, *) {
            controller.add(scriptMessageHandler, contentWorld: .defaultClient, name: "ctSecureLinkActivation")
            controller.addUserScript(WKUserScript(source: source(document: true, shadowRoots: false), injectionTime: .atDocumentStart,
                                                  forMainFrameOnly: false, in: .defaultClient))
            // attachShadow must be observed in the same world as the component creating it.
            controller.add(scriptMessageHandler, contentWorld: .page, name: "ctSecureLinkActivation")
            controller.addUserScript(WKUserScript(source: source(document: false, shadowRoots: true), injectionTime: .atDocumentStart,
                                                  forMainFrameOnly: false, in: .page))
        } else {
            // Older WebKit has no isolated worlds. Keep the per-view token and bound handler
            // private in the document-start closure so page scripts cannot forge a click message.
            controller.add(scriptMessageHandler, name: "ctSecureLinkActivation")
            controller.addUserScript(WKUserScript(source: source(document: true, shadowRoots: true), injectionTime: .atDocumentStart,
                                                  forMainFrameOnly: false))
        }
    }

    private func consumeUserLink(for action: WKNavigationAction) -> (activated: Bool, download: Bool) {
        let activation = pendingUserLink
        pendingUserLink = nil // Includes allowed links: their redirects must not reuse the click.
        let activated = action.navigationType == .linkActivated &&
            activation?.url == action.request.url && activation?.frameURL == action.sourceFrame.request.url &&
            activation?.mainFrame == action.sourceFrame.isMainFrame &&
            (activation?.expiresAt ?? 0) >= ProcessInfo.processInfo.systemUptime
        return (activated, activated && activation?.download == true)
    }

    private func isAttachmentLink(_ url: URL, hasDownloadAttribute: Bool) -> Bool {
        return CTAttachmentRules.isAttachmentLink(url, hasDownloadAttribute: hasDownloadAttribute)
    }
    
    /// Download the file from the given url and store it locally in the app's temp folder.
    /// - Parameter downloadUrl: File download url
    private func loadAndDisplayDocumentFrom(url downloadUrl : URL) {
        guard presentedViewController == nil && !(presentedViewController is CTPreviewViewController) && !(presentedViewController is UIActivityViewController) else { return }
        UIApplication.shared.isNetworkActivityIndicatorVisible = true
        fileLoader.loadDocumentFrom(url: downloadUrl) { [weak self] result in
            UIApplication.shared.isNetworkActivityIndicatorVisible = false
            guard case let .success(localFileURL) = result else { return }
            if let ctPreviewType = CTPreviewType(fileURL: localFileURL) {
                self?.show(CTPreviewViewController.create(with: ctPreviewType), sender: nil)
            } else {
                let activityViewController = UIActivityViewController(activityItems: [localFileURL], applicationActivities: nil)
                activityViewController.completionWithItemsHandler = { (activityType, completed, returnedItems:[Any]?, error: Error?) in
                    try? FileManager.default.removeItem(at: localFileURL)
                }
                self?.present(activityViewController, animated: true, completion: nil)
            }
            
        }
    }
    
    private func openURLInSafariViewController(_ url: URL) {
        guard UIApplication.shared.canOpenURL(url) else { return }
        let vc = SFSafariViewController(url: url)
        self.present(vc, animated: true)
    }

    private func presentAttachment(at fileURL: URL, cleanup: (() -> Void)? = nil) {
        let directory = fileURL.deletingLastPathComponent()
        let cleanup = cleanup ?? { try? FileManager.default.removeItem(at: directory) }
        guard presentedViewController == nil, viewIfLoaded?.window != nil else {
            cleanup()
            return
        }
        let controller = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            cleanup()
        }
        // A popover anchor is required on iPad.
        controller.popoverPresentationController?.sourceView = view
        controller.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        present(controller, animated: true)
    }

    private func downloadAttachmentBeforeIOS145(request: URLRequest, webView: WKWebView) {
        // Called only before WebKit sends the initial GET. Redirects and TLS are
        // checked by the same secured session; never restart a received response.
        let load: ([HTTPCookie]) -> Void = { [weak self] cookies in
            guard let self = self else { return }
            self.chat.networkManager.loadDocumentFrom(request: request, webCookies: cookies) { [weak self] result in
                guard case let .success(fileURL) = result else { return }
                let directory = fileURL.deletingLastPathComponent()
                guard let self = self else { try? FileManager.default.removeItem(at: directory); return }
                self.presentAttachment(at: fileURL)
            }
        }
        if #available(iOS 11.0, *) {
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies(load)
        } else {
            load(HTTPCookieStorage.shared.cookies ?? [])
        }
    }
    
    private func setInputAttribute() {
        guard wkWebView != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) { [weak self] in
            let source: String = """
                var inputElement = document.getElementById('webchat-file-input');
                inputElement.setAttribute('accept', 'image/jpg,image/jpeg,image/gif,image/img,.doc,.docx,.pdf,.txt');
                inputElement = Array.from( document.getElementsByClassName('webchat-userinput'));
                inputElement.forEach(element => element.setAttribute('autocorrect', 'on'));
                inputElement.forEach(element => element.setAttribute('spellcheck', 'true'));
                inputElement.forEach(element => element.setAttribute('autocomplete', 'true'));
                inputElement.forEach(element => element.setAttribute('autocapitalize', 'on'));
                """
            self?.wkWebView.evaluateJavaScript(source)
        }
    }
    
    
}

// MARK: - WKNavigationDelegate & WKUIDelegate
extension CTChatViewController: WKNavigationDelegate, WKUIDelegate {
    

    
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        reportNavigationError(error, webView: webView)
    }
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        shouldDownloadMainFrame = false
        attachmentNavigationURLs.removeAll()
    }
    
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        reportNavigationError(error, webView: webView)
    }

    private func reportNavigationError(_ error: Error, webView: WKWebView) {
        shouldDownloadMainFrame = false
        let failure = error as NSError
        let url = (failure.userInfo[NSURLErrorFailingURLErrorKey] as? URL) ?? webView.url ?? chatURL
        // WebKit reports a policy interruption when navigation becomes a download.
        // Only consume that expected handoff, not errors from rejected navigation.
        if failure.domain == "WebKitErrorDomain", failure.code == 102,
           let url = url, attachmentNavigationURLs.contains(url) {
            attachmentNavigationURLs.removeAll()
            return
        }
        let stage: CTChatError.Stage = (-1206 ... -1200).contains(failure.code) ? .tls : .navigation
        chat.report(CTChatError(stage: stage, url: url, error: error))
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard let policy = chat.securityPolicy, let url = navigationResponse.response.url,
              url.scheme?.lowercased() != "blob" else {
            decisionHandler(.allow)
            return
        }
        guard policy.allows(url) else {
            if navigationResponse.isForMainFrame { shouldDownloadMainFrame = false }
            chat.report(policy.rejection(for: url))
            decisionHandler(.cancel)
            return
        }
        let response = navigationResponse.response
        let disposition = (response as? HTTPURLResponse)?.allHeaderFields.first {
            String(describing: $0.key).lowercased() == "content-disposition"
        }.map { String(describing: $0.value).components(separatedBy: ";")[0].trimmingCharacters(in: .whitespaces).lowercased() }
        let mime = response.mimeType?.lowercased()
        let isDocument = mime == "text/html" || mime == "application/xhtml+xml"
        if (navigationResponse.isForMainFrame && shouldDownloadMainFrame) || disposition == "attachment" ||
            !navigationResponse.canShowMIMEType || (navigationResponse.isForMainFrame && mime != nil && !isDocument) {
            // An attachment response in an iframe is still a download. Keep
            // displayable iframe documents on the normal navigation path.
            if #available(iOS 14.5, *), supportsResponseDownloads {
                attachmentNavigationURLs.insert(url)
                decisionHandler(.download)
            } else {
                attachmentNavigationURLs.insert(url)
                decisionHandler(.cancel)
                chat.report(CTChatError(stage: .download, host: url.host,
                                                code: NSURLErrorUnsupportedURL, domain: NSURLErrorDomain))
            }
            return
        }
        decisionHandler(.allow)
    }

    private func decideSecureNavigation(_ action: WKNavigationAction, webView: WKWebView,
                                        policy: CTSecurityPolicy,
                                        completion: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { completion(.cancel); return }
        let scheme = url.scheme?.lowercased()
        let activation = consumeUserLink(for: action)
        let userLink = activation.activated && action.sourceFrame.isMainFrame &&
            (action.targetFrame == nil || action.targetFrame?.isMainFrame == true)
        if scheme == "tel" || scheme == "mailto" {
            shouldDownloadMainFrame = false
            if userLink { UIApplication.shared.open(url, options: [:], completionHandler: nil) }
            completion(.cancel)
        } else if policy.allows(url) {
            if !supportsResponseDownloads, activation.activated, action.request.httpMethod == "GET",
               isAttachmentLink(url, hasDownloadAttribute: activation.download) {
                completion(.cancel)
                downloadAttachmentBeforeIOS145(request: action.request, webView: webView)
                return
            }
            if action.targetFrame == nil || action.targetFrame?.isMainFrame == true {
                attachmentNavigationURLs.removeAll()
                if userLink { shouldDownloadMainFrame = false }
                if #available(iOS 14.5, *), action.shouldPerformDownload {
                    // Follow redirects under the navigation policy and convert the final
                    // response once. Converting the action can create a cancelled download
                    // for an intermediate 302 while WebKit continues the navigation.
                    shouldDownloadMainFrame = true
                }
            }
            if action.targetFrame == nil {
                completion(.cancel)
                webView.load(action.request)
            } else {
                completion(.allow)
            }
        } else {
            if action.targetFrame == nil || action.targetFrame?.isMainFrame == true { shouldDownloadMainFrame = false }
            completion(.cancel)
            if userLink && (scheme == "https" || scheme == "http") {
                openURLInSafariViewController(url)
            } else {
                chat.report(policy.rejection(for: url))
            }
        }
    }
    
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let policy = chat.securityPolicy,
           navigationAction.request.url?.scheme?.lowercased() != "blob" {
            decideSecureNavigation(navigationAction, webView: webView, policy: policy, completion: decisionHandler)
            return
        }
        guard let url = navigationAction.request.url,
              url.absoluteString.hasPrefix("https") || url.absoluteString.hasPrefix("blob") || url.absoluteString.hasPrefix("http") || url.absoluteString.hasPrefix("tel:")  ||
                url.absoluteString.hasPrefix("mailto:"),
              checkValidity(of: url) else {
            decisionHandler(.cancel)
            return
        }
        
        guard url != chatURL else {
            decisionHandler(.allow)
            return
        }
        
        if url.absoluteString.hasPrefix("mailto:"){
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            decisionHandler(.cancel)
            return
        }
        
        if url.absoluteString.hasPrefix("tel:"){
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        
        if url.absoluteString.hasPrefix("blob") {
            
            var scriptDownl = ""

            scriptDownl = scriptDownl + "var xhr = new XMLHttpRequest();"
            scriptDownl = scriptDownl + "xhr.open('GET', '\(url)', true);"
            scriptDownl = scriptDownl + "xhr.responseType = 'blob';"
            scriptDownl = scriptDownl + "xhr.onload = function(e) { if (this.status == 200) { var blob = this.response; var reader = new window.FileReader(); reader.readAsDataURL(blob); reader.onloadend = function() { window.webkit.messageHandlers.readBlob.postMessage(reader.result); }}};"
            scriptDownl = scriptDownl + "xhr.send();"

            wkWebView.evaluateJavaScript(scriptDownl, completionHandler: nil);
            if (philip == 1){
                wkWebView.configuration.userContentController.add(scriptMessageHandler, name: "readBlob")
                philip = philip - 1
                
                //decisionHandler(.cancel)
            }
            decisionHandler(.cancel)
            return
        } else {
            var tapCheck =
        """
        function sendPressure(){
          return tapPressureStatus;
        }
        sendPressure();
        """
            webView.evaluateJavaScript(tapCheck) { (result, error) in
                if let error = error{
                    print(error)
                    return
                }
                if let result = result as? Bool {
                    print(result)
                    if (result == false){
                        self.openURLInSafariViewController(url)
                    }
                } else {
                    print(type(of: result),"not a boolean value")
                }
            }
            //Тут добавить проверку долго нажатия на клавиатуру
            //print(tapStatusSwift)
            //openURLInSafariViewController(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.cancel)

/*
        
        if url.absoluteURL.pathComponents.contains("file") && url.absoluteURL.pathComponents.contains("webchat") {
            loadAndDisplayDocumentFrom(url: url)
        } else {
            openURLInSafariViewController(url)
        }*/
        
        
    }
    
    
    public func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let policy = chat.securityPolicy
        CTTrustEvaluator.handle(challenge, policy: policy,
                                legacyCertificate: policy == nil ? chat.certificate : nil,
                                legacyBaseURL: chat.baseURL, reportError: chat.report,
                                completion: completionHandler)
    }

    private func checkValidity(of url: URL) -> Bool {
        let string = url.absoluteString.replacingOccurrences(of: "https://", with: "", options: .caseInsensitive).replacingOccurrences(of: "/", with: "", options: .caseInsensitive)
        let validIpAddressRegex = "^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$"
        return string.range(of: validIpAddressRegex, options: .regularExpression) == nil
    }
    
    //preview View Controller
    private func loadCustomViewIntoController(url: URL) {
        let customViewFrame = CGRect(x: 0, y: 50, width: view.bounds.width, height: view.bounds.height)
        let customView = UIView(frame: customViewFrame)
        customView.backgroundColor = .white
        let wkWebViewConfig = WKWebViewConfiguration()
        let wkWViewFrame = CGRect(x: 0, y: 50, width: view.bounds.width, height: view.bounds.height - 25)
        let wkWView = WKWebView(frame: wkWViewFrame, configuration: wkWebViewConfig)
        customView.addSubview(wkWView)
                         
        let backButtonFrame = CGRect(x: 5, y: 0, width: 50, height: 50)
        let backButton = UIButton(frame: backButtonFrame)
        if #available(iOS 13.0, *) {
            backButton.setImage(UIImage(systemName: "arrow.left"), for: .normal)
        } else {
            // Fallback on earlier versions
        }
        backButton.addTarget(self, action: #selector(goBack(_:)), for: .touchUpInside)
        customView.addSubview(backButton)
        
        let shareFrame = CGRect(x: customViewFrame.width - 55, y: 0, width: 50, height: 50)
        let shareButton = UIButton(frame: shareFrame)
        if #available(iOS 13.0, *) {
            shareButton.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
        } else {
            // Fallback on earlier versions
        }
        shareButton.addTarget(self, action: #selector(share(_:)), for: .touchUpInside)
        customView.addSubview(shareButton)
                         
        view.addSubview(customView)
        blobPreview = customView
        customView.isHidden = false
        let request = URLRequest(url: url)
        wkWView.load(request)
    }
    
    @objc func goBack(_ sender: Any) {
        closeBlobPreview()
    }

    private func closeBlobPreview() {
        blobPreview?.removeFromSuperview()
        blobPreview = nil
        blobFile = nil
    }

    @objc func share(_ sender: Any) {
        guard let file = blobFile, presentedViewController == nil else {
            return
        }
        let items = [file.url]
        let ac = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // Меню удерживает файл, даже если preview закроется до завершения отправки.
        ac.completionWithItemsHandler = { _, _, _, _ in withExtendedLifetime(file) {} }
        ac.popoverPresentationController?.sourceView = view
        ac.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        present(ac, animated: true)
    }

    private func handleDocument(messageBody: Any) {
        do {
            let document = try CTBlobDocument(messageBody: messageBody, mimeTypes: mimeTypes)
            guard blobFile == nil, attachmentTransfers.isEmpty, presentedViewController == nil else {
                throw CTChatError(stage: .download, host: chatURL?.host, code: 6)
            }
            let file = try document.write()
            if chat.securityPolicy != nil || document.fileExtension == "bin" {
                presentAttachment(at: file.url, cleanup: { file.remove() })
            } else if viewIfLoaded?.window != nil {
                blobFile = file
                loadCustomViewIntoController(url: file.url)
            }
            // Если контроллер уже закрыт, локальный владелец удалит файл при освобождении.
        } catch let error as CTChatError {
            chat.report(error)
        } catch {
            chat.report(CTChatError(stage: .download, url: chatURL, error: error))
        }
    }
    
}

// MARK: - WKScriptMessageHandler
extension CTChatViewController: WKScriptMessageHandler {
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "ctSecureLinkActivation" {
            guard chat.securityPolicy != nil, message.webView === wkWebView,
                  let body = message.body as? [String: Any],
                  body["token"] as? String == secureLinkToken else { return }
            pendingUserLink = (body["url"] as? String).flatMap(URL.init(string:)).map {
                (url: $0, download: body["download"] as? Bool == true,
                 frameURL: message.frameInfo.request.url, mainFrame: message.frameInfo.isMainFrame,
                 expiresAt: ProcessInfo.processInfo.systemUptime + 5)
            }
            return
        }
        /* uncomment if loggin needed
        if message.name == "logHandler" {
            debugPrint("LOG: \(message.body)")
        }
        */
         
        if message.name == "readBlob" {
            handleDocument(messageBody: message.body)
        }
        setInputAttribute()
        chat.registerPushNotifications()
    }
}

@available(iOS 14.5, *)
extension CTChatViewController {
    public func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        receiveAttachment(download)
    }

    public func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        receiveAttachment(download)
    }

    private func receiveAttachment(_ download: WKDownload) {
        shouldDownloadMainFrame = false
        if let url = download.originalRequest?.url { attachmentNavigationURLs.insert(url) }
        guard let policy = chat.securityPolicy else { download.cancel(nil); return }
        if #available(iOS 18.2, *), !download.originatingFrame.isMainFrame, !download.isUserInitiated {
            download.cancel(nil)
            return
        }
        guard attachmentTransfers.isEmpty, blobFile == nil, presentedViewController == nil else {
            download.cancel(nil)
            chat.report(CTChatError(stage: .download, host: download.originalRequest?.url?.host, code: 6))
            return
        }
        let identifier = ObjectIdentifier(download)
        let reportError = chat.report
        attachmentTransfers[identifier] = CTAttachmentTransfer(download: download, policy: policy) { [weak self] result in
            // Release state before onError/presentation so a retry can start immediately.
            self?.attachmentTransfers.removeValue(forKey: identifier)
            switch result {
            case .success(let fileURL):
                guard let self = self else {
                    try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
                    return
                }
                self.presentAttachment(at: fileURL)
            case .failure(let error):
                reportError(error)
            }
        }
    }
}

// WebKit удерживает посредника, но не контроллер: закрытый чат может освободиться.
private final class CTWeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var handler: WKScriptMessageHandler?

    init(_ handler: WKScriptMessageHandler) {
        self.handler = handler
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        handler?.userContentController(userContentController, didReceive: message)
    }
}

// Keep the lifecycle holder available on older iOS; only its WebKit entry points
// require 14.5. The cancel closure retains WKDownload, whose delegate is weak.
private final class CTAttachmentTransfer: NSObject {
    private let policy: CTSecurityPolicy
    private var currentURL: URL?
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    private var fileURL: URL?
    private var failure: CTChatError?
    private var cancelDownload: (() -> Void)?
    private var completion: ((Result<URL, CTChatError>) -> Void)?

    @available(iOS 14.5, *)
    init(download: WKDownload, policy: CTSecurityPolicy, completion: @escaping (Result<URL, CTChatError>) -> Void) {
        self.policy = policy
        self.currentURL = download.originalRequest?.url
        self.completion = completion
        super.init()
        cancelDownload = { download.cancel(nil) }
        download.delegate = self
    }

    deinit {
        cancelDownload?()
        if completion != nil { try? FileManager.default.removeItem(at: directory) }
    }

    private func finish(_ result: Result<URL, CTChatError>) {
        guard let callback = completion else { return }
        completion = nil
        cancelDownload = nil
        if case .failure = result { try? FileManager.default.removeItem(at: directory) }
        callback(result)
    }
}

@available(iOS 14.5, *)
extension CTAttachmentTransfer: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        currentURL = response.url
        guard response.url.map({ policy.allows($0) }) == true else {
            completionHandler(nil)
            finish(.failure(policy.rejection(for: response.url, stage: .download)))
            return
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            completionHandler(nil)
            finish(.failure(CTChatError(stage: .download, host: response.url?.host, code: http.statusCode, domain: "HTTP")))
            return
        }
        let destination = directory.appendingPathComponent(CTAttachmentRules.safeFilename(suggestedFilename))
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.protectionKey: FileProtectionType.complete])
            fileURL = destination
            completionHandler(destination)
        } catch {
            completionHandler(nil)
            finish(.failure(CTChatError(stage: .download, url: response.url, error: error)))
        }
    }

    func download(_ download: WKDownload, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                  decisionHandler: @escaping (WKDownload.RedirectPolicy) -> Void) {
        currentURL = request.url
        guard request.url.map({ policy.allows($0) }) == true else {
            decisionHandler(.cancel)
            finish(.failure(policy.rejection(for: request.url, stage: .download)))
            return
        }
        // WebKit owns the request, cookies and cross-host credential handling.
        decisionHandler(.allow)
    }

    func download(_ download: WKDownload, didReceive challenge: URLAuthenticationChallenge,
                  completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        CTTrustEvaluator.handle(challenge, policy: policy, legacyCertificate: nil, legacyBaseURL: nil,
                                reportError: { [weak self] error in
                                    DispatchQueue.main.async { self?.failure = error }
                                }, completion: { disposition, credential in
                                    DispatchQueue.main.async { completionHandler(disposition, credential) }
                                })
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let fileURL = fileURL else {
            finish(.failure(CTChatError(stage: .download, host: currentURL?.host,
                                        code: NSURLErrorCannotCreateFile, domain: NSURLErrorDomain)))
            return
        }
        finish(.success(fileURL))
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let stage: CTChatError.Stage = (-1206 ... -1200).contains((error as NSError).code) ? .tls : .download
        finish(.failure(failure ?? CTChatError(stage: stage, url: currentURL, error: error)))
    }
}
