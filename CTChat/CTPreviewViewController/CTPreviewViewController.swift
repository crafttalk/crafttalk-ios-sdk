//
//  CTPreviewViewController.swift
//  Chat
//
//  Copyright © 2020 Crafttalk. All rights reserved.
//

import Foundation
import UIKit
import PDFKit
import Photos

internal enum CTPreviewType: Equatable {
    case pdf(fileURL: URL)
    case image(fileURL: URL)
    case video(fileURL: URL)
    
    var isPDF: Bool {
        guard case .pdf = self else { return false }
        return true
    }
    
    var isImage: Bool {
        guard case .image = self else { return false }
        return true
    }
    
    var isVideo: Bool {
        guard case .video = self else { return false }
        return true
    }
    
    var name: String {
        switch self {
        case .pdf(_): return "PDF файл"
        case .image(_): return "изображение"
        case .video(_): return "видео"
        }
    }
    
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
    
    static func ==(lhs: CTPreviewType, rhs: CTPreviewType) -> Bool {
        switch (lhs, rhs) {
        case (.image(fileURL: _), .image(fileURL: _)): return true
        case (.pdf(fileURL: _), .pdf(fileURL: _)): return true
        case (.video(fileURL: _), .video(fileURL: _)): return true
        default:
            return false
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
    
    private lazy var imageScrollView = CTImageScrollView(frame: view.frame)
    private lazy var videoView = CTVideoView()
  
    
    // MARK: - Properties
    private var previewType: CTPreviewType!
    private var localFileURL: URL!
    
    // MARK: - Lifecycle
    internal override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .white
        
        self.setupNavigationBarButtonItems()
        self.setupNeededView(for: self.previewType)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if case .image(_) = previewType {
            imageScrollView.setupForCurrentDeviceOrientation()
        }
    }
    
    deinit {
        try? FileManager.default.removeItem(at: localFileURL)
    }
    
    // MARK: - Methods
    internal static func create(with previewType: CTPreviewType) -> UIViewController {
        let previewViewController = CTPreviewViewController()
        previewViewController.previewType = previewType
        
        let navigationController = UINavigationController(rootViewController: previewViewController)
        
        switch previewType {
        case .image(_), .video(_):
            navigationController.modalPresentationStyle = .fullScreen
        default:
            break
        }
        
        return navigationController
    }
    
    // MARK: - Setup subviews
    private func setupNavigationBarButtonItems() {
        let doneButton = { () -> UIBarButtonItem in
            if case .pdf(_) = previewType  {
                return UIBarButtonItem(
                    image: UIImage.cross(),
                    style: .done,
                    target: self,
                    action: #selector(doneButtonPressed)
                )
            }
            else {
                return UIBarButtonItem(
                    title: NSLocalizedString(
                        "Закрыть",
                        comment: "Close button"
                    ),
                    style: .done,
                    target: self,
                    action: #selector(doneButtonPressed)
                )
            }
        }()
        navigationItem.setLeftBarButton(
            doneButton,
            animated: false
        )
        
        let saveButton = UIBarButtonItem(
            image: UIImage.share(),
            style: .done,
            target: self,
            action: #selector(saveButtonPressed)
        )
        navigationItem.setRightBarButton(
            saveButton,
            animated: false
        )
    }
    
    private func setupNeededView(for previewType: CTPreviewType) {
        switch previewType {
        case .pdf(let fileURL):
            localFileURL = fileURL
            setupPDFView(pdfURL: fileURL)
        case .image(let fileURL):
            localFileURL = fileURL
            setupImagePreview(imageURL: fileURL)
        case .video(let fileURL):
            localFileURL = fileURL
            setupVideoPreview(videoURL: fileURL)
        }
    }
    
    private func setupPDFView(pdfURL: URL) {
        guard let document = PDFDocument(url: pdfURL) else { showErrorAlert(); return }
        view.addSubview(pdfView)
        pdfView.fillSuperviewFromSafeAreaLayoutGuideTopAnchor()
        pdfView.document = document
    }
    
    private func setupImagePreview(imageURL: URL) {
        guard let imageData = try? Data(contentsOf: imageURL), let image = UIImage(data: imageData) else { showErrorAlert(); return }
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
    
    private func checkPermission(for previewType: CTPreviewType) -> Bool {
        guard previewType.isVideo || previewType.isImage else { return true }
        let status: PHAuthorizationStatus
        if #available(iOS 14, *) {
            status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        } else {
            status = PHPhotoLibrary.authorizationStatus()
        }
        switch status {
        case .denied, .restricted:
            DispatchQueue.main.async { [weak self] in
                let ac = UIAlertController(title: "Нет доступа к галерее", message: "Для сохранения фото/видео необходим доступ к галерее", preferredStyle: .alert)
                let submitAction = UIAlertAction(title: "Перейти в настройки", style: .default) { _ in
                    UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!, options: [:], completionHandler: nil)
                }
                let cancel = UIAlertAction(title: "Понятно", style: .cancel)
                ac.addAction(submitAction)
                ac.addAction(cancel)
                self?.present(ac, animated: true, completion: nil)
            }
            return false
        case .notDetermined:
            DispatchQueue.main.async { [weak self] in
                if #available(iOS 14, *) {
                    PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] (_) in
                        self?.saveButtonPressed()
                    }
                } else {
                    PHPhotoLibrary.requestAuthorization() { [weak self] (_) in
                        self?.saveButtonPressed()
                    }
                }
            }
            return false
        default: return true
        }
        
    }
    
    private func showErrorAlert() {
        let ac = UIAlertController(title: "Ошибка загрузки", message: "К сожалению, не удалось загрузить \(previewType.name)", preferredStyle: .alert)
        let cancel = UIAlertAction(title: "Понятно", style: .cancel) { [weak self] _ in
            self?.dismiss(animated: true, completion: nil)
        }
        ac.addAction(cancel)
        self.present(ac, animated: true, completion: nil)
    }
    
    // MARK: - CTVideoViewDelegate
    
    func videoStateChanged(isPlaying: Bool) {
        guard var items = toolbarItems else { return }
        if isPlaying {
            items[2] = UIBarButtonItem(barButtonSystemItem: .pause, target: self, action: #selector(playButtonPressed))
        } else {
            items[2] = UIBarButtonItem(barButtonSystemItem: .play, target: self, action: #selector(playButtonPressed))
        }
        toolbarItems = items
    }
    
    // MARK: - Button handling
    @objc
    private func doneButtonPressed() {
        DispatchQueue.main.async {
            self.dismiss(animated: true)
        }
    }
    
    @objc
    private func saveButtonPressed() {
        guard let localFileURL = localFileURL, FileManager.default.fileExists(atPath: localFileURL.path) && checkPermission(for: previewType) else { return }
        let activityItems: [Any]
        if case let CTPreviewType.image(imageURL) = previewType!,
           let imageData = try? Data(contentsOf: imageURL),
           let image = UIImage(data: imageData) {
            activityItems = [image]
        } else {
            activityItems = [localFileURL]
        }
        
        DispatchQueue.main.async { [weak self] in
            let activityViewController = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
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
