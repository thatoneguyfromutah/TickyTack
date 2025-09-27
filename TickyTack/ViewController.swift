//
//  ViewController.swift
//  TickyTack
//
//  Created by Chase Angelo Giles on 9/27/25.
//

import UIKit
import AVFoundation
import UniformTypeIdentifiers
import AVKit
import CoreData

class ViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    // MARK: - Properties
    
    var ticks: [Tick] = []
    var tickObjects: [NSManagedObject] = []
    // Core Data context
    lazy var context: NSManagedObjectContext = {
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        return appDelegate.persistentContainer.viewContext
    }()
    
    // MARK: - Interface Builder Properties
    
    @IBOutlet weak var cameraButtonView: UIView!
    @IBOutlet weak var tableView: UITableView!
    
    // MARK: - View Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Add shadows
        addShadowToView(cameraButtonView)
        
        // Core data
        loadTicksFromCoreData()
        
        // Permissions
        requestCameraAndMicPermissions(completion: { _ in
            
        })
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
        picker.videoQuality = .typeHigh // Optional
        
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
            let tick = Tick(videoURL: finalURL)
            if let obj = saveTickToCoreData(tick) {
                tickObjects.insert(obj, at: 0)
            }
            ticks.insert(tick, at: 0)
            tableView.insertRows(at: [IndexPath(row: 0, section: 0)], with: .automatic)
        }
        
        picker.dismiss(animated: true, completion: nil)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        
        picker.dismiss(animated: true, completion: nil)
    }
    
    // MARK: - Core Data

    private func loadTicksFromCoreData() {
        
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "StoredTick")
        
        do {
            
            let objects = try context.fetch(fetchRequest)
            let docs = documentsDirectory()
            var items: [(Tick, NSManagedObject, Date)] = []
            
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
                    items.append((Tick(videoURL: url), obj, date))
                }
            }
            
            let sorted = items.sorted { $0.2 > $1.2 }
            
            self.ticks = sorted.map { $0.0 }
            self.tickObjects = sorted.map { $0.1 }
            
            self.tableView.reloadData()
            
        } catch {
            
            print("Failed to fetch ticks from Core Data: \(error)")
        }
    }

    @discardableResult
    private func saveTickToCoreData(_ tick: Tick) -> NSManagedObject? {
        
        guard let entity = NSEntityDescription.entity(forEntityName: "StoredTick", in: context) else {
            print("Core Data entity 'Tick' not found in model.")
            return nil
        }
        
        let obj = NSManagedObject(entity: entity, insertInto: context)
        var storedString: String? = nil
        
        if let url = tick.videoURL, let rel = relativePathForDocuments(url: url) {
            
            storedString = rel
            
        } else {
            
            storedString = tick.videoURL?.absoluteString
        }
        
        obj.setValue(storedString, forKey: "videoURLString")
        
        do {
            
            try context.save()
            
            return obj
            
        } catch {
            
            print("Failed to save tick to Core Data: \(error)")
            
            return nil
        }
    }
    
    // MARK: - File Storage

    private func documentsDirectory() -> URL {
        
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    private func ticksDirectory() -> URL {
        
        return documentsDirectory().appendingPathComponent("Ticks", isDirectory: true)
    }

    private func ensureTicksDirectoryExists() {
        
        let dir = ticksDirectory()
        
        if !FileManager.default.fileExists(atPath: dir.path) {
            
            do {
                
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                
            } catch {
                
                print("Failed to create Ticks directory: \(error)")
            }
        }
    }

    @discardableResult
    private func saveVideoToDocuments(from sourceURL: URL) throws -> URL {
        
        ensureTicksDirectoryExists()
        
        let ext = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let fileName = "\(UUID().uuidString).\(ext)"
        let destinationURL = ticksDirectory().appendingPathComponent(fileName)
        
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
        
        return ticks.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
                
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! TableViewCell
        cell.thumbnailImageView.image = thumbnailImageForVideo(url: ticks[indexPath.row].videoURL!)
        
        self.addShadowToViews([cell.thumbnailImageBackgroundView, cell.playButtonBackgroundView])

        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        playVideo(from: ticks[indexPath.row].videoURL!)
    }
    
    // MARK: - Deletion

    private func deleteTick(at indexPath: IndexPath) {
        // Remove video file from disk
        if let url = ticks[indexPath.row].videoURL {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                print("Failed to remove video file: \(error)")
            }
        }

        // Remove Core Data object
        if indexPath.row < tickObjects.count {
            let obj = tickObjects[indexPath.row]
            context.delete(obj)
            do {
                try context.save()
            } catch {
                print("Failed to delete tick from Core Data: \(error)")
            }
            tickObjects.remove(at: indexPath.row)
        }

        // Update data source and table view
        ticks.remove(at: indexPath.row)
        tableView.deleteRows(at: [indexPath], with: .automatic)
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            guard let self = self else { completion(false); return }
            self.deleteTick(at: indexPath)
            completion(true)
        }
        deleteAction.image = UIImage(systemName: "trash.fill")
        
        let config = UISwipeActionsConfiguration(actions: [deleteAction])
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
        
        presentVideoRecorder()
    }
    
    @IBAction func cameraButtonTouchUpOutside(_ sender: UIButton) {
        
        UIView.animate(withDuration: 0.25) {
            
            self.cameraButtonView.transform = .identity
        }
    }
    
    @IBAction func didTapMore(_ sender: UIBarButtonItem) {
        
    }
    
    @IBAction func didTapSettings(_ sender: UIBarButtonItem) {
        
    }
}
