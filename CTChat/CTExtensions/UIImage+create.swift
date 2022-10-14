//
//  UIImage+create.swift
//  Chat
//
//  Created by Igor Bopp on 12.10.2022.
//  Copyright © 2022 Igor Bopp. All rights reserved.
//

import UIKit

extension UIImage {
    static func cross() -> UIImage {
        let path = UIBezierPath()
        path.lineCapStyle = .round
        
        path.move(to: CGPoint(x: 4, y: 4))
        path.addLine(to: CGPoint(x: 20, y: 20))
        
        path.move(to: CGPoint(x: 20, y: 4))
        path.addLine(to: CGPoint(x: 4, y: 20))
        
        return UIImage.create(
            with: path,
            size: CGSize(
                width: 24,
                height: 24
            )
        )
    }
    
    static func share() -> UIImage {
        let path = UIBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        
        path.move(to: CGPoint(x: 7, y: 7))
        path.addLine(to: CGPoint(x: 12, y: 2))
        path.addLine(to: CGPoint(x: 17, y: 7))
        
        path.move(to: CGPoint(x: 12, y: 3))
        path.addLine(to: CGPoint(x: 12, y: 21))
        
        path.move(to: CGPoint(x: 8, y: 12))
        path.addLine(to: CGPoint(x: 3, y: 12))
        path.addLine(to: CGPoint(x: 3, y: 21))
        path.addLine(to: CGPoint(x: 21, y: 21))
        path.addLine(to: CGPoint(x: 21, y: 12))
        path.addLine(to: CGPoint(x: 16, y: 12))
        
        return UIImage.create(
            with: path,
            size: CGSize(
                width: 24,
                height: 24
            )
        )
    }
    
    static func create(
        with path: UIBezierPath,
        size: CGSize
    ) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { _ in
            UIColor.blue.setStroke()
            path.lineWidth = 2
            path.stroke()
        }
    }
}
