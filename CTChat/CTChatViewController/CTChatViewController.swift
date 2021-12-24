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
    
    // MARK: - Properties
    private var wkWebView: WKWebView!
    private var chatURL: URL!
    private var visitor: CTVisitor!
    private var fileLoader: FileLoader!
    
    // MARK: - Lifecycle
    
    convenience init() {
        self.init(nibName: nil, bundle: nil)
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        chatURL = CTChat.shared.webchatURL
        visitor = CTChat.shared.visitor
        fileLoader = CTChat.shared.networkManager
        setupWebView()
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
    }
    
    // MARK: - Methods
    
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
                window.__WebchatUserCallback = function() {
                    webkit.messageHandlers.handler.postMessage("User registred");
                    return \(visitor);
                };
                """
            return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        }
        
        let wkWebViewConfig = WKWebViewConfiguration()
        wkWebViewConfig.preferences.javaScriptEnabled = true
        wkWebViewConfig.userContentController.addUserScript(getZoomDisableScript())
        wkWebViewConfig.userContentController.addUserScript(getUserAuthScript())
        wkWebViewConfig.userContentController.add(self, name: "handler")
        
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
    
    /// Download the file from the given url and store it locally in the app's temp folder.
    /// - Parameter downloadUrl: File download url
    private func loadAndDisplayDocumentFrom(url downloadUrl : URL) {
        guard presentedViewController == nil && !(presentedViewController is CTPreviewViewController) && !(presentedViewController is UIActivityViewController) else { return }
        UIApplication.shared.isNetworkActivityIndicatorVisible = true
        fileLoader.loadDocumentFrom(url: downloadUrl) { [weak self] (localFileURL) in
            UIApplication.shared.isNetworkActivityIndicatorVisible = false
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
    
    private func setInputAttribute() {
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
    
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {}
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { }
    
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {}
    
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, !url.absoluteString.contains("about:blank") else {
            decisionHandler(.allow)
            return
        }
        guard url.absoluteString.hasPrefix("https") else {
            makeACallIfNeeded(usingURL: url)
            decisionHandler(.cancel)
            return
        }
        guard checkValidity(of: url) else {
            decisionHandler(.cancel)
            return
        }
        guard url != chatURL else {
            decisionHandler(.allow)
            return
        }
        if url.absoluteURL.pathComponents.contains("file") && url.absoluteURL.pathComponents.contains("webchat") {
            loadAndDisplayDocumentFrom(url: url)
        } else {
            openURLInSafariViewController(url)
        }
        decisionHandler(.cancel)
        
    }
    
    
    public func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        /**
         * Listening to this delegate method to avoid of `SSL Pinning`
         * and `man-in-the-middle` attacks. Is required have certificate in
         * main bundle e.g. `CTCertificate.cer`
         */
        guard CTChat.shared.certificate != nil else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        let protectionSpace = challenge.protectionSpace
        guard protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              CTChat.shared.baseURL.contains(protectionSpace.host) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard let serverTrust = protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        if checkValidity(of: serverTrust) {
            // Pinning succeed
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            // Pinning failed
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
    
    private func checkValidity(of serverTrust: SecTrust) -> Bool {
        var secresult = SecTrustResultType.invalid
        let status = SecTrustEvaluate(serverTrust, &secresult)
        
        guard errSecSuccess == status,
              let serverCertificate = SecTrustGetCertificateAtIndex(serverTrust, 0),
              let cert2 = CTChat.shared.certificate else { return false }
        
        let serverCertificateData = SecCertificateCopyData(serverCertificate)
        let data = CFDataGetBytePtr(serverCertificateData)
        let size = CFDataGetLength(serverCertificateData)
        let cert1 = NSData(bytes: data, length: size)
        
        return cert1.isEqual(to: cert2)
    }
    
    private func checkValidity(of url: URL) -> Bool {
        let string = url.absoluteString.replacingOccurrences(of: "https://", with: "", options: .caseInsensitive).replacingOccurrences(of: "/", with: "", options: .caseInsensitive)
        let validIpAddressRegex = "^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$"
        return string.range(of: validIpAddressRegex, options: .regularExpression) == nil
    }
    
    private func makeACallIfNeeded(usingURL url: URL) {
        let string = url.absoluteString
        guard string.hasPrefix("tel:"),
              let phoneURL = URL(string: "tel://\(string.digits))"),
              UIApplication.shared.canOpenURL(phoneURL)
        else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - WKScriptMessageHandler
extension CTChatViewController: WKScriptMessageHandler {
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        setInputAttribute()
        CTChat.shared.registerPushNotifications()
    }
}

// MARK: String extension
private extension String {
    var digits: String {
        components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
    }
}
