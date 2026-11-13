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
    
    internal var webchatURL: URL {
        URL(string: baseURL + "/webchat/" + namespace)!
    }
    
    internal var visitor: CTVisitor!
    
    internal lazy var certificate: Data? = CTBundleUtil.certificateData(in: certificateBundles())

    internal let networkManager: CTNetworkManager

    // MARK: - Private Properties
    private var fcmToken: String = ""
    private let infoValue: (String) -> Any?
    private let certificateBundles: () -> [Bundle]
    private let schedulePush: ((TimeInterval, @escaping () -> Void) -> Void)?

    internal init(infoValue: @escaping (String) -> Any? = { Bundle.main.object(forInfoDictionaryKey: $0) },
                  networkManager: CTNetworkManager = CTNetworkManager(),
                  certificateBundles: @escaping () -> [Bundle] = { CTBundleUtil.relevantBundles },
                  schedulePush: ((TimeInterval, @escaping () -> Void) -> Void)? = nil) {
        self.infoValue = infoValue
        self.networkManager = networkManager
        self.certificateBundles = certificateBundles
        self.schedulePush = schedulePush
        networkManager.reportError = { [weak self] in self?.report($0) }
    }

    deinit {
        networkManager.invalidate()
    }
    
    public let ctqueue = DispatchQueue(label: "crafttalk.chat.queue", qos: .utility, attributes: [.concurrent])
    
    // MARK: - Public methods
    public func configure() {
        do {
            let settings = try readSettings()
            apply(settings, policy: nil)
        } catch let error as CTChatError {
            report(error)
        } catch {
            report(CTChatError(stage: .configuration, host: nil, code: 4))
        }
    }

    /// Проверяет и применяет настройки до возврата; при ошибке сохраняет предыдущую конфигурацию.
    public func configure(security: CTSecurityConfiguration) throws {
        let settings = try readSettings()
        let policy = try CTSecurityPolicy(configuration: security, baseURL: URL(string: settings.baseURL))
        apply(settings, policy: policy)
    }

    private struct Settings {
        let baseURL: String
        let salt: String
        let namespace: String
    }

    private func readSettings() throws -> Settings {
        guard let baseURL = infoValue("CTChatBaseURL") as? String,
              let url = URL(string: baseURL),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.query == nil, url.fragment == nil else {
            throw CTChatError(stage: .configuration, host: nil, code: 4)
        }
        guard let salt = infoValue("CTSalt") as? String else {
            throw CTChatError(stage: .configuration, host: nil, code: 7)
        }
        guard let namespace = infoValue("CTChatNamespace") as? String,
              let chatURL = URL(string: baseURL + "/webchat/" + namespace),
              chatURL.query == nil, chatURL.fragment == nil else {
            throw CTChatError(stage: .configuration, host: nil, code: 8)
        }
        return Settings(baseURL: baseURL, salt: salt, namespace: namespace)
    }

    private func apply(_ settings: Settings, policy: CTSecurityPolicy?) {
        // Все проверки завершены до первой записи. Настройка вызывается до открытия чата.
        baseURL = settings.baseURL
        salt = settings.salt
        namespace = settings.namespace
        networkManager.set(baseURL: settings.baseURL, namespace: settings.namespace)
        securityPolicy = policy
        networkManager.securityPolicy = policy
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
        let action = {
            self.networkManager.registerFCMToken(localFCMToken, uuid: localUUID)
        }
        if let schedulePush = schedulePush {
            schedulePush(5, action)
        } else {
            ctqueue.asyncAfter(deadline: .now() + .seconds(5), execute: action)
        }
    }
}
