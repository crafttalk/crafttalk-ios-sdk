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
    
    internal let mimeTypes = [
        "html": "text/html",
        "htm": "text/html",
        "shtml": "text/html",
        "css": "text/css",
        "xml": "text/xml",
        "gif": "image/gif",
        "jpeg": "image/jpeg",
        "jpg": "image/jpeg",
        "js": "application/javascript",
        "atom": "application/atom+xml",
        "rss": "application/rss+xml",
        "mml": "text/mathml",
        "txt": "text/plain",
        "jad": "text/vnd.sun.j2me.app-descriptor",
        "wml": "text/vnd.wap.wml",
        "htc": "text/x-component",
        "png": "image/png",
        "tif": "image/tiff",
        "tiff": "image/tiff",
        "wbmp": "image/vnd.wap.wbmp",
        "ico": "image/x-icon",
        "jng": "image/x-jng",
        "bmp": "image/x-ms-bmp",
        "svg": "image/svg+xml",
        "svgz": "image/svg+xml",
        "webp": "image/webp",
        "woff": "application/font-woff",
        "jar": "application/java-archive",
        "war": "application/java-archive",
        "ear": "application/java-archive",
        "json": "application/json",
        "hqx": "application/mac-binhex40",
        "doc": "application/msword",
        "pdf": "application/pdf",
        "ps": "application/postscript",
        "eps": "application/postscript",
        "ai": "application/postscript",
        "rtf": "application/rtf",
        "m3u8": "application/vnd.apple.mpegurl",
        "xls": "application/vnd.ms-excel",
        "eot": "application/vnd.ms-fontobject",
        "ppt": "application/vnd.ms-powerpoint",
        "wmlc": "application/vnd.wap.wmlc",
        "kml": "application/vnd.google-earth.kml+xml",
        "kmz": "application/vnd.google-earth.kmz",
        "7z": "application/x-7z-compressed",
        "cco": "application/x-cocoa",
        "jardiff": "application/x-java-archive-diff",
        "jnlp": "application/x-java-jnlp-file",
        "run": "application/x-makeself",
        "pl": "application/x-perl",
        "pm": "application/x-perl",
        "prc": "application/x-pilot",
        "pdb": "application/x-pilot",
        "rar": "application/x-rar-compressed",
        "rpm": "application/x-redhat-package-manager",
        "sea": "application/x-sea",
        "swf": "application/x-shockwave-flash",
        "sit": "application/x-stuffit",
        "tcl": "application/x-tcl",
        "tk": "application/x-tcl",
        "der": "application/x-x509-ca-cert",
        "pem": "application/x-x509-ca-cert",
        "crt": "application/x-x509-ca-cert",
        "xpi": "application/x-xpinstall",
        "xhtml": "application/xhtml+xml",
        "xspf": "application/xspf+xml",
        "zip": "application/zip",
        "bin": "application/octet-stream",
        "exe": "application/octet-stream",
        "dll": "application/octet-stream",
        "deb": "application/octet-stream",
        "dmg": "application/octet-stream",
        "iso": "application/octet-stream",
        "img": "application/octet-stream",
        "msi": "application/octet-stream",
        "msp": "application/octet-stream",
        "msm": "application/octet-stream",
        "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "mid": "audio/midi",
        "midi": "audio/midi",
        "kar": "audio/midi",
        "mp3": "audio/mpeg",
        "ogg": "audio/ogg",
        "m4a": "audio/x-m4a",
        "ra": "audio/x-realaudio",
        "3gpp": "video/3gpp",
        "3gp": "video/3gpp",
        "ts": "video/mp2t",
        "mp4": "video/mp4",
        "mpeg": "video/mpeg",
        "mpg": "video/mpeg",
        "mov": "video/quicktime",
        "webm": "video/webm",
        "flv": "video/x-flv",
        "m4v": "video/x-m4v",
        "mng": "video/x-mng",
        "asx": "video/x-ms-asf",
        "asf": "video/x-ms-asf",
        "wmv": "video/x-ms-wmv",
        "avi": "video/x-msvideo"
    ]

    private var shareItem: URL?
    
    
    
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
    var philip = 1
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
                \( CTChat.shared.isConsoleEnabled ? "javascript:(function () { var script = document.createElement('script'); script.src=\"//cdn.jsdelivr.net/npm/eruda\"; document.body.appendChild(script); script.onload = function () { eruda.init() } })();" : "")
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
        guard let url = navigationAction.request.url,
              url.absoluteString.hasPrefix("https") || url.absoluteString.hasPrefix("blob") || url.absoluteString.hasPrefix("http") || url.absoluteString.hasPrefix("tel:") ,
              checkValidity(of: url) else {
            decisionHandler(.cancel)
            return
        }
        
        guard url != chatURL else {
            decisionHandler(.allow)
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
                wkWebView.configuration.userContentController.add(self, name: "readBlob")
                philip = philip - 1
                
                //decisionHandler(.cancel)
            }
            decisionHandler(.cancel)
            return
        } else {
            openURLInSafariViewController(url)
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
    
    //preview View Controller
    private func loadCustomViewIntoController(html: Data, url: URL) {
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
                         
        UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.addSubview(customView)
        customView.isHidden = false
        let request = URLRequest(url: url)
        wkWView.load(request)
    }
    
    @objc func goBack(_ sender: Any) {
        let button = (sender as! UIButton)
        button.superview?.removeFromSuperview()
    }

    @objc func share(_ sender: Any) {
        guard let shareItem else {
            return
        }
        let items = [shareItem]
        let ac = UIActivityViewController(activityItems: items, applicationActivities: nil)
        present(ac, animated: true)
    }

    private func handleDocument(messageBody: String) {
        // messageBody is in the format ;data:;base64,
          
        // split on the first ";", to reveal the filename
        let filenameSplits = messageBody.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
                            
        // split the remaining part on the first ",", to reveal the base64 data
        let dataSplits = filenameSplits[1].split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        
        let mime = filenameSplits[0].split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)[1]
     
        
        let ext = mimeTypes.key(from: String(mime))
        
        let filename = String(Date().timeIntervalSince1970) + "." + ext!
        
        let data = Data(base64Encoded: String(dataSplits[1]))
          
        _ = Data(base64Encoded: String(dataSplits[1]))
     
        if (data == nil) {
            debugPrint("Could not construct data from base64")
            return
        }
          
        let localFileURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename.removingPercentEncoding ?? filename)
          
        do {
            try data!.write(to: localFileURL);
            shareItem = localFileURL
            loadCustomViewIntoController(html: data!, url: localFileURL)
        } catch {
            debugPrint(error)
            return
        }
    }
    
}

// MARK: - WKScriptMessageHandler
extension CTChatViewController: WKScriptMessageHandler {
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        /* uncomment if loggin needed
        if message.name == "logHandler" {
            debugPrint("LOG: \(message.body)")
        }
        */
         
        if message.name == "readBlob" {
            handleDocument(messageBody: message.body as! String)
        }
        setInputAttribute()
        CTChat.shared.registerPushNotifications()
    }
}

extension Dictionary where Value: Equatable {
    func key(from value: Value) -> Key? {
        return self.first(where: { $0.value == value })?.key
    }
}
