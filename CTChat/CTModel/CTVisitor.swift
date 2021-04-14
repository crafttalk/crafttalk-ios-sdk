//
//  CTVisitor.swift
//  Chat
//
//  Copyright © 2020 Crafttalk. All rights reserved.
//

import Foundation
import CommonCrypto

public final class CTVisitior: Codable {
    
    // MARK: - Properties
    let firstName: String
    let lastName: String
    let uuid: String
    let email: String
    let phone: String
    let contract: String
    let birthday: String
    let hash: String
    
    // MARK: - Initialization
    public init(firstName: String,
                lastName: String,
                email: String = "default_email@gmail.com",
                phone: String = "81234567890",
                contract: String = "default_contract",
                birthday: String = "01.01.1970",
                uuid: String = UUID().uuidString.lowercased(),
                hash: String? = nil) {
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.phone = phone
        self.contract = contract
        self.birthday = birthday
        self.uuid = uuid
        self.hash = hash ?? CTVisitior.calculateHash(salt: CTChat.shared.salt,
                                             sourceString: "\(uuid)\(firstName)\(lastName)\(contract)\(phone)\(email)\(birthday)")
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
    
}
