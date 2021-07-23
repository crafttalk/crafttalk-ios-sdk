//
//  CTBundleUtil.swift
//  Chat
//
//  Copyright © 2020 Crafttalk. All rights reserved.
//


import Foundation

internal final class CTBundleUtil {
    
    static var relevantBundles: [Bundle] {
        var bundles = [Bundle.main]
        let currentBundle = Bundle(for: self)
        if currentBundle != Bundle.main {
            bundles.append(currentBundle)
        }
        return bundles
    }
    
    static func certificatePath(with resourceName: String, and fileType: String, in bundles: [Bundle]) -> String? {
        for bundle in bundles {
            if let path = bundle.path(forResource: resourceName, ofType: fileType) {
                return path
            }
        }
        return nil
    }
    
    static let externalURLSchemes: [String] = {
        var result: [String] = []
        for bundle in relevantBundles {
            guard let urlTypes = bundle.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] else { continue }
            
            for urlTypeDictionary in urlTypes {
                guard let urlSchemes = urlTypeDictionary["CFBundleURLSchemes"] as? [String] else { continue }
                guard let externalURLScheme = urlSchemes.first else { continue }
                result.append(externalURLScheme)
            }
            
        }
        
        return result
    }()
    
}
