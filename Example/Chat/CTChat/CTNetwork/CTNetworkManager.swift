//
//  CTNetworkManager.swift
//  Chat
//
//  Copyright © 2020 Crafttalk. All rights reserved.
//

import Foundation

internal protocol FileLoader: AnyObject {
    func loadDocumentFrom(url downloadUrl : URL, completion: @escaping (URL)->())
}

internal final class CTNetworkManager: NSObject, FileLoader {
    
    // MARK: - Properties
    private var baseURL: String!
    private var namespace: String!
    
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.tlsMinimumSupportedProtocol = .tlsProtocol12
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    private var receivedData: Data?
    private var loadFileCompletion: ((URL)->())?
    
    // MARK: - Methods
    internal func set(baseURL: String, namespace: String) {
        self.baseURL = baseURL
        self.namespace = namespace
    }
    ///регистрирует токен push-уведомлений на сервере.
    ///
    ///Функция registerFCMToken(_:uuid:) принимает токен push-уведомлений и идентификатор пользователя в качестве входных параметров и возвращает Void. Функция сначала создает экземпляр класса CTPushRegistationRequest с токеном push-уведомлений, идентификатором пользователя, базовым URL-адресом и пространством имен. Затем функция создает экземпляр класса URLSessionDataTask с запросом CTPushRegistationRequest и запускает задачу. Задача отправляет запрос на сервер и возвращает ответ сервера.
    internal func registerFCMToken(_ fcmToken: String, uuid: String) {
        let request = CTPushRegistationRequest(baseURL: baseURL, namespace: namespace, fcmToken: fcmToken, uuid: uuid)
        let task = session.dataTask(with: request.urlRequest())
        task.resume()
    }
    
    /// Download the file from the given url and store it locally in the app's temp folder.
    /// - Parameter downloadUrl: File download url
    internal func loadDocumentFrom(url downloadUrl : URL, completion: @escaping (URL)->()) {
        guard loadFileCompletion == nil else { return }
        loadFileCompletion = completion
        receivedData = Data()
        session.dataTask(with: downloadUrl).resume()
    }
    
}

extension CTNetworkManager: URLSessionDelegate, URLSessionDataDelegate, URLSessionTaskDelegate {
    
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        
        if loadFileCompletion != nil {
            receivedData?.append(data)
        }
        
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, willCacheResponse proposedResponse: CachedURLResponse, completionHandler: @escaping (CachedURLResponse?) -> Void) {
        completionHandler(nil)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard error == nil else { return }
        
        if let data = receivedData, let loadFileCompletion = loadFileCompletion {
            let localFileURL: URL = FileManager.default.temporaryDirectory.appendingPathComponent(task.currentRequest!.url!.lastPathComponent)
            
            do {
                try data.write(to: localFileURL, options: [.atomic, .completeFileProtection])
                
                DispatchQueue.main.async {
                    loadFileCompletion(localFileURL)
                }
                
            } catch { }
            self.loadFileCompletion = nil
            self.receivedData = nil
        }
    }
    
}

