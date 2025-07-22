import Foundation
import Combine

/// On-demand model service for efficient app distribution
/// Intelligently detects existing models and downloads only when needed
class OnDemandModelService: NSObject, ObservableObject, URLSessionDownloadDelegate {
    
    // MARK: - Published Properties
    
    @Published var isModelReady: Bool = false
    @Published var downloadProgress: Double = 0.0
    @Published var downloadState: DownloadState = .notStarted
    @Published var currentModel: ModelConfiguration?
    
    // MARK: - Types
    
    enum DownloadState: Equatable {
        case notStarted      // No model detected, download needed
        case checking        // Checking for existing model
        case downloading     // Currently downloading
        case validating      // Validating downloaded model
        case ready          // Model available and ready
        case failed(String) // Download or validation failed (using String instead of Error for Equatable)
        
        static func == (lhs: DownloadState, rhs: DownloadState) -> Bool {
            switch (lhs, rhs) {
            case (.notStarted, .notStarted),
                 (.checking, .checking),
                 (.downloading, .downloading),
                 (.validating, .validating),
                 (.ready, .ready):
                return true
            case (.failed(let lhsMsg), .failed(let rhsMsg)):
                return lhsMsg == rhsMsg
            default:
                return false
            }
        }
    }
    
    struct ModelConfiguration {
        let name: String
        let filename: String
        let downloadURL: URL
        let sizeBytes: Int64
        let expectedChecksum: String
        
        // Gemma 3n 2B Q8 configuration
        static let gemma3n_2B_Q8 = ModelConfiguration(
            name: "Gemma 3n 2B Q8",
            filename: "gemma-3n-E2B-it-Q8_0.gguf",
            downloadURL: URL(string: "https://huggingface.co/ggml-org/gemma-3n-E2B-it-GGUF/resolve/main/gemma-3n-E2B-it-Q8_0.gguf")!,
            sizeBytes: 4_788_112_064,
            expectedChecksum: "f7782fb59d31c8c755a747cea79f8a671818a363e7d70c5b4a0a28bf0d6318bc"
        )
    }
    
    // MARK: - Properties
    
    private let fileManager = FileManager.default
    private var downloadTask: URLSessionDownloadTask?
    private var urlSession: URLSession
    private var downloadContinuation: CheckedContinuation<URL, Error>?
    
    // MARK: - Paths
    
    private var modelsPersistentDirectory: URL {
        // CRITICAL FIX: Use Application Support directory instead of Caches 
        // Caches directory gets automatically cleaned up by macOS, causing model deletion
        let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelsDirectory = appSupportDir.appendingPathComponent("Web/AI/Models")
        
        // Ensure directory exists with proper error handling
        do {
            try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true, attributes: nil)
            NSLog("📁 Ensured persistent models directory exists: \(modelsDirectory.path)")
        } catch {
            NSLog("⚠️ Warning: Could not create persistent models directory: \(error)")
        }
        
