//
//  CTPushRegistationRequest.swift
//  Chat
//
//  Copyright © 2020 Crafttalk. All rights reserved.
//

import Foundation

internal enum RequestHTTPMethod: String {
    case get = "GET"
    case post = "POST"
}

internal struct CTPushRegistationRequest {
    
    private let subscription: String
    private let uuid: String
    
    // MARK: - Properties
    private let baseURL: String
    private let namespace: String
    
    private var path: String { "/webchat/\(namespace)/set-user-subscription" }
    
    private let method: RequestHTTPMethod = .post
    
    private let headers = ["Content-Type" : "application/json"]
    
    private var body: [String: Any?] {
        return [
            "subscription": subscription,
            "uuid" : uuid
        ]
    }
    
    // MARK: - Initialization
    internal init(baseURL: String, namespace: String, fcmToken: String, uuid: String) {
        self.baseURL = baseURL
        self.namespace = namespace
        self.subscription = fcmToken
        self.uuid = uuid
    }
    
    // MARK: - Internal methods
    internal func urlRequest() -> URLRequest {
        let endpoint: String = baseURL.appending(path)
        var request: URLRequest = URLRequest(url: URL(string: endpoint)!)
        
        request.httpMethod = method.rawValue
        
        for header in headers {
            request.addValue(header.value, forHTTPHeaderField: header.key)
        }
        
        if method == RequestHTTPMethod.post {
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body, options: JSONSerialization.WritingOptions.prettyPrinted)
            } catch let error {
                print("Request body parse error: \(error.localizedDescription)")
            }
        }
        
        return request
    }
    
}
