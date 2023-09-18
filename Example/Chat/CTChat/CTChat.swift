//
//  CTChat.swift
//  Chat
//
//  Copyright © 2020 Crafttalk. All rights reserved.
//

import Foundation

///Этот код представляет класс CTChat, который используется для конфигурации и управления функциональностью CraftTalk Chat SDK
///
///Все внутренние свойства и методы используются для внутренней логики работы SDK, в том числе для настройки сети, работы с сертификатом и другими задачами. Публичные методы предоставляют простой интерфейс для настройки и использования SDK в приложении.
public final class CTChat {
    
    // MARK: - Public Properties
    public static let shared: CTChat = CTChat()
    
    
    
    // MARK: - Internal Properties
    ///переменная отвечатет за включение экономного режима использования памяти
    ///
    ///На данный момнт при её активации окно с чатом при закрытии будет выгружатся из памяти
    internal var lowMemMode = true
    ///Включение консоли для JS библиотеки eruda,
    internal var isConsoleEnabled = true
    
    internal var salt: String = ""
    /// Webchat base url
    internal var baseURL: String = ""
    
    internal var namespace: String = ""
    
    internal var webchatURL: URL { URL(string: baseURL + "/webchat/" + namespace)! }
    
    //internal var visitor: CTVisitor! //старая переменная пользователя, легаси код все дела
    
    ///Список всех пользователей
    internal var userList: [CTVisitor] = []
    
    ///номер активного пользователя, нулевой пользователь это анонимус. но во время работы программы это можно поменять
    internal var currentUserID = 0 //
    
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
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let defaults = UserDefaults.standard
        
        //извлекаем из ПЗУ номер выбранного в прошлый запуск пользователя
        self.currentUserID = defaults.integer(forKey: "currentUserIDData")

        //данный код должен проверить сохранены ли какие нибудь пользователи в памяти и телефона и извлечь их оттуда в обратном случае он заносит туда анонимуса при первом запуске программы
        if let savedData = defaults.data(forKey: "userListData") {
            if let savedUserList = try? decoder.decode([CTVisitor].self, from: savedData){
                print("userListData was restored!")
                print(savedUserList)
                for element in savedUserList{
                    print(element.firstName! , element.uuid)
                }
                print(savedUserList.count)
                for element in savedUserList{
                    self.userList.append(element)
                }
            }
        }
        if let encodedData = try? encoder.encode(self.userList){
            defaults.set(encodedData, forKey: "userListData")
        }

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
    ///Добавляет нового пользователя в конец списка пользователей
    public func registerVisitor(_ visitor: CTVisitor) {
        self.userList.append(visitor)
    }
    ///Удаляет выбранного пользователя из списка, также проверяет что currentuserId указывает на правильный элемент массива пользователей и не ссылается в пустоту
    public func deleteUser(_ position: Int){
        
        userList.remove(at: position)
        if currentUserID + 1 > userList.count{
            print("КРИТИЧЕСКАЯ ОШИБКА, ССЫЛАЕМСЯ НА НЕСУЩЕСТВУЮЩЕГО ПОЛЬЗОВАТЕЛЯ!!!!!!!1111!!!111")
            currentUserID = currentUserID - 1
        }
        if userList.isEmpty {
            print("КРИТИЧЕСКАЯ ОШИБКА, ПОЛЬЗОВАТЕЛЬ УДАЛИЛ ВСЕХ!!!!!!!1111!!!111")
            let uuid =  UUID().uuidString
            let visitor = CTVisitor(firstName: "Anonymous", lastName: "", uuid: uuid, customProperties: ["custom" : "123"])
            registerVisitor(visitor)
            currentUserID = 0
        }
    }
    
    ///Выводит в консоль имена и айди всех пользователей из списка
    public func showAllUser(){
        for element in userList{
            print(element.firstName! , element.uuid)
        }
        print(userList.count)
    }
    ///Возвращает имя пользователя, в качестве параметра задаётся номер в списке
    ///
    ///Используется для формирования списка всех пользователей в графическом интрефейсе программы
    public func userName(_ position: Int) -> String{
        return userList[position].firstName ?? "no name"
    }
    ///Возвращает фамилию пользователя, в качестве параметра задаётся номер в списке
    ///
    ///Используется для формирования списка всех пользователей в графическом интрефейсе программы
    public func userLastName(_ position: Int) -> String{
        return userList[position].lastName ?? "no lastname"
    }
    ///Меняет id текущего выбранного пользователя, а также сохраняет его  в пзу
    public func switchUser(_ number: Int){
        self.currentUserID = number
        let defaults = UserDefaults.standard
        defaults.set(number, forKey: "currentUserIDData")
    }
    ///Сохраняет в ПЗУ Список пользователей
    public func saveUserList(){
        let encoder = JSONEncoder()
        let defaults = UserDefaults.standard
        if let encodedData = try? encoder.encode(self.userList){
            defaults.set(encodedData, forKey: "userListData")
        }
        
    }
    
    
    public func saveFCMToken(_ fcmToken: String) {
        self.fcmToken = fcmToken
    }
    
    // MARK: - Internal methods
    
    ///регистрирует токен push-уведомлений на сервере
    ///
    ///Функция сначала проверяет, пуст ли токен fcmToken. Если он пуст, функция возвращает ничего. Если токен fcmToken не пуст, функция создает локальную копию токена и идентификатора пользователя. Функция затем использует библиотеку ctqueue для планирования задачи, которая должна быть выполнена через 5 секунд. Задача состоит в вызове функции networkManager.registerFCMToken(localFCMToken, uuid: localUUID), которая регистрирует токен push-уведомлений на сервере.
    internal func registerPushNotifications() {
        guard !fcmToken.isEmpty else { return }
        let localFCMToken = fcmToken
        let localUUID = userList[currentUserID].uuid
        ctqueue.asyncAfter(deadline: .now() + .seconds(5)) {
            self.networkManager.registerFCMToken(localFCMToken, uuid: localUUID)
        }
    }
    
}