        return modelsDirectory
    }
    
    // MARK: - Initialization
    
    override init() {
        // Configure URL session for large downloads with delegate
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 7200 // 2 hours for 5GB download
        config.waitsForConnectivity = true
        
        // Initialize urlSession before super.init()
        self.urlSession = URLSession(configuration: config)
        
        super.init()
        
        // Update session with delegate after super.init()
        self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        
        // MIGRATION: Move any existing models from Caches to Application Support
        migrateModelsFromCaches()
        
        // Immediately check for existing model on initialization
        Task {
            await performIntelligentModelCheck()
        }
        
        NSLog("🤖 OnDemandModelService initialized - checking for existing AI model...")
    }
    
    /// Migrate existing models from Caches directory to Application Support
    private func migrateModelsFromCaches() {
        let oldCacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let oldModelsDir = oldCacheDir.appendingPathComponent("Web/AI/Models")
        
        // Check if old directory exists
        guard fileManager.fileExists(atPath: oldModelsDir.path) else {
            return // No migration needed
        }
        
        do {
            let files = try fileManager.contentsOfDirectory(atPath: oldModelsDir.path)
            
            for filename in files {
                let oldFilePath = oldModelsDir.appendingPathComponent(filename)
                let newFilePath = modelsPersistentDirectory.appendingPathComponent(filename)
                
                // Only migrate if the file doesn't already exist in the new location
                if fileManager.fileExists(atPath: oldFilePath.path) && !fileManager.fileExists(atPath: newFilePath.path) {
                    do {
                        try fileManager.moveItem(at: oldFilePath, to: newFilePath)
                        NSLog("📦 Migrated model file: \(filename) → Application Support")
                    } catch {
                        NSLog("⚠️ Failed to migrate model file \(filename): \(error)")
                    }
                }
            }
            
            // Try to remove the old directory if it's empty
            try? fileManager.removeItem(at: oldModelsDir)
            NSLog("✅ Model migration completed successfully")
            
        } catch {
            NSLog("⚠️ Model migration failed: \(error)")
        }
    }
    
    deinit {
        downloadTask?.cancel()
    }
    
    // MARK: - Public Interface
    
    /// Intelligent check: returns true if model is ready, false if download needed
    func isAIReady() -> Bool {
        return isModelReady && downloadState == .ready
    }
    
    /// Get path to ready model (nil if not available)
    func getModelPath() -> URL? {
        guard let model = currentModel, isModelReady else {
            return nil
        }
        
        let modelPath = modelsPersistentDirectory.appendingPathComponent(model.filename)

        // CRITICAL FIX: Don't destructively reset model status on every call
        // This was causing race conditions where validated models got deleted
        // Only log if file exists, but don't reset status - validation happens elsewhere
        if fileManager.fileExists(atPath: modelPath.path) {
            NSLog("✅ Found local GGUF model: \(model.filename)")
            return modelPath
        } else {
            NSLog("⚠️ Model path missing but status shows ready - possible race condition")
            return nil
        }
    }
    
    /// Start AI initialization - downloads model if needed
    func initializeAI() async throws {
        // CRITICAL FIX: Double-check with file system before starting download
        // This prevents race condition where model exists but status isn't updated yet
        let model = ModelConfiguration.gemma3n_2B_Q8
        let modelPath = modelsPersistentDirectory.appendingPathComponent(model.filename)
        
        if fileManager.fileExists(atPath: modelPath.path) && isModelReady {
            NSLog("✅ AI model already ready - no download needed")
            return
        }
        
        // If already ready, no action needed
        if isAIReady() {
            NSLog("✅ AI model already ready - no download needed")
            return
        }
        
        // If currently downloading, just wait
        if downloadState == .downloading {
            NSLog("⏳ AI model download already in progress - waiting...")
            return
        }
        
        // Final safety check: if model file exists but state is wrong, re-validate instead of downloading
        if fileManager.fileExists(atPath: modelPath.path) {
            NSLog("🔄 Model file exists but not marked ready - re-validating instead of downloading")
            await performIntelligentModelCheck()
            
            // After validation, check if ready now
            if isAIReady() {
                NSLog("✅ Model validated successfully - no download needed")
                return
            }
        }
        
        // Start download process only if truly needed
        try await downloadModelIfNeeded()
    }
    
    /// Get download information for UI
    func getDownloadInfo() -> DownloadInfo {
        let model = ModelConfiguration.gemma3n_2B_Q8
        return DownloadInfo(
            modelName: model.name,
            sizeGB: Double(model.sizeBytes) / (1024 * 1024 * 1024),
            isDownloadNeeded: !isAIReady()
        )
    }
    
    /// Cancel ongoing download
    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        
        Task {
            await MainActor.run {
                downloadState = .notStarted
                downloadProgress = 0.0
            }
        }
        
        NSLog("❌ AI model download cancelled by user")
    }
    
    /// Download tokenizer.model if not present - NO MORE HARDCODED VOCABULARY!
    func downloadTokenizerIfNeeded() async throws {
        let tokenizerPath = modelsPersistentDirectory.appendingPathComponent("tokenizer.model")
        
        // Check if tokenizer already exists and is valid
        if FileManager.default.fileExists(atPath: tokenizerPath.path) {
            do {
                try TokenizerDownloader.shared.validateTokenizer(at: tokenizerPath)
                NSLog("✅ Valid tokenizer.model already exists")
                return
            } catch {
                NSLog("⚠️ Existing tokenizer invalid, re-downloading: \(error)")
            }
        }
        
        // Download appropriate tokenizer based on system capabilities
        let recommendedModel = TokenizerDownloader.shared.recommendedModel()
        NSLog("🚀 Downloading REAL SentencePiece tokenizer for \(recommendedModel.displayName)...")
        
        try await TokenizerDownloader.shared.downloadTokenizer(
            for: recommendedModel,
            to: tokenizerPath
        )
        
        NSLog("✅ Tokenizer download completed - ready for multilingual tokenization!")
    }
    
    // MARK: - Private Methods
    
    /// Intelligent model detection and validation
    private func performIntelligentModelCheck() async {
        await MainActor.run {
            downloadState = .checking
        }
        
        let model = ModelConfiguration.gemma3n_2B_Q8
        let modelPath = modelsPersistentDirectory.appendingPathComponent(model.filename)
        
        await MainActor.run {
            currentModel = model
        }
        
        // Check if model file exists
        guard fileManager.fileExists(atPath: modelPath.path) else {
            await MainActor.run {
                downloadState = .notStarted
                isModelReady = false
            }
            NSLog("📥 No AI model found - will download on first use (\(formatBytes(model.sizeBytes)))")
            return
        }
        
        // Validate existing model
        do {
            let isValid = try await validateExistingModel(at: modelPath, expected: model)
            
            await MainActor.run {
                if isValid {
                    isModelReady = true
                    downloadState = .ready
                    downloadProgress = 1.0
                    NSLog("✅ Existing AI model validated and ready: \(model.name)")
                } else {
                    isModelReady = false
                    downloadState = .notStarted
                    NSLog("⚠️ Existing AI model corrupted - will re-download")
                }
            }
            
        } catch {
            await MainActor.run {
                downloadState = .failed(error.localizedDescription)
                isModelReady = false
            }
            NSLog("❌ AI model validation failed: \(error)")
        }
    }
    
    private func downloadModelIfNeeded() async throws {
        let model = ModelConfiguration.gemma3n_2B_Q8
        
        await MainActor.run {
            downloadState = .downloading
            downloadProgress = 0.0
        }
        
        // Remove any corrupted existing file if it exists
        let modelPath = modelsPersistentDirectory.appendingPathComponent(model.filename)
        try? fileManager.removeItem(at: modelPath)
        
        NSLog("🔽 Starting AI model download: \(model.name) (\(formatBytes(model.sizeBytes)))")
        NSLog("💡 This is a one-time download - future app launches will be instant")
        
        do {
            // Start download with progress tracking
            downloadTask = urlSession.downloadTask(with: model.downloadURL)
            
            // Use continuation to wait for download completion and file move
            let finalModelPath = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                downloadContinuation = continuation
                downloadTask?.resume()
            }
            
            await MainActor.run {
                downloadState = .validating
                downloadProgress = 0.95
            }
            
            NSLog("📁 Model successfully downloaded and moved to final location")
            
            // Validate downloaded model
            let isValid = try await validateExistingModel(at: finalModelPath, expected: model)
            
            guard isValid else {
                throw ModelError.corruptedDownload
            }
            
            await MainActor.run {
                isModelReady = true
                downloadState = .ready
                downloadProgress = 1.0
            }
            
            NSLog("✅ AI model download completed successfully")
            NSLog("🚀 AI is now ready for use!")
            
        } catch {
            await MainActor.run {
                downloadState = .failed(error.localizedDescription)
                isModelReady = false
                downloadProgress = 0.0
            }
            
            // Clean up failed download
            let modelPath = modelsPersistentDirectory.appendingPathComponent(model.filename)
            try? fileManager.removeItem(at: modelPath)
            
            NSLog("❌ AI model download failed: \(error)")
            throw error
        }
    }
    
    private func validateExistingModel(at path: URL, expected: ModelConfiguration) async throws -> Bool {
        // Check file size
        let attributes = try fileManager.attributesOfItem(atPath: path.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        
        guard fileSize == expected.sizeBytes else {
            NSLog("❌ Model size mismatch: expected \(formatBytes(expected.sizeBytes)), got \(formatBytes(fileSize))")
            return false
        }
        
        // Check GGUF magic number
        let handle = try FileHandle(forReadingFrom: path)
        defer { handle.closeFile() }
        
        let header = handle.readData(ofLength: 4)
        let ggufMagic = Data([0x47, 0x47, 0x55, 0x46]) // "GGUF"
        
        guard header == ggufMagic else {
            NSLog("❌ Invalid AI model format - not a GGUF file")
            return false
        }
        
        return true
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    // No MLX conversion needed - we use GGUF models directly with LLM.swift
    
    // MARK: - URLSessionDownloadDelegate
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        // Update progress on main thread
        DispatchQueue.main.async {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            let cappedProgress = min(max(progress, 0.0), 0.95) // Cap at 95% until validation
            
            // Only update if progress actually changed (prevent infinite updates at 95%)
            if abs(self.downloadProgress - cappedProgress) > 0.001 {
                self.downloadProgress = cappedProgress
            }
            
            // Log progress periodically
            if Int(progress * 100) % 10 == 0 {
                let downloaded = self.formatBytes(totalBytesWritten)
                let total = self.formatBytes(totalBytesExpectedToWrite)
                NSLog("📊 AI model download progress: \(Int(progress * 100))% (\(downloaded) / \(total))")
            }
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        NSLog("✅ AI model download completed, validating...")
        NSLog("📍 Temporary download location: \(location.path)")
        
        // Immediately move the file to prevent system cleanup
        do {
            let model = ModelConfiguration.gemma3n_2B_Q8
            let modelPath = modelsPersistentDirectory.appendingPathComponent(model.filename)
            
            // Verify the temporary file exists and has the expected size
            if fileManager.fileExists(atPath: location.path) {
                let attributes = try fileManager.attributesOfItem(atPath: location.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                NSLog("📏 Downloaded file size: \(formatBytes(fileSize))")
                
                // Ensure destination directory exists
                let destinationDir = modelPath.deletingLastPathComponent()
                try fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true, attributes: nil)
                
                // Remove any existing file at destination
                if fileManager.fileExists(atPath: modelPath.path) {
                    try fileManager.removeItem(at: modelPath)
                    NSLog("🗑️ Removed existing model file before moving new download")
                }
                
                // Immediately move to final location to prevent system cleanup
                try fileManager.moveItem(at: location, to: modelPath)
                NSLog("✅ Successfully moved model to: \(modelPath.path)")
                
                // Resume continuation with the final path
                downloadContinuation?.resume(returning: modelPath)
                
            } else {
                NSLog("❌ Error: Temporary download file does not exist at expected location")
                let error = ModelError.downloadFailed("Temporary download file was removed by system")
                downloadContinuation?.resume(throwing: error)
            }
            
        } catch {
            NSLog("❌ Error moving downloaded model: \(error)")
            downloadContinuation?.resume(throwing: error)
        }
        
        downloadContinuation = nil
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            NSLog("❌ AI model download failed: \(error.localizedDescription)")
            downloadContinuation?.resume(throwing: error)
        }
        downloadContinuation = nil
    }
}

// MARK: - Supporting Types

struct DownloadInfo {
    let modelName: String
    let sizeGB: Double
    let isDownloadNeeded: Bool
    
    var formattedSize: String {
        return String(format: "%.1f GB", sizeGB)
    }
    
    var statusMessage: String {
        if isDownloadNeeded {
            return "AI model download required (\(formattedSize))"
        } else {
            return "AI model ready"
        }
    }
}

enum ModelError: LocalizedError {
    case corruptedDownload
    case validationFailed(String)
    case conversionFailed(String)
    case downloadFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .corruptedDownload:
            return "Downloaded AI model is corrupted"
        case .validationFailed(let message):
            return "Model validation failed: \(message)"
        case .conversionFailed(let message):
            return "Model conversion failed: \(message)"
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        }
    }
}