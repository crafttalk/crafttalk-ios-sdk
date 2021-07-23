//
//  CTVideoView.swift
//  Chat
//
//  Copyright © 2020 Crafttalk. All rights reserved.
//

import UIKit
import AVFoundation

internal protocol CTVideoViewDelegate: AnyObject {
    func videoStateChanged(isPlaying: Bool)
}

internal final class CTVideoView: UIView {
    
    // MARK: - Properties
    private var player: AVPlayer!
    private var playerLayer: AVPlayerLayer!
    
    private var isPlaying = false
    
    weak var delegate: CTVideoViewDelegate!
    
    // MARK: - Lifecycle
    
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = self.bounds
    }
    
    // MARK: - Methods
    internal func set(video videoURL: URL) {
        player?.pause()
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        
        player = AVPlayer(url: videoURL)
        playerLayer = AVPlayerLayer(player: player)
        self.layer.addSublayer(playerLayer)
    }
    
    internal func playButtonPressed() {
        !isPlaying ? setOnPlay() : setOnPause()
    }
    
    internal func fastForwardButtonPressed() {
        setOnPause()
        let newTime = player.currentTime() + CMTime(seconds: 5, preferredTimescale: 600)
        player.seek(to: newTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    internal func rewindButtonPressed() {
        setOnPause()
        let newTime = player.currentTime() - CMTime(seconds: 5, preferredTimescale: 600)
        player.seek(to: newTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    private func setOnPlay() {
        isPlaying = true
        player.play()
        
        delegate.videoStateChanged(isPlaying: isPlaying)
    }
    
    private func setOnPause() {
        isPlaying = false
        player.pause()
        
        delegate.videoStateChanged(isPlaying: isPlaying)
    }
    
}
