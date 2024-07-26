//
//  CTChatViewController.swift
//  Chat
//
//  Copyright © 2020 Crafttalk. All rights reserved.
//

import UIKit
import WebKit
import SafariServices


//Данный класс используется в конструкторе storyboard, он нужен для отабражения веб-интерфейса с виджетом чата. также в этом классе хранятся методы управления виджетом через externalApi
@available(iOS 13.0, *)
public final class CTChatViewController: UIViewController, WKScriptMessageHandler {
    public static let shared: CTChatViewController = CTChatViewController()

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
    // Определяем переменные внутри класса
    private var wkWebView: WKWebView!
    private var chatURL: URL!
    private var visitor: CTVisitor!
    private var fileLoader: FileLoader!
    private var currentUserID: Int!

    @IBOutlet weak var rightButon: UIBarButtonItem!
    @IBAction func rightButtonPressed(_ sender: Any) {
        print("cordinate sending")
        sendCordinate(52.9646392, 36.0447363)
    }
    @IBOutlet weak var leftbutton: UIBarButtonItem!
    @IBAction func leftButtonPressed(_ sender: Any) {
        print("Left button pressed!")
        ratedialog5()
    }
    
    
    // MARK: - Lifecycle
    /// функция для авторизации пользовотеля
    ///
    /// выполняет js запрос в браузере и передаёт данные из программы в виджет чата
    public func loginUser(_ visitor: CTVisitor) {
        let visitorJSON = visitor.toJSON() ?? ""
        wkWebView.evaluateJavaScript("userData = \(visitorJSON); loginUserAction()") { (result, error) in
            if let error = error {
                print(error.localizedDescription)
            } else {
                print(result)
            }
        }
    }
    
    public func ratedialog5(){
        wkWebView.evaluateJavaScript("sendDialogScore5Action()") { (result, error) in
            if let error = error {
                print(error.localizedDescription)
            } else {
                print(result)
            }
        }
    }
    
    public func ratedialog4(){
        wkWebView.evaluateJavaScript("sendDialogScore4Action()") { (result, error) in
            if let error = error {
                print(error.localizedDescription)
            } else {
                print(result)
            }
        }
    }
    
    public func ratedialog3(){
        wkWebView.evaluateJavaScript("sendDialogScore3Action()") { (result, error) in
            if let error = error {
                print(error.localizedDescription)
            } else {
                print(result)
            }
        }
    }
    
    public func ratedialog2(){
        wkWebView.evaluateJavaScript("sendDialogScore2Action()") { (result, error) in
            if let error = error {
                print(error.localizedDescription)
            } else {
                print(result)
            }
        }
    }
    
    public func ratedialog1(){
        wkWebView.evaluateJavaScript("sendDialogScore1Action()") { (result, error) in
            if let error = error {
                print(error.localizedDescription)
            } else {
                print(result)
            }
        }
    }
    
    public func sendCordinate(_ lat: Float, _ lon: Float){
        let latString = "\(lat)"
        let lonString = "\(lon)"
        wkWebView.evaluateJavaScript("cordinate.lat = \(latString); cordinate.lon = \(lonString); sendCordinateAction()") { (result, error) in
            if let error = error {
                print(error.localizedDescription)
            } else {
                print(result)
            }
        }

    }
    
    
    convenience init() {
        self.init(nibName: nil, bundle: nil)
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        chatURL = CTChat.shared.webchatURL
        currentUserID = CTChat.shared.currentUserID
        visitor = CTChat.shared.userList[currentUserID]
        fileLoader = CTChat.shared.networkManager
        setupWebView()
        print("Chat scene loaded!")
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        print ("window reopen!")
        if CTChat.shared.userChanged == true {
            CTChat.shared.switchUserChanger()
            let currentUserID = CTChat.shared.currentUserID
            loginUser(CTChat.shared.userList[currentUserID])
        }
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        print("окно скрыто")
        if CTChat.shared.lowMemMode == true {
             //wkWebView = nil
            //print("ecomode work")
        }
        
    }
    
    // MARK: - Methods
    ///перезагрузить страницу с новыми параметрами
    public func reloadpage(){
        currentUserID = CTChat.shared.currentUserID
        visitor = CTChat.shared.userList[currentUserID]
    }
    
