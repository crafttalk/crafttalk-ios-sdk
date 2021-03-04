//
//  CTNetworkManager.swift
//  Chat
//
//  Copyright © 2020 Crafttalk. All rights reserved.
//

import Foundation

internal final class CTNetworkManager {
    
    // MARK: - Properties
    private var baseURL: String!
    private var namespace: String!
    
    // MARK: - Methods
    internal func set(baseURL: String, namespace: String) {
        self.baseURL = baseURL
        self.namespace = namespace
    }
    
    internal func registerFCMToken(_ fcmToken: String, uuid: String) {
        
        let request = CTPushRegistationRequest(baseURL: baseURL, namespace: namespace, fcmToken: fcmToken, uuid: uuid)
        URLSession.shared.dataTask(with: request.urlRequest()) { data, response, error in
            
            if let error = error {
                print(error.localizedDescription)
            }
            
            let httpResponse = response as? HTTPURLResponse
            if httpResponse?.statusCode == 200 {
                print("CTChat: FCMToken registred successfully")
            } else {
                print("CTChat: Failed to register fcmToken")
            }
            
        }.resume()
        
    }
    
}

