//
//  CTVisitor.swift
//  Chat
//
//  Copyright © 2020 Crafttalk. All rights reserved.
//

import Foundation
import CommonCrypto

public final class CTVisitor {
    
    // MARK: - Properties
    let firstName: String?
    let lastName: String?
    let uuid: String
    let email: String?
    let phone: String?
    let contract: String?
    let birthday: String?
    let hash: String
    let customProperties: [String: Any]?
    
    // MARK: - Initialization
    public init(firstName: String? = nil,
                lastName: String? = nil,
                email: String? = nil,
                phone: String? = nil,
                contract: String? = nil,
                birthday: String? = nil,
                uuid: String,
                hash: String? = nil,
                customProperties: [String: Any]? = nil) {
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.phone = phone
        self.contract = contract
        self.birthday = birthday
        self.uuid = uuid
        self.hash = hash ?? CTVisitor.calculateHash(salt: CTChat.shared.salt,
                                             sourceString: "\(uuid)\(firstName ?? "")\(lastName ?? "")\(contract ?? "")\(phone ?? "")\(email ?? "")\(birthday ?? "")")
        self.customProperties = customProperties
    }
    
    // MARK: - Methods
    
    private static func calculateHash(salt: String, sourceString: String) -> String {
        guard let firstData = (salt + sourceString).data(using: .utf8) else {
            return ""
        }
        var tempHash = [UInt8](repeating: 0,  count: Int(CC_SHA256_DIGEST_LENGTH))
        firstData.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG($0.count), &tempHash)
        }
        guard let secondData = (salt + tempHash.map { String(format: "%02hhx", $0) }.joined()).data(using: .utf8) else {
            return ""
        }
        var hash = [UInt8](repeating: 0,  count: Int(CC_SHA256_DIGEST_LENGTH))
        secondData.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG($0.count), &hash)
        }
        return hash.map { String(format: "%02hhx", $0) }.joined()
    }
    
    func toJSON() -> String? {
        let jsonObject = NSMutableDictionary()
        jsonObject.setValue(firstName, forKey: "first_name")
        jsonObject.setValue(lastName, forKey: "last_name")
        jsonObject.setValue(uuid, forKey: "uuid")
        jsonObject.setValue(email, forKey: "email")
        jsonObject.setValue(phone, forKey: "phone")
        jsonObject.setValue(contract, forKey: "contract")
        jsonObject.setValue(birthday, forKey: "birthday")
        jsonObject.setValue(hash, forKey: "hash")
        
        if let customProperties = customProperties,
           JSONSerialization.isValidJSONObject(customProperties) {
            
            customProperties.forEach { (arg) in
                jsonObject.setValue(arg.value, forKey: arg.key)
            }
            
        }
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
            let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }
        
        return jsonString
    }
    
}
