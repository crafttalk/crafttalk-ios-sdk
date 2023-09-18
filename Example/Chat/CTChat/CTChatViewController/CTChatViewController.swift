//
//  CTChatViewController.swift
//  Chat
//
//  Copyright © 2020 Crafttalk. All rights reserved.
//

import UIKit
import WebKit
import SafariServices

//Данный класс используется в конструкторе storyboard, он нужен для отабражения веб-интерфейса с виджетом чата
@available(iOS 13.0, *)
public final class CTChatViewController: UIViewController {
    
    // MARK: - Properties
    // Определяем переменные внутри класса
    private var wkWebView: WKWebView!
    private var chatURL: URL!
    private var visitor: CTVisitor!
    private var fileLoader: FileLoader!
    private var currentUserID: Int!

    @IBOutlet weak var leftbutton: UIBarButtonItem!
    @IBAction func leftButtonPressed(_ sender: Any) {
        print("Left button pressed!")
        CTChat.shared.switchUser(0)
        wkWebView.evaluateJavaScript("userData.uuid = '2cadfd06-e8a6-4ccd-ad38-855271015671'; loginUserAction()") { (result, error) in
            if let error = error {
                print(error.localizedDescription)
            } else {
                print(result)
            }
        }
        
        
    }
    
    
    // MARK: - Lifecycle
    
    
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
        if currentUserID != CTChat.shared.currentUserID{
            print("user was chanched!")
            currentUserID = CTChat.shared.currentUserID
            visitor = CTChat.shared.userList[currentUserID]
            wkWebView = nil
            setupWebView()
            
        }
        
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        print("окно скрыто")
        if CTChat.shared.lowMemMode == true {
            wkWebView = nil
            print("ecomode work")
        }
        
    }
    
    // MARK: - Methods
    ///перезагрузить страницу с новыми параметрами
    public func reloadpage(){
        currentUserID = CTChat.shared.currentUserID
        visitor = CTChat.shared.userList[currentUserID]
    }
    
    ///функция настройки веб вида, отключает масштабирование окна и регестрирует нового пользователя
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
            element8.textContent = "const sendLocationButton = document.getElementById('sendLocation'); sendLocationButton.style.display = 'none'; function sendCordinateAction(){const sendLocationButton = document.getElementById('sendLocation'); sendLocationButton.click();}; const sendVisitorMessageButton = document.getElementById('sendVisitorMessage'); sendVisitorMessageButton.style.display = 'none';  let visitorMessageText = 'SAMPLE: hello i am visitor! code:phi249'; function sendVisitorMessage(){const sendVisitorMessageButton = document.getElementById('sendVisitorMessage'); sendVisitorMessageButton.click();}; const sendDialogScore1Button = document.getElementById('sendDialogScore1'); const sendDialogScore2Button = document.getElementById('sendDialogScore2'); const sendDialogScore3Button = document.getElementById('sendDialogScore3'); const sendDialogScore4Button = document.getElementById('sendDialogScore4'); const sendDialogScore5Button = document.getElementById('sendDialogScore5'); sendDialogScore1Button.style.display = 'none'; sendDialogScore2Button.style.display = 'none'; sendDialogScore3Button.style.display = 'none'; sendDialogScore4Button.style.display = 'none'; sendDialogScore5Button.style.display = 'none'; function sendDialogScore1Action(){const sendDialogScore1Button = document.getElementById('sendDialogScore1'); sendDialogScore1Button.click();}; function sendDialogScore2Action(){ const sendDialogScore2Button = document.getElementById('sendDialogScore2'); sendDialogScore2Button.click();}; function sendDialogScore3Action(){const sendDialogScore3Button = document.getElementById('sendDialogScore3');sendDialogScore3Button.click();}; function sendDialogScore4Action(){const sendDialogScore4Button = document.getElementById('sendDialogScore4'); sendDialogScore4Button.click();}; function sendDialogScore5Action(){const sendDialogScore5Button = document.getElementById('sendDialogScore5'); sendDialogScore5Button.click();}; let userData = { uuid: '', first_name: '', last_name: '', contract: ''}; const loginUserButton = document.getElementById('loginUser'); loginUserButton.style.display = 'none'; function loginUserAction(){ const loginUserButton = document.getElementById('loginUser'); loginUserButton.click();} window.getWebChatCraftTalkExternalControl = (externalControl) => {const sendLocationButton = document.getElementById('sendLocation'); const sendVisitorMessageButton = document.getElementById('sendVisitorMessage'); const text = {lat: 52.9646392,lon: 36.0447363}; sendLocationButton.addEventListener('click', () => {externalControl.sendMessage(JSON.stringify(text), 10); }); sendVisitorMessageButton.addEventListener('click', () =>{externalControl.sendMessage(JSON.stringify(visitorMessageText), 1); }); sendDialogScore1Button.addEventListener('click', () =>{externalControl.sendDialogScore(1); }); sendDialogScore2Button.addEventListener('click', () =>{externalControl.sendDialogScore(2); }); sendDialogScore3Button.addEventListener('click', () =>{ externalControl.sendDialogScore(3);}); sendDialogScore4Button.addEventListener('click', () =>{ externalControl.sendDialogScore(4);}); sendDialogScore5Button.addEventListener('click', () =>{externalControl.sendDialogScore(5);}); loginUserButton.addEventListener('click', () =>{ setTimeout(() => { externalControl.logout(); externalControl.closeWidget(); const newUser = userData; window.__WebchatUserCallback = function () { return newUser;};externalControl.login();}, 1333);}); externalControl.on('webchatOpened', function () {console.log('Чат был открыт, успех! func extapi2 включена и работает!');}); externalControl.on('messageReceived', function () {console.log('ПОЛУЧЕНО СООБЩЕНИЕ ДЛЯ ПОЛЬЗОВАТЕЛЯ');});}";
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
              url.absoluteString.hasPrefix("https"),
              checkValidity(of: url) else {
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
    
}

// MARK: - WKScriptMessageHandler
@available(iOS 13.0, *)
extension CTChatViewController: WKScriptMessageHandler {
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        setInputAttribute()
        CTChat.shared.registerPushNotifications()
    }
}
