//
//  CTPreviewViewController.swift
//  Chat
//
//  Copyright © 2020 Crafttalk. All rights reserved.
//

import Foundation
import UIKit
import PDFKit

internal enum CTPreviewType {
    case pdf(fileURL: URL)
    case image(fileURL: URL)
    case video(fileURL: URL)
    
    init?(fileURL: URL) {
        if fileURL.containsPDF {
            self = .pdf(fileURL: fileURL)
        } else if fileURL.containsImage {
            self = .image(fileURL: fileURL)
        } else if fileURL.containsVideo {
            self = .video(fileURL: fileURL)
        } else {
            return nil
        }
    }
}

internal final class CTPreviewViewController: UIViewController, CTVideoViewDelegate {
    
    // MARK: - Subviews
    private lazy var pdfView: PDFView = {
        let pdfView = PDFView()
        pdfView.displayMode = .singlePageContinuous
        pdfView.autoScales = true
        pdfView.displayDirection = .vertical
        
        return pdfView
    }()
    
    private lazy var imageScrollView: CTImageScrollView = {
        return CTImageScrollView(frame: view.frame)
    }()
    
    private lazy var videoView: CTVideoView = {
       return CTVideoView()
    }()
    
    // MARK: - Properties
    private var previewType: CTPreviewType!
    
    // MARK: - Lifecycle
    internal override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .white
        
        self.setupNavigationBarButtonItems()
        self.setupNeededView(for: self.previewType)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if case CTPreviewType.image(_) = previewType! {
            imageScrollView.setupForCurrentDeviceOrientation()
        }
    }
    
    // MARK: - Methods
    internal static func create(with previewType: CTPreviewType) -> UIViewController {
        let previewViewController = CTPreviewViewController()
        previewViewController.previewType = previewType
        
        return UINavigationController(rootViewController: previewViewController)
    }
    
    // MARK: - Setup subviews
    private func setupNavigationBarButtonItems() {
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneButtonPressed))
        navigationItem.setRightBarButton(doneButton, animated: false)
        
        let saveButton = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(saveButtonPressed))
        navigationItem.setLeftBarButton(saveButton, animated: false)
    }
    
    private func setupNeededView(for previewType: CTPreviewType) {
        switch previewType {
        case .pdf(let fileURL):
            setupPDFView(pdfURL: fileURL)
        case .image(let fileURL):
            setupImagePreview(imageURL: fileURL)
        case .video(let fileURL):
            setupVideoPreview(videoURL: fileURL)
        }
    }
    
    private func setupPDFView(pdfURL: URL) {
        guard let document = PDFDocument(url: pdfURL) else { return }
        view.addSubview(pdfView)
        pdfView.fillSuperviewFromSafeAreaLayoutGuideTopAnchor()
        pdfView.document = document
    }
    
    private func setupImagePreview(imageURL: URL) {
        guard let imageData = try? Data(contentsOf: imageURL), let image = UIImage(data: imageData) else { return }
        view.addSubview(imageScrollView)
        imageScrollView.fillSuperviewFromSafeAreaLayoutGuideTopAnchor()
        imageScrollView.set(image: image)
    }
    
    private func setupVideoPreview(videoURL: URL) {
        view.addSubview(videoView)
        videoView.fillSuperviewFromSafeAreaLayoutGuideTopAnchor()
        videoView.set(video: videoURL)
        videoView.delegate = self
        
        // setup toolbar
        self.navigationController?.isToolbarHidden = false
        
        var items = [UIBarButtonItem]()
        
        items.append(UIBarButtonItem(barButtonSystemItem: .rewind, target: self, action: #selector(rewindButtonPressed)))
        items.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))
        items.append(UIBarButtonItem(barButtonSystemItem: .play, target: self, action: #selector(playButtonPressed)))
        items.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))
        items.append(UIBarButtonItem(barButtonSystemItem: .fastForward, target: self, action: #selector(fastForwardButtonPressed)))
        
        self.toolbarItems = items
    }
    
    // MARK: - CTVideoViewDelegate
    
    func videoStateChanged(isPlaying: Bool) {
        guard var items = toolbarItems else { return }
        if isPlaying {
            items[2] = UIBarButtonItem(barButtonSystemItem: .pause, target: self, action: #selector(playButtonPressed))
        } else {
            items[2] = UIBarButtonItem(barButtonSystemItem: .play, target: self, action: #selector(playButtonPressed))
        }
        self.toolbarItems = items
    }
    
    // MARK: - Button handling
    @objc
    private func doneButtonPressed() {
        DispatchQueue.main.async {
            self.dismiss(animated: true, completion: nil)
        }
    }
    
    @objc
    private func saveButtonPressed() {
        guard let previewType = previewType else { return }
        let localFileURL: URL
        switch previewType {
        case .pdf(let fileURL):
            localFileURL = fileURL
        case .image(let fileURL):
            localFileURL = fileURL
        case .video(let fileURL):
            localFileURL = fileURL
        }
        DispatchQueue.main.async { [weak self] in
            let activityViewController = UIActivityViewController(activityItems: [localFileURL], applicationActivities: nil)
            self?.present(activityViewController, animated: true, completion: nil)
        }
    }
    
    @objc
    private func playButtonPressed() {
        videoView.playButtonPressed()
    }
    
    @objc
    private func fastForwardButtonPressed() {
        videoView.fastForwardButtonPressed()
    }
    
    @objc
    private func rewindButtonPressed() {
        videoView.rewindButtonPressed()
    }
    
}
