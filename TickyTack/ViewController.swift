//
//  ViewController.swift
//  TickyTack
//
//  Created by Chase Angelo Giles, with AI assistance, on 9/27/25.
//

import UIKit
import AVFoundation
import UniformTypeIdentifiers
import AVKit
import CoreData
import SafariServices

class ViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UIImagePickerControllerDelegate, UINavigationControllerDelegate, SFSafariViewControllerDelegate {
    
    // MARK: - Properties
    
    var tacks: [Tack] = []
    var tackObjects: [NSManagedObject] = []
    // Core Data context
    lazy var context: NSManagedObjectContext = {
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        return appDelegate.persistentContainer.viewContext
    }()
    
    // MARK: - Interface Builder Properties
    
    @IBOutlet weak var cameraButtonView: UIView!
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var toolbarBackgroundView: UIView!
    
    // MARK: - View Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Add shadows
        addShadowToViews([cameraButtonView, toolbarBackgroundView])
        
        // Core data
        loadTacksFromCoreData()
        
        // Permissions
        requestCameraAndMicPermissions(completion: { _ in })
    }
    
    // MARK: - Permissions
    
    func requestCameraAndMicPermissions(completion: @escaping (Bool) -> Void) {
        
           AVCaptureDevice.requestAccess(for: .video) { cameraGranted in
               
               AVCaptureDevice.requestAccess(for: .audio) { micGranted in
                   
                   DispatchQueue.main.async {
                       
                       completion(cameraGranted && micGranted)
                   }
               }
           }
       }

    // MARK: - Camera Button & View
    
    func addShadowToView(_ view: UIView) {
        
        addShadowToViews([view])
    }
    
    func addShadowToViews(_ views: [UIView]) {
        
        for view in views {
            
            view.layer.shadowColor = UIColor.black.cgColor
            view.layer.shadowOffset = .zero
            view.layer.shadowOpacity = 0.33
            view.layer.shadowRadius = 3
        }
    }
    
    // MARK: - Camera
    
    func presentVideoRecorder() {
        
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
        
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.movie"]
        picker.delegate = self
        picker.videoQuality = .typeHigh
        picker.videoMaximumDuration = 300 // Limit recording to 5 minutes
        picker.allowsEditing = true
        
        present(picker, animated: true, completion: nil)
    }

    // MARK: - UIImagePickerControllerDelegate
    
    func imagePickerController(_ picker: UIImagePickerController,
                              didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        
        if let videoURL = info[.mediaURL] as? URL {
            var finalURL = videoURL
            do {
                finalURL = try saveVideoToDocuments(from: videoURL)
            } catch {
                print("Failed to save video to Documents: \(error). Will use original URL.")
            }
            let tack = Tack(videoURL: finalURL)
            if let obj = saveTackToCoreData(tack) {
                tackObjects.insert(obj, at: 0)
            }
            tacks.insert(tack, at: 0)
            tableView.insertRows(at: [IndexPath(row: 0, section: 0)], with: .automatic)
        }
        
        picker.dismiss(animated: true, completion: nil)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        
        picker.dismiss(animated: true, completion: nil)
    }
    
    // MARK: - Core Data

    private func loadTacksFromCoreData() {
        
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "StoredTack")
        
        do {
            
            let objects = try context.fetch(fetchRequest)
            let docs = documentsDirectory()
            var items: [(Tack, NSManagedObject, Date)] = []
            
            for obj in objects {
                guard let urlString = obj.value(forKey: "videoURLString") as? String else { continue }
                let url: URL?
                if urlString.hasPrefix("file://") {
                    url = URL(string: urlString)
                } else {
                    url = docs.appendingPathComponent(urlString)
                }
                if let url = url {
                    let date = fileDate(for: url)
                    items.append((Tack(videoURL: url), obj, date))
                }
            }
            
            let sorted = items.sorted { $0.2 > $1.2 }
            
            self.tacks = sorted.map { $0.0 }
            self.tackObjects = sorted.map { $0.1 }
            
            self.tableView.reloadData()
            
        } catch {
            
            print("Failed to fetch tacks from Core Data: \(error)")
        }
    }

    @discardableResult
    private func saveTackToCoreData(_ tack: Tack) -> NSManagedObject? {
        
        guard let entity = NSEntityDescription.entity(forEntityName: "StoredTack", in: context) else {
            print("Core Data entity 'Tack' not found in model.")
            return nil
        }
        
        let obj = NSManagedObject(entity: entity, insertInto: context)
        var storedString: String? = nil
        
        if let url = tack.videoURL, let rel = relativePathForDocuments(url: url) {
            
            storedString = rel
            
        } else {
            
            storedString = tack.videoURL?.absoluteString
        }
        
        obj.setValue(storedString, forKey: "videoURLString")
        
        do {
            
            try context.save()
            
            return obj
            
        } catch {
            
            print("Failed to save tack to Core Data: \(error)")
            
            return nil
        }
    }
    
    // MARK: - File Storage

    private func documentsDirectory() -> URL {
        
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    private func tacksDirectory() -> URL {
        
        return documentsDirectory().appendingPathComponent("Tacks", isDirectory: true)
    }

    private func ensureTacksDirectoryExists() {
        
        let dir = tacksDirectory()
        
        if !FileManager.default.fileExists(atPath: dir.path) {
            
            do {
                
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                
            } catch {
                
                print("Failed to create Tacks directory: \(error)")
            }
        }
    }

    @discardableResult
    private func saveVideoToDocuments(from sourceURL: URL) throws -> URL {
        
        ensureTacksDirectoryExists()
        
        let ext = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let fileName = "\(UUID().uuidString).\(ext)"
        let destinationURL = tacksDirectory().appendingPathComponent(fileName)
        
        do {
            
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
            
        } catch {
            // Fallback to copy if move fails
            do {
                
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                try? FileManager.default.removeItem(at: sourceURL)
                
            } catch {
                
                throw error
            }
        }
        
        return destinationURL
    }

    private func relativePathForDocuments(url: URL) -> String? {
        
        let docs = documentsDirectory().standardizedFileURL
        let target = url.standardizedFileURL
        let docsPath = docs.path
        let targetPath = target.path
        
        if targetPath.hasPrefix(docsPath) {
            let start = targetPath.index(targetPath.startIndex, offsetBy: docsPath.hasSuffix("/") ? docsPath.count : docsPath.count + 1)
            return String(targetPath[start...])
        }
        
        return nil
    }
    
    private func fileDate(for url: URL) -> Date {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let creation = attrs?[.creationDate] as? Date
        let modified = attrs?[.modificationDate] as? Date
        return creation ?? modified ?? .distantPast
    }
    
    // MARK: - Video Management
    
    func thumbnailImageForVideo(url: URL, at time: CMTime = CMTime(seconds: 1, preferredTimescale: 60)) -> UIImage? {
        
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        let semaphore = DispatchSemaphore(value: 0)
        var resultImage: UIImage?

        generator.generateCGImageAsynchronously(for: time) { cgImage, actualTime, error in
            if let cgImage = cgImage {
                resultImage = UIImage(cgImage: cgImage)
            } else {
                let message = error?.localizedDescription ?? "Unknown error"
                print("Error generating thumbnail at \(actualTime.seconds): \(message)")
            }
            semaphore.signal()
        }

        // Wait for the async generation to complete
        semaphore.wait()
        
        return resultImage
    }
    
    func playVideo(from url: URL) {
        
        let player = AVPlayer(url: url)
        let playerVC = AVPlayerViewController()
        
        playerVC.player = player
        
        present(playerVC, animated: true) {
            player.play()
        }
    }
    
    // MARK: - Table View Delegate & Data Source
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        let emptyLabel = UILabel()
        emptyLabel.textColor = .label
        emptyLabel.font = UIFont.systemFont(ofSize: 28)
        emptyLabel.textAlignment = .center
        emptyLabel.text = tacks.isEmpty ? "No Tacks" : nil
        emptyLabel.alpha = 0.5
        
        tableView.backgroundView = tacks.isEmpty ? emptyLabel : nil
        
        return tacks.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
                
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! TableViewCell
        cell.thumbnailImageView.image = thumbnailImageForVideo(url: tacks[indexPath.row].videoURL!)
        
        self.addShadowToViews([cell.thumbnailImageBackgroundView, cell.playButtonBackgroundView])

        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        playVideo(from: tacks[indexPath.row].videoURL!)
    }
    
    // MARK: - Deletion

    private func deleteTack(at indexPath: IndexPath) {
        // Remove video file from disk
        if let url = tacks[indexPath.row].videoURL {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                print("Failed to remove video file: \(error)")
            }
        }

        // Remove Core Data object
        if indexPath.row < tackObjects.count {
            let obj = tackObjects[indexPath.row]
            context.delete(obj)
            do {
                try context.save()
            } catch {
                print("Failed to delete tack from Core Data: \(error)")
            }
            tackObjects.remove(at: indexPath.row)
        }

        // Update data source and table view
        tacks.remove(at: indexPath.row)
        tableView.deleteRows(at: [indexPath], with: .automatic)
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            guard let self = self else { completion(false); return }
            self.deleteTack(at: indexPath)
            completion(true)
        }
        deleteAction.image = UIImage(systemName: "trash.fill")
        
        let shareAction = UIContextualAction(style: .normal, title: "Share") { [weak self] _, _, completion in
            guard let self = self else { completion(false); return }
            guard let url = self.tacks[indexPath.row].videoURL else { completion(false); return }
            let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let popover = activityVC.popoverPresentationController {
                if let cell = tableView.cellForRow(at: indexPath) {
                    popover.sourceView = cell
                    popover.sourceRect = cell.bounds
                } else {
                    popover.sourceView = self.view
                    popover.sourceRect = self.view.bounds
                }
            }
            self.present(activityVC, animated: true)
            completion(true)
        }
        shareAction.image = UIImage(systemName: "square.and.arrow.up")
        shareAction.backgroundColor = .systemBlue
        
        let config = UISwipeActionsConfiguration(actions: [deleteAction, shareAction])
        config.performsFirstActionWithFullSwipe = true
        
        return config
    }
    
    // MARK: - Actions
    
    @IBAction func cameraButtonTouchDown(_ sender: UIButton) {
        
        UIView.animate(withDuration: 0.33, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5, options: .curveEaseIn) {
            
            self.cameraButtonView.transform = CGAffineTransform(scaleX: 1.25, y: 1.25)
        }
    }
    
    
    @IBAction func cameraButtonTouchUpInside(_ sender: UIButton) {
        
        UIView.animate(withDuration: 0.25) {
            
            self.cameraButtonView.transform = .identity
        }
        
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
            
        case .authorized:

            if tacks.count >= 25 {
                
                let alertController = UIAlertController(title: "Oops!", message: "You have too many Tacks saved to make a new one. Try deleting one or a few and try again.", preferredStyle: .alert)
                let action = UIAlertAction(title: "Okay", style: .default)
                alertController.addAction(action)
                present(alertController, animated: true)
                
            } else {
                
                presentVideoRecorder()
            }
            
        case .denied:
            
            let alertController = UIAlertController(title: "Oops!", message: "Camera permissions were denied. Please tap the settings icon and allow access to make new Tacks.", preferredStyle: .alert)
            let action = UIAlertAction(title: "Okay", style: .default)
            alertController.addAction(action)
            present(alertController, animated: true)
            
        case .notDetermined:
            
            requestCameraAndMicPermissions(completion: { _ in })
            
        case .restricted:
            
            let alertController = UIAlertController(title: "Oops!", message: "Camera permissions are restricted. Please tap the settings icon and allow access to make Tacks.", preferredStyle: .alert)
            let action = UIAlertAction(title: "Okay", style: .default)
            alertController.addAction(action)
            present(alertController, animated: true)
            
        @unknown default:
            
            let alertController = UIAlertController(title: "Oops!", message: "Camera permissions are unknown. Please send in a bug report to explain the situation.", preferredStyle: .alert)
            let action = UIAlertAction(title: "Okay", style: .default)
            alertController.addAction(action)
            present(alertController, animated: true)
            
        }
    }
    
    @IBAction func cameraButtonTouchUpOutside(_ sender: UIButton) {
        
        UIView.animate(withDuration: 0.25) {
            
            self.cameraButtonView.transform = .identity
        }
    }
    
    @IBAction func didTapMore(_ sender: UIBarButtonItem) {
        
        let helpEmail = "thatoneguyfromutah@gmail.com"

        let alertController = UIAlertController(title: "More TickyTack Stuff", message: nil, preferredStyle: .actionSheet)
        alertController.popoverPresentationController?.barButtonItem = sender
        
        let bugReportAction = UIAlertAction(title: "Send Bug Report", style: .default) { _ in
            
            let emailSubject = "TickyTack Bug Report"
            let emailBody = "Please include things like the device model, operating system, and any other relevant information related to the bug(s) you have encountered below:\n\n"
            
            let subjectEncoded = emailSubject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
            let bodyEncoded = emailBody.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
            
            if let url = URL(string: "mailto:\(helpEmail)?subject=\(subjectEncoded)&body=\(bodyEncoded)"),
                      UIApplication.shared.canOpenURL(url) {
                
                UIApplication.shared.open(url)
                
            } else {
                
                let alertController = UIAlertController(title: "Oops!", message: "Unable to send an email. Please set one up in settings and try again. You can also reach out through another device where email is already set up at \(helpEmail).", preferredStyle: .alert)
                
                let cancelAction = UIAlertAction(title: "Okay", style: .default)
                alertController.addAction(cancelAction)
                
                self.present(alertController, animated: true)
            }
        }
        alertController.addAction(bugReportAction)
        
        let contactDeveloperAction = UIAlertAction(title: "Contact Developer", style: .default) { _ in
            
            let emailSubject = "General TickyTack Inquiry"
            let emailBody = ""
            
            let subjectEncoded = emailSubject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
            let bodyEncoded = emailBody.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
            
            if let url = URL(string: "mailto:\(helpEmail)?subject=\(subjectEncoded)&body=\(bodyEncoded)"),
                      UIApplication.shared.canOpenURL(url) {
                
                UIApplication.shared.open(url)
                
            } else {
                
                let alertController = UIAlertController(title: "Oops!", message: "Unable to send an email. Please set one up in settings and try again. You can also reach out through another device where email is already set up at \(helpEmail).", preferredStyle: .alert)
                
                let cancelAction = UIAlertAction(title: "Okay", style: .default)
                alertController.addAction(cancelAction)
                
                self.present(alertController, animated: true)
            }
        }
        alertController.addAction(contactDeveloperAction)
        
        let followDeveloperAction = UIAlertAction(title: "Dev's Personal Blog", style: .default) { _ in
            
            if let url = URL(string: "instagram://user?username=thatoneguyfromutah"), UIApplication.shared.canOpenURL(url) {
                
                UIApplication.shared.open(url)
                
            } else if let url = URL(string: "https://www.instagram.com/thatoneguyfromutah"),
                      UIApplication.shared.canOpenURL(url) {
                
                UIApplication.shared.open(url)
                
            } else {
                
                let alertController = UIAlertController(title: "Oops!", message: "There was an issue opening the developer's personal Instagram blog.", preferredStyle: .alert)
                
                let cancelAction = UIAlertAction(title: "Okay", style: .default)
                alertController.addAction(cancelAction)
                
                self.present(alertController, animated: true)
            }
        }
        alertController.addAction(followDeveloperAction)
        
        let privacyPolicyAction = UIAlertAction(title: "App Privacy Policy", style: .default) { _ in
            
            if let url = URL(string: "https://www.iubenda.com/privacy-policy/78992277"), UIApplication.shared.canOpenURL(url) {
                
                let safariController = SFSafariViewController(url: url)
                safariController.delegate = self
                
                self.present(safariController, animated: true)
                
            } else {
                
                let alertController = UIAlertController(title: "Oops!", message: "There was an issue opening the app privacy policy.", preferredStyle: .alert)
                
                let cancelAction = UIAlertAction(title: "Okay", style: .default)
                alertController.addAction(cancelAction)
                
                self.present(alertController, animated: true)
            }
        }
        alertController.addAction(privacyPolicyAction)
        
        let moreAppsAction = UIAlertAction(title: "More Apps From Dev", style: .default) { _ in
            
            if let url = URL(string: "https://apps.apple.com/developer/chase-giles/id687549414"), UIApplication.shared.canOpenURL(url) {
                
                UIApplication.shared.open(url)
                
            } else {
                
                let alertController = UIAlertController(title: "Oops!", message: "There was an issue opening the developer's apps page.", preferredStyle: .alert)
                
                let cancelAction = UIAlertAction(title: "Okay", style: .default)
                alertController.addAction(cancelAction)
                
                self.present(alertController, animated: true)
            }
        }
        alertController.addAction(moreAppsAction)
        
        present(alertController, animated: true)
    }
    
    @IBAction func didTapSettings(_ sender: UIBarButtonItem) {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
    }
}

