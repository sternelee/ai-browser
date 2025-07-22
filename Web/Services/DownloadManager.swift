import SwiftUI
import Combine
import WebKit
import os.log

class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()
    
    private let logger = Logger(subsystem: "com.example.Web", category: "DownloadManager")
    
    @Published var downloads: [Download] = []
    @Published var isVisible: Bool = false
    @Published var totalActiveDownloads: Int = 0
    @Published var downloadHistory: [DownloadHistoryItem] = []
    
    // WKWebView integration
    private var webViewDownloads: [String: WKDownload] = [:]
    
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    private let downloadDirectory: URL = {
        guard let directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            // Fallback to Documents directory if Downloads is not accessible
            return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first 
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
        }
        return directory
    }()
    
    override init() {
        super.init()
        loadExistingDownloads()
        loadDownloadHistory()
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
    
    private func loadDownloadHistory() {
        // Load download history from UserDefaults
        if let data = UserDefaults.standard.data(forKey: "downloadHistory"),
           let history = try? JSONDecoder().decode([DownloadHistoryItem].self, from: data) {
            downloadHistory = history
        }
    }
    
    private func saveDownloadHistory() {
        if let data = try? JSONEncoder().encode(downloadHistory) {
            UserDefaults.standard.set(data, forKey: "downloadHistory")
        }
    }
    
    // MARK: - WKWebView Integration
    
    /// Handle WKDownload from WKWebView
    func handleWebViewDownload(_ download: WKDownload) {
        guard let url = download.originalRequest?.url else { 
            logger.error("WKDownload missing original request URL")
            return 
        }
        
        // Safely extract filename with fallback
        let filename = url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent
        let downloadId = UUID().uuidString
        webViewDownloads[downloadId] = download
        
        let webDownload = Download(
            url: url,
            destinationURL: downloadDirectory.appendingPathComponent(filename),
            filename: filename
        )
        webDownload.webKitDownloadId = downloadId
        
        downloads.append(webDownload)
        updateActiveDownloadsCount()
        
        logger.info("Started WKWebView download: \(filename)")
    }
    
    /// Check if navigation should trigger download based on MIME type
    func shouldDownloadResponse(_ response: URLResponse) -> Bool {
        guard let mimeType = response.mimeType else { return false }
        
        let downloadableMimeTypes = [
            "application/pdf",
            "application/zip",
            "application/x-zip-compressed",
            "application/octet-stream",
            "application/msword",
            "application/vnd.ms-excel",
            "application/vnd.ms-powerpoint",
            "application/vnd.openxmlformats-officedocument",
            "image/jpeg",
            "image/png",
            "image/gif",
            "image/svg+xml",
            "video/mp4",
            "video/quicktime",
            "audio/mpeg",
            "audio/wav"
        ]
        
        return downloadableMimeTypes.contains { mimeType.hasPrefix($0) }
    }
    
    /// Open file in default application
    func openDownloadedFile(_ download: Download) {
        guard download.status == .completed else { return }
        
        if FileManager.default.fileExists(atPath: download.destinationURL.path) {
            NSWorkspace.shared.open(download.destinationURL)
            logger.info("Opened downloaded file: \(download.filename)")
        } else {
            logger.error("Downloaded file not found: \(download.destinationURL.path)")
        }
    }
    
    /// Show file in Finder
    func showInFinder(_ download: Download) {
        guard download.status == .completed else { return }
        
        if FileManager.default.fileExists(atPath: download.destinationURL.path) {
            NSWorkspace.shared.selectFile(download.destinationURL.path, inFileViewerRootedAtPath: downloadDirectory.path)
            logger.info("Showed file in Finder: \(download.filename)")
        }
    }
    
    /// Get download progress for UI
    func getOverallProgress() -> Double {
        let activeDownloads = downloads.filter { $0.status == .downloading }
        guard !activeDownloads.isEmpty else { return 0.0 }
        
        let totalProgress = activeDownloads.reduce(0.0) { $0 + $1.progress }
        return totalProgress / Double(activeDownloads.count)
    }
    
    /// Clear completed downloads
    func clearCompletedDownloads() {
        downloads.removeAll { $0.status == .completed || $0.status == .failed || $0.status == .cancelled }
        updateActiveDownloadsCount()
        logger.info("Cleared completed downloads")
    }
    
    /// Get download by URL
    func getDownload(for url: URL) -> Download? {
        return downloads.first { $0.url == url }
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
    @Published var completedDate: Date?
    
    var task: URLSessionDownloadTask?
    var webKitDownloadId: String? // For WKDownload integration
    
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
    
    /// Get formatted file size
    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        
        if status == .completed || totalBytes > 0 {
            return formatter.string(fromByteCount: totalBytes)
        } else {
            return "Unknown"
        }
    }
    
    /// Get formatted download speed
    var formattedSpeed: String {
        guard speed > 0 else { return "" }
        
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        
        return "\(formatter.string(fromByteCount: Int64(speed)))/s"
    }
    
    /// Get estimated time remaining
    var formattedTimeRemaining: String {
        guard let remaining = remainingTime, remaining > 0 && remaining.isFinite else { return "" }
        
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        
        return formatter.string(from: remaining) ?? ""
    }
}

// Download history item for persistence
struct DownloadHistoryItem: Codable, Identifiable {
    let id: UUID
    let url: String
    let filename: String
    let filePath: String
    let fileSize: Int64
    let downloadDate: Date
    let mimeType: String?
    
    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
    
    var fileExists: Bool {
        return FileManager.default.fileExists(atPath: filePath)
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
                download.completedDate = Date()
                self.updateActiveDownloadsCount()
                
                // Add to download history
                let historyItem = DownloadHistoryItem(
                    id: UUID(),
                    url: download.url.absoluteString,
                    filename: download.filename,
                    filePath: download.destinationURL.path,
                    fileSize: download.totalBytes,
                    downloadDate: Date(),
                    mimeType: downloadTask.response?.mimeType
                )
                
                self.downloadHistory.insert(historyItem, at: 0)
                
                // Keep only last 100 downloads in history
                if self.downloadHistory.count > 100 {
                    self.downloadHistory = Array(self.downloadHistory.prefix(100))
                }
                
                self.saveDownloadHistory()
                self.logger.info("Download completed: \(download.filename)")
            }
        } catch {
            DispatchQueue.main.async {
                download.status = .failed
                self.updateActiveDownloadsCount()
                self.logger.error("Failed to move downloaded file: \(error.localizedDescription)")
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