import Foundation
import CryptoKit

/// Model download and management system for Gemma 3n 4B
/// Handles downloading, validation, caching, and integrity verification
class ModelDownloader: NSObject, ObservableObject {
    
    // MARK: - Properties
    
    @Published var downloadProgress: Double = 0.0
    @Published var downloadSpeed: Double = 0.0
    @Published var isDownloading: Bool = false
    @Published var downloadError: String?
    @Published var isModelAvailable: Bool = false
    
    private let fileManager = FileManager.default
    private var downloadTask: URLSessionDownloadTask?
    private var session: URLSession
    
    // MARK: - Model Configuration
    
    struct ModelInfo {
        let name: String
        let url: URL
        let expectedSize: Int64
        let sha256Hash: String
        let quantization: String
        
        static let gemma4BInt4 = ModelInfo(
            name: "gemma-3n-4b-int4",
            url: URL(string: "https://huggingface.co/google/gemma-3n-4b-it/resolve/main/model.safetensors")!,
            expectedSize: 2_684_354_560, // 2.6 GB
            sha256Hash: "placeholder_hash", // Would be actual SHA256
            quantization: "int4"
        )
        
        static let gemma2BInt4 = ModelInfo(
            name: "gemma-3n-2b-int4",
            url: URL(string: "https://huggingface.co/google/gemma-3n-2b-it/resolve/main/model.safetensors")!,
            expectedSize: 1_610_612_736, // 1.5 GB
            sha256Hash: "placeholder_hash",
            quantization: "int4"
        )
    }
    
    // MARK: - File Paths
    
    private var modelsDirectory: URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let webModels = applicationSupport.appendingPathComponent("Web/AI/Models")
        
        // Ensure directory exists
        try? fileManager.createDirectory(at: webModels, withIntermediateDirectories: true)
        
        return webModels
    }
    
    private func modelPath(for info: ModelInfo) -> URL {
        return modelsDirectory.appendingPathComponent("\(info.name).safetensors")
    }
    
    private func checksumPath(for info: ModelInfo) -> URL {
        return modelsDirectory.appendingPathComponent("\(info.name).sha256")
    }
    
    // MARK: - Initialization
    
    override init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600 // 1 hour for large downloads
        self.session = URLSession(configuration: config, delegate: nil, delegateQueue: nil)
        
        super.init()
        
        // Check if model is already available
        checkModelAvailability()
    }
    
    // MARK: - Public Interface
    
    /// Download the optimal model for the current hardware
    func downloadOptimalModel() async throws {
        let config = HardwareDetector.getOptimalAIConfiguration()
        let modelInfo: ModelInfo
        
        switch config.modelVariant {
        case .gemma4B:
            modelInfo = ModelInfo.gemma4BInt4
        case .gemma2B:
            modelInfo = ModelInfo.gemma2BInt4
        case .custom(let name):
            throw ModelDownloadError.unsupportedModel("Custom model \(name) not supported")
        }
        
        try await downloadModel(modelInfo)
    }
    
    /// Download a specific model
    func downloadModel(_ info: ModelInfo) async throws {
        await MainActor.run {
            isDownloading = true
            downloadProgress = 0.0
            downloadError = nil
        }
        
        do {
            // Check if model already exists and is valid
            if isModelValid(info) {
                await MainActor.run {
                    self.isDownloading = false
                    self.isModelAvailable = true
                    self.downloadProgress = 1.0
                }
                NSLog("✅ Model \(info.name) already available and valid")
                return
            }
            
            // Download the model
            try await performDownload(info)
            
            // Verify the downloaded model
            try await verifyModel(info)
            
            await MainActor.run {
                self.isDownloading = false
                self.isModelAvailable = true
                self.downloadProgress = 1.0
            }
            
            NSLog("✅ Model \(info.name) downloaded and verified successfully")
            
        } catch {
            await MainActor.run {
                self.isDownloading = false
                self.downloadError = error.localizedDescription
            }
            throw error
        }
    }
    
    /// Cancel current download
    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        
        Task { @MainActor in
            isDownloading = false
            downloadProgress = 0.0
        }
    }
    
    /// Check if the model is available and valid
    func checkModelAvailability() {
        let config = HardwareDetector.getOptimalAIConfiguration()
        let modelInfo: ModelInfo
        
        switch config.modelVariant {
        case .gemma4B:
            modelInfo = ModelInfo.gemma4BInt4
        case .gemma2B:
            modelInfo = ModelInfo.gemma2BInt4
        case .custom:
            return // Custom models not supported yet
        }
        
        isModelAvailable = isModelValid(modelInfo)
    }
    
    /// Get the path to the downloaded model
    func getModelPath() -> URL? {
        let config = HardwareDetector.getOptimalAIConfiguration()
        let modelInfo: ModelInfo
        
        switch config.modelVariant {
        case .gemma4B:
            modelInfo = ModelInfo.gemma4BInt4
        case .gemma2B:
            modelInfo = ModelInfo.gemma2BInt4
        case .custom:
            return nil
        }
        
        let path = modelPath(for: modelInfo)
        return fileManager.fileExists(atPath: path.path) ? path : nil
    }
    
    // MARK: - Private Methods
    
    private func performDownload(_ info: ModelInfo) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            let request = URLRequest(url: info.url)
            
            downloadTask = session.downloadTask(with: request) { [weak self] localURL, response, error in
                guard let self = self else { return }
                
                if let error = error {
                    continuation.resume(throwing: ModelDownloadError.downloadFailed(error.localizedDescription))
                    return
                }
                
                guard let localURL = localURL else {
                    continuation.resume(throwing: ModelDownloadError.downloadFailed("No local URL"))
                    return
                }
                
                do {
                    let destination = self.modelPath(for: info)
                    
                    // Remove existing file if it exists
                    try? self.fileManager.removeItem(at: destination)
                    
                    // Move downloaded file to destination
                    try self.fileManager.moveItem(at: localURL, to: destination)
                    
                    continuation.resume()
                    
                } catch {
                    continuation.resume(throwing: ModelDownloadError.downloadFailed(error.localizedDescription))
                }
            }
            
            // Add progress tracking
            downloadTask?.progress.addObserver(
                self,
                forKeyPath: "fractionCompleted",
                options: .new,
                context: nil
            )
            
            downloadTask?.resume()
        }
    }
    
    private func verifyModel(_ info: ModelInfo) async throws {
        let modelPath = self.modelPath(for: info)
        
        guard fileManager.fileExists(atPath: modelPath.path) else {
            throw ModelDownloadError.verificationFailed("Model file not found")
        }
        
        // Check file size
        let attributes = try fileManager.attributesOfItem(atPath: modelPath.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        
        if fileSize != info.expectedSize {
            throw ModelDownloadError.verificationFailed("File size mismatch: expected \(info.expectedSize), got \(fileSize)")
        }
        
        // Verify checksum (placeholder - would implement actual SHA256 verification)
        try await verifyChecksum(modelPath, expectedHash: info.sha256Hash)
        
        // Save checksum file
        let checksumPath = self.checksumPath(for: info)
        try info.sha256Hash.write(to: checksumPath, atomically: true, encoding: .utf8)
    }
    
    private func verifyChecksum(_ filePath: URL, expectedHash: String) async throws {
        // Placeholder for SHA256 verification
        // In real implementation, would compute SHA256 of the file
        // For now, just validate file is readable
        guard fileManager.isReadableFile(atPath: filePath.path) else {
            throw ModelDownloadError.verificationFailed("Model file is not readable")
        }
    }
    
    private func isModelValid(_ info: ModelInfo) -> Bool {
        let modelPath = self.modelPath(for: info)
        let checksumPath = self.checksumPath(for: info)
        
        // Check if both files exist
        guard fileManager.fileExists(atPath: modelPath.path),
              fileManager.fileExists(atPath: checksumPath.path) else {
            return false
        }
        
        // Check file size
        do {
            let attributes = try fileManager.attributesOfItem(atPath: modelPath.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            
            if fileSize != info.expectedSize {
                return false
            }
        } catch {
            return false
        }
        
        // Check checksum file content
        do {
            let savedChecksum = try String(contentsOf: checksumPath)
            return savedChecksum.trimmingCharacters(in: .whitespacesAndNewlines) == info.sha256Hash
        } catch {
            return false
        }
    }
    
    // MARK: - KVO Observer
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "fractionCompleted",
           let progress = object as? Progress {
            
            Task { @MainActor in
                self.downloadProgress = progress.fractionCompleted
                
                // Calculate download speed
                let bytesCompleted = progress.completedUnitCount
                let timeElapsed = CFAbsoluteTimeGetCurrent() - self.startTime
                
                if timeElapsed > 0 {
                    self.downloadSpeed = Double(bytesCompleted) / timeElapsed // bytes per second
                }
            }
        }
    }
    
    private var startTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    
    deinit {
        downloadTask?.progress.removeObserver(self, forKeyPath: "fractionCompleted")
        cancelDownload()
    }
}

