//
//  CTNetworkManager.swift
//  Chat
//
//  Copyright © 2020 Crafttalk. All rights reserved.
//

import Foundation

internal protocol FileLoader: class {
    func loadDocumentFrom(url downloadUrl : URL, completion: @escaping (URL)->())
}

internal final class CTNetworkManager: NSObject, FileLoader {
    
    // MARK: - Properties
    private var baseURL: String!
    private var namespace: String!
    
    private lazy var session: URLSession = {
        return URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
    }()
    
    private var receivedData: Data?
    private var loadFileCompletion: ((URL)->())?
    
    // MARK: - Methods
    internal func set(baseURL: String, namespace: String) {
        self.baseURL = baseURL
        self.namespace = namespace
    }
    
    internal func registerFCMToken(_ fcmToken: String, uuid: String) {
        let request = CTPushRegistationRequest(baseURL: baseURL, namespace: namespace, fcmToken: fcmToken, uuid: uuid)
        let task = session.dataTask(with: request.urlRequest())
        task.resume()
    }
    
    /// Download the file from the given url and store it locally in the app's temp folder.
    /// - Parameter downloadUrl: File download url
    internal func loadDocumentFrom(url downloadUrl : URL, completion: @escaping (URL)->()) {
        receivedData = Data()
        loadFileCompletion = completion
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
        
        if loadFileCompletion == nil {
            let httpResponse = response as? HTTPURLResponse
            if httpResponse?.statusCode == 200 {
                print("CTChat: FCMToken registred successfully")
            } else {
                print("CTChat: Failed to register fcmToken")
            }
        }
        
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, willCacheResponse proposedResponse: CachedURLResponse, completionHandler: @escaping (CachedURLResponse?) -> Void) {
        completionHandler(nil)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard error == nil else {
            print("Download completed with error: \(error!.localizedDescription)")
            return
        }
        
        if let data = receivedData, let loadFileCompletion = loadFileCompletion {
            let localFileURL: URL = FileManager.default.temporaryDirectory.appendingPathComponent(task.currentRequest!.url!.lastPathComponent)
            
            do {
                try data.write(to: localFileURL, options: .atomic)
                
                DispatchQueue.main.async {
                    loadFileCompletion(localFileURL)
                }
                
            } catch {
                debugPrint(error)
                return
            }
            self.loadFileCompletion = nil
            self.receivedData = nil
        }
    }
    
}

