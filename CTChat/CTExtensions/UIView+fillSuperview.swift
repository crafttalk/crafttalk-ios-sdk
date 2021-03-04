//
//  UIView+fillSuperviewFromSafeAreaLayoutGuideTopAnchor.swift
//  Chat
//
//  Copyright © 2020 Crafttalk. All rights reserved.
//

import UIKit

internal extension UIView {
    func fillSuperviewFromSafeAreaLayoutGuideTopAnchor() {
        translatesAutoresizingMaskIntoConstraints = false
        
        if let superview = superview {
            NSLayoutConstraint.activate([
                topAnchor.constraint(equalTo: superview.safeAreaLayoutGuide.topAnchor),
                bottomAnchor.constraint(equalTo: superview.bottomAnchor),
                leadingAnchor.constraint(equalTo: superview.leadingAnchor),
                trailingAnchor.constraint(equalTo: superview.trailingAnchor)
            ])
        }
    }
}
