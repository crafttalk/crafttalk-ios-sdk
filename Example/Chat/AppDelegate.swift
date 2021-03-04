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
        
        CTChat.shared.configure()
        if !UserDefaults.standard.bool(forKey: "visitorRegistered") {
            CTChat.shared.registerVisitor(.init(firstName: "iOSExample", lastName: "hey"))
            UserDefaults.standard.set(true, forKey: "visitorRegistered")
        }
        
        
        registerAppForRemoteNotifications(application: application)
        
        return true
    }
    
    
}

// Push notifications
extension AppDelegate: MessagingDelegate, UNUserNotificationCenterDelegate {
    
    private func registerAppForRemoteNotifications(application: UIApplication) {
        FirebaseApp.configure()
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
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String) {
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
