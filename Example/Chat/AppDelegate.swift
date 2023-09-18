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
//Этот код предназначен для конфигурации CTChat и FirebaseApp, а также для регистрации пользователя и получения уведомлений Push в приложении iOS.

class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        FirebaseApp.configure()
        CTChat.shared.configure()
        //условие ниже не работает при первом запуске программы, его нужно исправить!
        if UserDefaults.standard.object(forKey: "userListData") == nil {
            // Данные по указанному ключу уже сохранены
            //CTChat.shared.currentUserID = 0 //если программа не запускается из-за ошибки логина первого пользователя
            print("Данные уже сохранены")
            
        } else {
            // Данных по указанному ключу нет
            print("Данных нет")
            let uuid =  UUID().uuidString
            let visitor = CTVisitor(firstName: "Anonymous", lastName: "", uuid: uuid, customProperties: ["custom" : "123"])
            CTChat.shared.registerVisitor(visitor)
            
            
        }
            
            
        
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

//этот метод позволяет настроить различные параметры для объекта CTChat, такие как базовый URL, пространство имен, соль и флаг включения/отключения консоли.
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
