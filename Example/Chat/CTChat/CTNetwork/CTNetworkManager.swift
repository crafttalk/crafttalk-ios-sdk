import Foundation

internal protocol FileLoader: AnyObject {
    func loadDocumentFrom(url: URL, completion: @escaping (Result<URL, Error>) -> Void)
}

internal final class CTNetworkManager: NSObject, FileLoader {
    private var baseURL: String!
    private var namespace: String!
    private var session: URLSession!
    private let temporaryDirectory: URL
    internal var securityPolicy: CTSecurityPolicy?
    internal var reportError: (CTChatError) -> Void = { _ in }
    private var invalidationCompletions: [() -> Void] = []
    private var isInvalidated = false

    init(configuration: URLSessionConfiguration = .ephemeral,
         temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        self.temporaryDirectory = temporaryDirectory
        super.init()
        let config = configuration.copy() as! URLSessionConfiguration
        config.tlsMinimumSupportedProtocol = .tlsProtocol12
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    internal func invalidate(completion: (() -> Void)? = nil) {
        lock.lock()
        let alreadyInvalidated = isInvalidated
        if !alreadyInvalidated, let completion = completion { invalidationCompletions.append(completion) }
        lock.unlock()
        if alreadyInvalidated { completion?(); return }
        session.invalidateAndCancel()
    }

    // A push response must never be appended to a concurrently downloaded file.
    private struct Download {
        let taskID: Int
        let completion: (Result<URL, Error>) -> Void
        let usesResponseFilename: Bool
        var data = Data()
    }
    private let lock = NSLock()
    private var download: Download?
    private var failures: [Int: CTChatError] = [:]

    internal func set(baseURL: String, namespace: String) {
        self.baseURL = baseURL
        self.namespace = namespace
    }

    internal func registerFCMToken(_ fcmToken: String, uuid: String) {
        let request = CTPushRegistationRequest(baseURL: baseURL, namespace: namespace, fcmToken: fcmToken, uuid: uuid).urlRequest()
        if let policy = securityPolicy, let url = request.url, !policy.allows(url) {
            reportError(policy.rejection(for: url, stage: .pushRegistration))
            return
        }
        session.dataTask(with: request).resume()
    }

    internal func loadDocumentFrom(url: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        loadDocumentFrom(url: url, webCookies: nil, completion: completion)
    }

    internal func loadDocumentFrom(url: URL, webCookies: [HTTPCookie]?, completion: @escaping (Result<URL, Error>) -> Void) {
        loadDocumentFrom(request: URLRequest(url: url), webCookies: webCookies, completion: completion)
    }

    internal func loadDocumentFrom(request: URLRequest, webCookies: [HTTPCookie]?, completion: @escaping (Result<URL, Error>) -> Void) {
        guard let url = request.url else {
            let error = CTChatError(stage: .download, host: nil, code: NSURLErrorBadURL, domain: NSURLErrorDomain)
            reportError(error)
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }
        if let policy = securityPolicy, !policy.allows(url) {
            let error = policy.rejection(for: url, stage: .download)
            reportError(error)
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }
        lock.lock()
        guard download == nil else {
            lock.unlock()
            let error = CTChatError(stage: .download, host: url.host, code: 6)
            reportError(error)
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }
        if let cookies = webCookies, let storage = session.configuration.httpCookieStorage {
            // Let Foundation select cookies by domain/path on each redirect. Never
            // forward a manually constructed Cookie/Authorization header to another host.
            storage.cookies?.forEach { storage.deleteCookie($0) }
            cookies.forEach { storage.setCookie($0) }
        }
        var downloadRequest = request
        if webCookies != nil {
            // WebKit may have populated a Cookie header on its request. Let the
            // session's cookie jar select cookies again for every redirect host.
            downloadRequest.setValue(nil, forHTTPHeaderField: "Cookie")
            downloadRequest.httpShouldHandleCookies = true
            // This is a standalone download, not a WebKit subresource. Keeping
            // the chat's mainDocumentURL makes Foundation reject cookies set by
            // another allowed host during redirects (.onlyFromMainDocumentDomain).
            downloadRequest.mainDocumentURL = nil
        }
        let task = session.dataTask(with: downloadRequest)
        download = Download(taskID: task.taskIdentifier, completion: completion, usesResponseFilename: webCookies != nil)
        lock.unlock()
        task.resume()
    }
}

extension CTNetworkManager: URLSessionDelegate, URLSessionDataDelegate {
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        lock.lock()
        isInvalidated = true
        let completions = invalidationCompletions
        invalidationCompletions.removeAll()
        lock.unlock()
        completions.forEach { $0() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Historically the native session used system trust, not the WebView's legacy pin.
        CTTrustEvaluator.handle(challenge, policy: securityPolicy,
                                legacyCertificate: nil, legacyBaseURL: nil, reportError: { error in
                                    self.lock.lock()
                                    self.failures[task.taskIdentifier] = error
                                    self.lock.unlock()
                                }, completion: completionHandler)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        if let policy = securityPolicy,
           request.url.map({ policy.allows($0) }) != true {
            lock.lock()
            failures[task.taskIdentifier] = policy.rejection(for: request.url)
            lock.unlock()
            task.cancel()
            completionHandler(nil)
            return
        }
        // Use Foundation's redirect request, preserving its method/body and credential handling.
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        if download?.taskID == dataTask.taskIdentifier { download?.data.append(data) }
        lock.unlock()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            lock.lock()
            let stage: CTChatError.Stage = download?.taskID == dataTask.taskIdentifier ? .download : .pushRegistration
            failures[dataTask.taskIdentifier] = CTChatError(stage: stage, host: response.url?.host,
                                                           code: http.statusCode, domain: "HTTP")
            lock.unlock()
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, willCacheResponse proposedResponse: CachedURLResponse,
                    completionHandler: @escaping (CachedURLResponse?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let active = download?.taskID == task.taskIdentifier ? download : nil
        if active != nil { download = nil }
        let recorded = failures.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        // Clear state before reporting failures, so onError can immediately retry.
        let isTLSError = error.map { (-1206 ... -1200).contains(($0 as NSError).code) } ?? false
        let stage: CTChatError.Stage = isTLSError ? .tls : (active == nil ? .pushRegistration : .download)
        if let failure = recorded ?? error.map({ CTChatError(stage: stage, url: task.currentRequest?.url, error: $0) }) {
            reportError(failure)
            if let active = active { DispatchQueue.main.async { active.completion(.failure(failure)) } }
            return
        }
        guard let active = active else { return }
        let directory = temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let suggested = active.usesResponseFilename ? task.response?.suggestedFilename : nil
        let name = CTAttachmentRules.safeFilename(suggested ?? task.currentRequest?.url?.lastPathComponent)
        let fileURL = directory.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            try active.data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            DispatchQueue.main.async { active.completion(.success(fileURL)) }
        } catch {
            try? FileManager.default.removeItem(at: directory)
            let failure = CTChatError(stage: .download, url: task.currentRequest?.url, error: error)
            reportError(failure)
            DispatchQueue.main.async { active.completion(.failure(failure)) }
        }
    }
}
