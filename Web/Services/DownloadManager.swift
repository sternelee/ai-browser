import SwiftUI
import Combine

class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()
    
    @Published var downloads: [Download] = []
    @Published var isVisible: Bool = false
    @Published var totalActiveDownloads: Int = 0
    
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    private let downloadDirectory: URL = {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    }()
    
    override init() {
        super.init()
        loadExistingDownloads()
    }
    
    func startDownload(from url: URL, suggestedFilename: String? = nil) {
        let filename = suggestedFilename ?? url.lastPathComponent
        let destinationURL = downloadDirectory.appendingPathComponent(filename)
        
        // Check if file already exists and create unique name
        let finalURL = createUniqueFileURL(for: destinationURL)
        
        let download = Download(
            url: url,
            destinationURL: finalURL,
            filename: finalURL.lastPathComponent
        )
        
        downloads.append(download)
        
        let task = session.downloadTask(with: url)
        download.task = task
        task.resume()
        
        updateActiveDownloadsCount()
    }
    
    func pauseDownload(_ download: Download) {
        download.task?.suspend()
        download.status = .paused
    }
    
    func resumeDownload(_ download: Download) {
        download.task?.resume()
        download.status = .downloading
    }
    
    func cancelDownload(_ download: Download) {
        download.task?.cancel()
        download.status = .cancelled
        updateActiveDownloadsCount()
    }
    
    func removeDownload(_ download: Download) {
        if let index = downloads.firstIndex(where: { $0.id == download.id }) {
            downloads.remove(at: index)
        }
    }
    
    private func createUniqueFileURL(for url: URL) -> URL {
        var finalURL = url
        var counter = 1
        
        while FileManager.default.fileExists(atPath: finalURL.path) {
            let name = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension
            finalURL = url.deletingLastPathComponent()
                .appendingPathComponent("\(name) (\(counter))")
                .appendingPathExtension(ext)
            counter += 1
        }
        
        return finalURL
    }
    
    private func updateActiveDownloadsCount() {
        totalActiveDownloads = downloads.filter { 
            $0.status == .downloading 
        }.count
    }
    
    private func loadExistingDownloads() {
        // Load download history from UserDefaults if needed
    }
}

// Download model
class Download: ObservableObject, Identifiable {
    let id = UUID()
    let url: URL
    let destinationURL: URL
    let filename: String
    let startDate = Date()
    
    @Published var status: Status = .downloading
    @Published var totalBytes: Int64 = 0
    @Published var downloadedBytes: Int64 = 0
    @Published var speed: Double = 0 // bytes per second
    
    var task: URLSessionDownloadTask?
    
    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(downloadedBytes) / Double(totalBytes)
    }
    
    var remainingTime: TimeInterval? {
        guard speed > 0 && totalBytes > downloadedBytes else { return nil }
        let remainingBytes = max(0, totalBytes - downloadedBytes)
        guard remainingBytes > 0 else { return 0 }
        let time = Double(remainingBytes) / speed
        guard time.isFinite && time <= Double(Int.max) else { return nil }
        return time
    }
    
    enum Status {
        case downloading, paused, completed, failed, cancelled
    }
    
    init(url: URL, destinationURL: URL, filename: String) {
        self.url = url
        self.destinationURL = destinationURL
        self.filename = filename
    }
}

// Download manager URLSession delegate
extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let download = downloads.first(where: { $0.task == downloadTask }) else { return }
        
        do {
            try FileManager.default.moveItem(at: location, to: download.destinationURL)
            
            DispatchQueue.main.async {
                download.status = .completed
                self.updateActiveDownloadsCount()
            }
        } catch {
            DispatchQueue.main.async {
                download.status = .failed
                self.updateActiveDownloadsCount()
            }
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let download = downloads.first(where: { $0.task == downloadTask }) else { return }
        
        DispatchQueue.main.async {
            download.downloadedBytes = totalBytesWritten
            download.totalBytes = totalBytesExpectedToWrite
            
            // Calculate speed with safety checks
            let timeElapsed = Date().timeIntervalSince(download.startDate)
            if timeElapsed > 0 && timeElapsed.isFinite {
                let speed = Double(totalBytesWritten) / timeElapsed
                download.speed = speed.isFinite && speed >= 0 ? speed : 0
            } else {
                download.speed = 0
            }
        }
    }
}