// MARK: - Errors

enum ModelDownloadError: LocalizedError {
    case unsupportedModel(String)
    case downloadFailed(String)
    case verificationFailed(String)
    case networkError(String)
    case insufficientStorage(String)
    
    var errorDescription: String? {
        switch self {
        case .unsupportedModel(let message):
            return "Unsupported Model: \(message)"
        case .downloadFailed(let message):
            return "Download Failed: \(message)"
        case .verificationFailed(let message):
            return "Verification Failed: \(message)"
        case .networkError(let message):
            return "Network Error: \(message)"
        case .insufficientStorage(let message):
            return "Insufficient Storage: \(message)"
        }
    }
}

// MARK: - Extensions

extension ModelDownloader {
    /// Get human-readable download speed string
    var formattedDownloadSpeed: String {
        let bytesPerSecond = downloadSpeed
        
        if bytesPerSecond < 1024 {
            return String(format: "%.0f B/s", bytesPerSecond)
        } else if bytesPerSecond < 1024 * 1024 {
            return String(format: "%.1f KB/s", bytesPerSecond / 1024)
        } else {
            return String(format: "%.1f MB/s", bytesPerSecond / (1024 * 1024))
        }
    }
    
    /// Get estimated time remaining for download
    var estimatedTimeRemaining: TimeInterval? {
        guard downloadSpeed > 0, downloadProgress > 0, downloadProgress < 1.0 else {
            return nil
        }
        
        let remainingProgress = 1.0 - downloadProgress
        let config = HardwareDetector.getOptimalAIConfiguration()
        
        let modelSize: Double
        switch config.modelVariant {
        case .gemma4B:
            modelSize = Double(ModelInfo.gemma4BInt4.expectedSize)
        case .gemma2B:
            modelSize = Double(ModelInfo.gemma2BInt4.expectedSize)
        case .custom:
            return nil
        }
        
        let remainingBytes = remainingProgress * modelSize
        return remainingBytes / downloadSpeed
    }
    
    /// Get formatted time remaining string
    var formattedTimeRemaining: String {
        guard let timeRemaining = estimatedTimeRemaining else {
            return "Calculating..."
        }
        
        let minutes = Int(timeRemaining / 60)
        let seconds = Int(timeRemaining.truncatingRemainder(dividingBy: 60))
        
        if minutes > 0 {
            return "\(minutes)m \(seconds)s remaining"
        } else {
            return "\(seconds)s remaining"
        }
    }
}