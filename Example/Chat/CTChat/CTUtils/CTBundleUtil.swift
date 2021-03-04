//
//  CTBundleUtil.swift
//  Chat
//
//  Copyright © 2020 Crafttalk. All rights reserved.
//


import Foundation

internal final class CTBundleUtil {
    
    static var relevantBundles: [Bundle] {
        return [Bundle.main, Bundle(for: self)]
    }
    
    static func certificatePath(with resourceName: String, and fileType: String, in bundles: [Bundle]) -> String? {
        for bundle in bundles {
            if let path = bundle.path(forResource: resourceName, ofType: fileType) {
                return path
            }
        }
        return nil
    }
    
}