    ///функция настройки веб вида, отключает масштабирование окна и регестрирует нового пользователя
    var philip = 1
    private func setupWebView() {
        ///Отключает масштабирование в окне/виджете чата
        func getZoomDisableScript() -> WKUserScript {
            let source: String = "var meta = document.createElement('meta');" +
                "meta.name = 'viewport';" +
                "meta.content = 'width=device-width, initial-scale=1.0, maximum- scale=1.0, user-scalable=no';" +
                "var head = document.getElementsByTagName('head')[0];" + "head.appendChild(meta);"
            return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        }
        ///Авторизует пользователя в чате окна/виджета и загружает script eruda для консоли в браузере
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
        ///включает консоль в браузере
        ///
        ///в ctchat переменная isConsoleEnabled должна быть true
        func debugWebConsole() -> WKUserScript {
            let source: String = """
                \( CTChat.shared.isConsoleEnabled ? "javascript:(function () { var script = document.createElement('script'); script.src=\"//cdn.jsdelivr.net/npm/eruda\"; document.body.appendChild(script); script.onload = function () { eruda.init() } })();" : "")
            """
            return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        }
        
        func testScript1() -> WKUserScript {
            let source: String = """
            var element = document.createElement('script');
            element.textContent = "window.getWebChatCraftTalkExternalControl = (externalControl) => {console.log('ОНО РАБОТАЕТ АААААААААААААААААААААААА');}";
            document.body.appendChild(element);
            """
            return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        }
        ///добавить кнопки для управления externalApi
        ///
        ///сами кнопки не используются они нужны для активации команд externalapi, к кнопкам применяется параметр .style.display = "none"
        ///по сути костыль
        func invisibleButtonExternalApi() -> WKUserScript {
            let source: String = """
            var element = document.createElement('button');
            element.setAttribute("id", "sendLocation");
            element.textContent = 'sendCordinate';
            document.body.appendChild(element);
            
            var element1 = document.createElement('button');
            element1.setAttribute("id", "sendVisitorMessage");
            element1.textContent = 'sendMessage';
            document.body.appendChild(element1);
            
            var element2 = document.createElement('button');
            element2.setAttribute("id", "sendDialogScore1");
            element2.textContent = 'score1';
            document.body.appendChild(element2);
            
            var element3 = document.createElement('button');
            element3.setAttribute("id", "sendDialogScore2");
            element3.textContent = 'score2';
            document.body.appendChild(element3);
            
            var element4 = document.createElement('button');
            element4.setAttribute("id", "sendDialogScore3");
            element4.textContent = 'score3';
            document.body.appendChild(element4);
            
            var element5 = document.createElement('button');
            element5.setAttribute("id", "sendDialogScore4");
            element5.textContent = 'score4';
            document.body.appendChild(element5);
            
            var element6 = document.createElement('button');
            element6.setAttribute("id", "sendDialogScore5");
            element6.textContent = 'score5';
            document.body.appendChild(element6);
            
            var element7 = document.createElement('button');
            element7.setAttribute("id", "loginUser");
            element7.textContent = 'login';
            document.body.appendChild(element7);
            """
            return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        }
        //вторая часть externalApi скрывает отображение кнопок и биндить функции на них
        func invisibleButtonExternalApi2() -> WKUserScript {
            let visitor = self.visitor.toJSON() ?? ""
            let source: String = """
            var element8 = document.createElement('script');
            element8.textContent = "let cordinate = {lat: 52.9646392, lon: 36.0447363}; const sendLocationButton = document.getElementById('sendLocation'); sendLocationButton.style.display = 'none'; function sendCordinateAction(){const sendLocationButton = document.getElementById('sendLocation'); sendLocationButton.click();}; const sendVisitorMessageButton = document.getElementById('sendVisitorMessage'); sendVisitorMessageButton.style.display = 'none';  let visitorMessageText = 'SAMPLE'; function sendVisitorMessage(){const sendVisitorMessageButton = document.getElementById('sendVisitorMessage'); sendVisitorMessageButton.click();}; const sendDialogScore1Button = document.getElementById('sendDialogScore1'); const sendDialogScore2Button = document.getElementById('sendDialogScore2'); const sendDialogScore3Button = document.getElementById('sendDialogScore3'); const sendDialogScore4Button = document.getElementById('sendDialogScore4'); const sendDialogScore5Button = document.getElementById('sendDialogScore5'); sendDialogScore1Button.style.display = 'none'; sendDialogScore2Button.style.display = 'none'; sendDialogScore3Button.style.display = 'none'; sendDialogScore4Button.style.display = 'none'; sendDialogScore5Button.style.display = 'none'; function sendDialogScore1Action(){const sendDialogScore1Button = document.getElementById('sendDialogScore1'); sendDialogScore1Button.click();}; function sendDialogScore2Action(){ const sendDialogScore2Button = document.getElementById('sendDialogScore2'); sendDialogScore2Button.click();}; function sendDialogScore3Action(){const sendDialogScore3Button = document.getElementById('sendDialogScore3');sendDialogScore3Button.click();}; function sendDialogScore4Action(){const sendDialogScore4Button = document.getElementById('sendDialogScore4'); sendDialogScore4Button.click();}; function sendDialogScore5Action(){const sendDialogScore5Button = document.getElementById('sendDialogScore5'); sendDialogScore5Button.click();}; let userData = {first_name: '', last_name: '', uuid: '', email: '', phone: '', contarct: '', birthday: '', hash: '', customProperties: ''}; const loginUserButton = document.getElementById('loginUser'); loginUserButton.style.display = 'none'; function loginUserAction(){ const loginUserButton = document.getElementById('loginUser'); loginUserButton.click();} window.getWebChatCraftTalkExternalControl = (externalControl) => {const sendLocationButton = document.getElementById('sendLocation'); const sendVisitorMessageButton = document.getElementById('sendVisitorMessage'); const text = cordinate; sendLocationButton.addEventListener('click', () => {externalControl.sendMessage(JSON.stringify(text), 10); }); sendVisitorMessageButton.addEventListener('click', () =>{externalControl.sendMessage(JSON.stringify(visitorMessageText), 1); }); sendDialogScore1Button.addEventListener('click', () =>{externalControl.sendDialogScore(1); }); sendDialogScore2Button.addEventListener('click', () =>{externalControl.sendDialogScore(2); }); sendDialogScore3Button.addEventListener('click', () =>{ externalControl.sendDialogScore(3);}); sendDialogScore4Button.addEventListener('click', () =>{ externalControl.sendDialogScore(4);}); sendDialogScore5Button.addEventListener('click', () =>{externalControl.sendDialogScore(5);}); loginUserButton.addEventListener('click', () =>{ setTimeout(() => { externalControl.logout(); externalControl.closeWidget(); const newUser = userData; window.__WebchatUserCallback = function () { return newUser;};externalControl.login();}, 650);}); externalControl.on('webchatOpened', function () {console.log('Чат был открыт, успех! func extapi2 включена и работает!');}); externalControl.on('messageReceived', function () {console.log('ПОЛУЧЕНО СООБЩЕНИЕ ДЛЯ ПОЛЬЗОВАТЕЛЯ'); var message = 'this message send from web'; window.webkit.messageHandlers.observer.postMessage(message);});}";
            document.body.appendChild(element8);
            """
            return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        }
        ///третья часть с самим externalApi
        func invisibleButtonExternalApi3() -> WKUserScript {
            let source: String = """
            var element9 = document.createElement('script');
            element9.textContent = "window.getWebChatCraftTalkExternalControl = (externalControl) => {const sendLocationButton = document.getElementById('sendLocation'); const sendVisitorMessageButton = document.getElementById('sendVisitorMessage'); const text = {lat: 52.9646392,lon: 36.0447363}; sendLocationButton.addEventListener('click', () => {externalControl.sendMessage(JSON.stringify(text), 10); }); ";
            document.body.appendChild(element9);
            """
            return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        }
        
        let wkWebViewConfig = WKWebViewConfiguration()
        wkWebViewConfig.preferences.javaScriptEnabled = true
        //добавляем пользовательские скрипты
        wkWebViewConfig.userContentController.addUserScript(getZoomDisableScript())
        wkWebViewConfig.userContentController.addUserScript(getUserAuthScript())
        wkWebViewConfig.userContentController.addUserScript(debugWebConsole())
        
        wkWebViewConfig.userContentController.addUserScript(testScript1())
        wkWebViewConfig.userContentController.addUserScript(invisibleButtonExternalApi())
        wkWebViewConfig.userContentController.addUserScript(invisibleButtonExternalApi2())
        
        
        
        wkWebViewConfig.userContentController.add(self, name: "handler")
        //тестовая функция ниже
     
        
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
@available(iOS 13.0, *)
extension CTChatViewController: WKNavigationDelegate, WKUIDelegate {
    
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {}
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { }
    
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    }
    
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
@available(iOS 13.0, *)
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

