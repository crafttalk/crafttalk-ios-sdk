//
//  CTChat.swift
//  Chat
//
//  Copyright © 2020 Crafttalk. All rights reserved.
//

import Foundation

public final class CTChat {
    
    // MARK: - Public Properties
    public static let shared: CTChat = CTChat()
    /// Loading, trust and navigation errors, delivered on the main queue.
    public var onError: ((Error) -> Void)?
    
    // MARK: - Internal Properties
    
    internal var isConsoleEnabled = false
    internal private(set) var securityPolicy: CTSecurityPolicy?
    
    internal var salt: String = ""
    /// Webchat base url
    internal var baseURL: String = ""
    
    internal var namespace: String = ""
    
    internal var webchatURL: URL { URL(string: baseURL + "/webchat/" + namespace)! }
    
    internal var visitor: CTVisitor!
    
    internal lazy var certificate: Data? = {
        let certName = "CTCertificate"
        let certTypes = ["der", "cer", "crt"]
        
        var certPath: String?
        let bundles = CTBundleUtil.relevantBundles
        for certType in certTypes {
            if let path = CTBundleUtil.certificatePath(with: certName, and: certType, in: bundles) {
                certPath = path
                break
            }
        }
        
        if let certPath = certPath, let cert = FileManager.default.contents(atPath: certPath) {
            return cert
        }
        return nil
    }()
    
    internal let networkManager: CTNetworkManager = CTNetworkManager()
    
    // MARK: - Private Properties
    private var fcmToken: String = ""
    
    public let ctqueue = DispatchQueue(label: "crafttalk.chat.queue", qos: .utility, attributes: [.concurrent])
    
    // MARK: - Public methods
    public func configure() {
        securityPolicy = nil
        configureFromInfoPlist()
    }

    /// Validates synchronously. An invalid configuration leaves the previous policy intact.
    /// Info.plist initialization remains asynchronous, just as in configure().
    public func configure(security: CTSecurityConfiguration) throws {
        let url = (Bundle.main.object(forInfoDictionaryKey: "CTChatBaseURL") as? String).flatMap(URL.init(string:))
        let policy = try CTSecurityPolicy(configuration: security, baseURL: url)
        securityPolicy = policy
        configureFromInfoPlist()
    }

    private func configureFromInfoPlist() {
        ctqueue.async {
            guard let baseURL = Bundle.main.object(forInfoDictionaryKey: "CTChatBaseURL") as? String else {
                fatalError("CTChat: No CTChatBaseURL in Info.plist")
            }
            guard URL(string: baseURL) != nil else {
                fatalError("CTChat: Incorrect baseURL")
            }
            guard let salt = Bundle.main.object(forInfoDictionaryKey: "CTChatBaseURL") as? String else {
                fatalError("CTChat: No CTSalt in Info.plist")
            }
            guard let namespace = Bundle.main.object(forInfoDictionaryKey: "CTChatNamespace") as? String else {
                fatalError("CTChat: No CTChatNamespace in Info.plist")
            }
            
            self.baseURL = baseURL
            self.salt = salt
            self.namespace = namespace
            
            self.networkManager.set(baseURL: baseURL, namespace: namespace)
            
        }
    }
    
    public func registerVisitor(_ visitor: CTVisitor) {
        self.visitor = visitor
    }
    
    public func saveFCMToken(_ fcmToken: String) {
        self.fcmToken = fcmToken
    }
    
    // MARK: - Internal methods
    internal func report(_ error: CTChatError) {
        DispatchQueue.main.async { self.onError?(error) }
    }

    internal func registerPushNotifications() {
        guard !fcmToken.isEmpty else { return }
        let localFCMToken = fcmToken
        let localUUID = visitor.uuid
        ctqueue.asyncAfter(deadline: .now() + .seconds(5)) {
            self.networkManager.registerFCMToken(localFCMToken, uuid: localUUID)
        }
    }
    
}
