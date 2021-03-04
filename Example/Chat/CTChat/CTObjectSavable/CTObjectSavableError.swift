//
//  CTObjectSavableError.swift
//  Chat
//
//  Copyright © 2020 Crafttalk. All rights reserved.
//

import Foundation

internal enum CTObjectSavableError: String, LocalizedError {
    case unableToEncode = "Unable to encode object into data"
    case noValue = "No data object found for the given key"
    case unableToDecode = "Unable to decode object into given type"
    
    var errorDescription: String? {
        rawValue
    }
}
