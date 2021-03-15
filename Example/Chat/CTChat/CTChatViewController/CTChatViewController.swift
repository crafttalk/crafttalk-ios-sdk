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
    private var visitor: CTVisitior!
    
    // MARK: - Lifecycle
    
    convenience init() {
        self.init(nibName: nil, bundle: nil)
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        self.chatURL = CTChat.shared.webchatURL
        self.visitor = CTChat.shared.visitor
        self.setupWebView()
        
        NotificationCenter.default.addObserver(self, selector: #selector(scrollChatToBottom), name: UIResponder.keyboardWillShowNotification, object: nil)
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
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let visitor = String(data: (try! encoder.encode(self.visitor)), encoding: .utf8)!
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
        wkWebView.load(URLRequest(url: chatURL))
        self.wkWebView = wkWebView
    }
    
    /// Download the file from the given url and store it locally in the app's temp folder.
    /// - Parameter downloadUrl: File download url
    private func loadAndDisplayDocumentFrom(url downloadUrl : URL) {
        let localFileURL: URL = FileManager.default.temporaryDirectory.appendingPathComponent(downloadUrl.lastPathComponent)
        
        UIApplication.shared.isNetworkActivityIndicatorVisible = true
        URLSession.shared.dataTask(with: downloadUrl) { [weak self] data, response, err in
            guard let data = data, err == nil else {
                debugPrint("Error while downloading document from url=\(downloadUrl.absoluteString): \(err.debugDescription)")
                return
            }
            
            DispatchQueue.main.async {
                UIApplication.shared.isNetworkActivityIndicatorVisible = false
            }
            
            do {
                try data.write(to: localFileURL, options: .atomic)
                
                DispatchQueue.main.async {
                    
                    if let ctPreviewType = CTPreviewType(fileURL: localFileURL) {
                        self?.show(CTPreviewViewController.create(with: ctPreviewType), sender: nil)
                    } else {
                        let activityViewController = UIActivityViewController(activityItems: [localFileURL], applicationActivities: nil)
                        self?.present(activityViewController, animated: true, completion: nil)
                    }
                    
                }
                
            } catch {
                debugPrint(error)
                return
            }
        }.resume()
    }
    
    private func openURLInSafariViewController(_ url: URL) {
        let vc = SFSafariViewController(url: url)
        self.present(vc, animated: true)
    }
    
    private func setInputAttribute() {
        let source: String = """
            var inputElement = document.getElementById('webchat-file-input');
            inputElement.setAttribute('accept', 'image/jpg,image/jpeg,image/gif,image/img,.doc,.docx,.pdf,.txt');
            """
        wkWebView.evaluateJavaScript(source)
    }
    
    @objc
    private func scrollChatToBottom(notification: Notification) {
        let source: String = """
            var element = document.getElementsByClassName('webchat-dialog')[0];
            element.scrollTop = element.scrollHeight;
            """
        wkWebView.evaluateJavaScript(source)
    }
    
}

// MARK: - WKNavigationDelegate & WKUIDelegate
extension CTChatViewController: WKNavigationDelegate, WKUIDelegate {
    
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print(error.localizedDescription)
    }
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { }
    
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print(error.localizedDescription)
    }
    
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        
        guard let url = navigationAction.request.url, url != chatURL else {
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
    
}

// MARK: - WKScriptMessageHandler
extension CTChatViewController: WKScriptMessageHandler {
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        setInputAttribute()
        CTChat.shared.registerPushNotifications()
    }
}

