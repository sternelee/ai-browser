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
        case converting    // Converting GGUF → MLX
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
    
    private var modelsCacheDirectory: URL {
        let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let modelsCache = cacheDir.appendingPathComponent("Web/AI/Models")
        
        // Ensure directory exists with proper error handling
        do {
            try fileManager.createDirectory(at: modelsCache, withIntermediateDirectories: true, attributes: nil)
            NSLog("📁 Ensured models cache directory exists: \(modelsCache.path)")
        } catch {
            NSLog("⚠️ Warning: Could not create models cache directory: \(error)")
        }
        
        return modelsCache
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
        
        // Immediately check for existing model on initialization
        Task {
            await performIntelligentModelCheck()
        }
        
        NSLog("🤖 OnDemandModelService initialized - checking for existing AI model...")
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
        
        let modelPath = modelsCacheDirectory.appendingPathComponent(model.filename)

        // If we already have a converted MLX directory return it immediately
        if let preexisting = findExistingMLXModel() {
            return preexisting
        }

        // We no longer perform on-device GGUF→MLX conversion – the runtime will download a ready-made
        // MLX build instead.  Therefore, if the cached file is still the raw .gguf simply ignore it so
        // the caller can fall back to the remote model.
        if model.filename.hasSuffix(".gguf") {
            NSLog("ℹ️ Ignoring cached GGUF model – using remote MLX repository instead")
            return nil
        }

        // For non-GGUF assets (e.g. already-converted .mlx bundles) return the path if it exists.
        guard fileManager.fileExists(atPath: modelPath.path) else {
            Task {
                await MainActor.run {
                    isModelReady = false
                    downloadState = .notStarted
                }
            }
            return nil
        }

        return modelPath
    }
    
    /// Start AI initialization - downloads model if needed
    func initializeAI() async throws {
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
        
        // Start download process
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
        let tokenizerPath = modelsCacheDirectory.appendingPathComponent("tokenizer.model")
        
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
        let modelPath = modelsCacheDirectory.appendingPathComponent(model.filename)
        
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
        let modelPath = modelsCacheDirectory.appendingPathComponent(model.filename)
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
            let modelPath = modelsCacheDirectory.appendingPathComponent(model.filename)
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
    
    // MARK: - GGUF → MLX Conversion

    /// Converts a downloaded GGUF model to MLX format if the converted directory is not present.
    /// Returns the directory URL containing the MLX model on success.
    private func convertGGUFModelIfNeeded(ggufPath: URL) throws -> URL {
        let outputDir = ggufPath.deletingPathExtension().appendingPathExtension("mlx")
        // Already converted?
        if fileManager.fileExists(atPath: outputDir.path) {
            try ensureMainSafetensors(in: outputDir)
            return outputDir
        }

        // Update state for any UI bindings
        DispatchQueue.main.async {
            self.downloadState = .converting
        }

        NSLog("🔄 Converting GGUF model to MLX format: \(ggufPath.lastPathComponent) → \(outputDir.lastPathComponent)")

        // Ensure output directory exists
        try? fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true, attributes: nil)

        // Build conversion process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3", "-m", "mlx_lm.convert",
            "--hf-path", ggufPath.path,
            "--mlx-path", outputDir.path,
            "--quantize", "--q-bits", "4"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ModelError.conversionFailed(msg)
        }

        // Determine the real output directory – some converters override the --mlx-path
        let candidateDirs = try fileManager.contentsOfDirectory(at: modelsCacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
            .filter { url in
                url.hasDirectoryPath && url.appendingPathComponent("config.json").pathExtension == "json" && fileManager.fileExists(atPath: url.appendingPathComponent("config.json").path)
            }

        // Prefer outputDir if valid, otherwise fall back to most recently modified candidate
        var finalDir: URL = outputDir
        if fileManager.fileExists(atPath: outputDir.appendingPathComponent("config.json").path) == false, let recent = candidateDirs.sorted(by: { (a,b) -> Bool in
            let aDate = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            let bDate = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            return aDate > bDate
        }).first {
            finalDir = recent
            NSLog("ℹ️ Converter produced directory \(recent.lastPathComponent); using that instead of expected name")
        }

        // Final sanity check
        guard fileManager.fileExists(atPath: finalDir.appendingPathComponent("config.json").path) else {
            throw ModelError.conversionFailed("config.json missing in converted model directory")
        }

        NSLog("✅ Model conversion completed: \(finalDir.lastPathComponent)")

        // Guarantee MLX runtime finds expected filename
        try? ensureMainSafetensors(in: finalDir)

        DispatchQueue.main.async {
            if self.downloadState == .converting {
                self.downloadState = .ready
            }
            self.isModelReady = true
        }

        return finalDir
    }
    
    /// Ensure there is a main.safetensors file (or symlink) inside the MLX model directory – MLX expects that name.
    private func ensureMainSafetensors(in dir: URL) throws {
        let mainPath = dir.appendingPathComponent("main.safetensors")
        if fileManager.fileExists(atPath: mainPath.path) {
            return // already present
        }

        // Find any *.safetensors file (excluding potential index files)
        let items = try fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        if let firstWeights = items.first(where: { $0.pathExtension == "safetensors" }) {
            try fileManager.createSymbolicLink(at: mainPath, withDestinationURL: firstWeights)
            NSLog("🔗 Created symlink main.safetensors → \(firstWeights.lastPathComponent)")
        } else {
            throw ModelError.conversionFailed("No .safetensors weight file found in converted directory")
        }
    }
    
    /// Scan the cache directory for an existing MLX model (directory containing config.json)
    private func findExistingMLXModel() -> URL? {
        guard let dirs = try? fileManager.contentsOfDirectory(at: modelsCacheDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return nil
        }
        for dir in dirs {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false else { continue }
            let config = dir.appendingPathComponent("config.json")
            if fileManager.fileExists(atPath: config.path) {
                try? ensureMainSafetensors(in: dir)
                return dir
            }
        }
        return nil
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        // Update progress on main thread
        DispatchQueue.main.async {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            self.downloadProgress = min(max(progress, 0.0), 0.95) // Cap at 95% until validation
            
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
            let modelPath = modelsCacheDirectory.appendingPathComponent(model.filename)
            
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