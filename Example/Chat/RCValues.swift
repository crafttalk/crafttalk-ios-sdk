import Foundation
import Firebase


//перечисляемый тип
enum ValueKey: String {
    case webchatURL = "webchat_url"
    case namespace = "namespace"
    case salt = "salt"
    case erudaToggle = "eruda_toggle"
}


//Этот код представляет класс RCValues, который используется для работы с Remote Config - сервисом Firebase, предназначенным для динамической настройки приложения без его повторной сборки и обновления.
final class RCValues {
    
    static let shared = RCValues()
    var loadingDoneCallback: (() -> ())?
    var fetchComplete: Bool = false
    
    private init() {
        loadDefaultValues()
        fetchCloudValues()
    }
    
    func loadDefaultValues() {
        let appDefaults: [String: Any?] = [
            ValueKey.webchatURL.rawValue : "",
            ValueKey.namespace.rawValue : "",
            ValueKey.salt.rawValue : "",
            ValueKey.erudaToggle.rawValue : false
        ]
        RemoteConfig.remoteConfig().setDefaults(appDefaults as? [String: NSObject])
    }
    
    func fetchCloudValues() {
        RemoteConfig.remoteConfig().fetch() {
            [weak self] (status, error) in
            
            if status == .success {
                print("Config fetched!")
                RemoteConfig.remoteConfig().activate { (_, _) in }
            }
            else {
                print("Config not fetched")
                print("Error: \(error?.localizedDescription ?? "No error available.")")
            }
            
            self?.fetchComplete = true
            self?.loadingDoneCallback?()
            
        }
    }
    
    func integer(forKey key: ValueKey) -> Int {
        return RemoteConfig.remoteConfig()[key.rawValue].numberValue.intValue
    }
    
    func array<T>(forKey key: ValueKey) -> [T]? {
        return RemoteConfig.remoteConfig()[key.rawValue].jsonValue as? [T]
    }
    
    func string(forKey key: ValueKey) -> String {
        return RemoteConfig.remoteConfig()[key.rawValue].stringValue ?? ""
    }
    
    func bool(forKey key: ValueKey) -> Bool {
        return RemoteConfig.remoteConfig()[key.rawValue].boolValue
    }
    
}
