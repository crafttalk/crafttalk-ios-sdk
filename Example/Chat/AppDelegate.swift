//
//  AppDelegate.swift
//  Chat
//
//  Copyright © 2020 Crafttalk. All rights reserved.
//

import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        FirebaseApp.configure()
        RCValues.shared.loadingDoneCallback = {
            CTChat.shared.configure(baseURL: RCValues.shared.string(forKey: .webchatURL),
                                    namespace: RCValues.shared.string(forKey: .namespace),
                                    salt: RCValues.shared.string(forKey: .salt),
                                    isConsoleEnabled: RCValues.shared.bool(forKey: .erudaToggle))
        }

        let uuid = UserDefaults.standard.string(forKey: "uuid") ?? UUID().uuidString
        UserDefaults.standard.set(uuid, forKey: "uuid")
        let visitor = CTVisitor(firstName: "iOSExample", lastName: "", uuid: uuid, customProperties: ["custom" : "123"])
        
        CTChat.shared.registerVisitor(visitor)
        
        registerAppForRemoteNotifications(application: application)
        
        return true
    }
    
    
}

// Push notifications
extension AppDelegate: MessagingDelegate, UNUserNotificationCenterDelegate {
    
    private func registerAppForRemoteNotifications(application: UIApplication) {
        Messaging.messaging().delegate = self
        
        if #available(iOS 10.0, *) {
            UNUserNotificationCenter.current().delegate = self
            UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound],
                completionHandler: { isGranted, error in
                    guard error == nil else { return }
                })
        } else {
            let settings: UIUserNotificationSettings =
                UIUserNotificationSettings(types: [.alert, .badge, .sound], categories: nil)
            application.registerUserNotificationSettings(settings)
        }
        
        application.registerForRemoteNotifications()
    }
    
    @available(iOS 10.0, *)
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        print(userInfo)
        completionHandler()
    }
    
    // MARK: - MessagingDelegate
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken = fcmToken else { return }
        print("fcmToken: ", fcmToken)
        CTChat.shared.saveFCMToken(fcmToken)
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) {
        
        // Print full message.
        print(userInfo)
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // Print full message.
        print(userInfo)
        
        completionHandler(UIBackgroundFetchResult.newData)
    }
    
}

extension CTChat {
    
    func configure(baseURL: String, namespace: String, salt: String, isConsoleEnabled: Bool) {
        print(baseURL, namespace, salt, isConsoleEnabled)
        self.baseURL = baseURL
        self.salt = salt
        self.namespace = namespace
        self.isConsoleEnabled = isConsoleEnabled
        self.networkManager.set(baseURL: baseURL, namespace: namespace)
    }
    
}
