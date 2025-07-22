import Foundation

/// Bundled model service for out-of-the-box AI experience
/// Handles locally bundled Gemma 3n models for zero-setup deployment
class BundledModelService: ObservableObject {
    
    // MARK: - Properties
    
    @Published var isModelReady: Bool = false
    @Published var modelLoadingProgress: Double = 0.0
    @Published var currentModel: BundledModel?
    
    private let fileManager = FileManager.default
    
    // MARK: - Bundled Models Configuration
    
    struct BundledModel {
        let name: String
        let filename: String
        let sizeBytes: Int64
        let quantization: String
        let contextLength: Int
        let modelType: ModelType
        
        enum ModelType {
            case gemma3n_2B
        }
        
        // Single bundled Gemma 3n model for out-of-box experience
        static let gemma3n_2B_Q8 = BundledModel(
            name: "Gemma 3n 2B Q8",
            filename: "gemma-3n-E2B-it-Q8_0.gguf",
            sizeBytes: 4_790_000_000, // 4.79 GB
            quantization: "Q8_0",
            contextLength: 32768,
            modelType: .gemma3n_2B
        )
    }
    
    // MARK: - Bundle Paths
    
    private var modelsBundle: URL? {
        return Bundle.main.url(forResource: "AI-Models", withExtension: nil)
    }
    
    private var modelsCacheDirectory: URL {
        let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let modelsCache = cacheDir.appendingPathComponent("Web/AI/BundledModels")
        
        // Ensure directory exists
        try? fileManager.createDirectory(at: modelsCache, withIntermediateDirectories: true)
        
        return modelsCache
    }
    
    // MARK: - Initialization
    
    init() {
        Task {
            await initializeBundledModel()
        }
    }
    
    // MARK: - Model Management
    
    /// Initialize the best bundled model for current hardware
    func initializeBundledModel() async {
        await MainActor.run {
            modelLoadingProgress = 0.0
            isModelReady = false
        }
        
        do {
            // Select optimal model based on hardware
            let selectedModel = selectOptimalBundledModel()
            
            await MainActor.run {
                currentModel = selectedModel
                modelLoadingProgress = 0.1
            }
            
            // Copy model from bundle to cache if needed
            let modelPath = try await ensureModelInCache(selectedModel)
            
            await MainActor.run {
                modelLoadingProgress = 0.8
            }
            
            // Validate model integrity
            try await validateModelFile(at: modelPath, for: selectedModel)
            
            await MainActor.run {
                modelLoadingProgress = 1.0
                isModelReady = true
            }
            
            NSLog("✅ Bundled model ready: \(selectedModel.name)")
            
        } catch {
            await MainActor.run {
                isModelReady = false
                modelLoadingProgress = 0.0
            }
            NSLog("❌ Failed to initialize bundled model: \(error)")
        }
    }
    
    /// Get the path to the ready model file
    func getModelPath() -> URL? {
        guard let model = currentModel, isModelReady else {
            return nil
        }
        
        return modelsCacheDirectory.appendingPathComponent(model.filename)
    }
    
    // MARK: - Private Methods
    
    private func selectOptimalBundledModel() -> BundledModel {
        // Single bundled model for simplicity and guaranteed compatibility
        return BundledModel.gemma3n_2B_Q8
    }
    
    private func ensureModelInCache(_ model: BundledModel) async throws -> URL {
        let cacheModelPath = modelsCacheDirectory.appendingPathComponent(model.filename)
        
        // Check if already in cache and valid
        if fileManager.fileExists(atPath: cacheModelPath.path) {
            let attributes = try fileManager.attributesOfItem(atPath: cacheModelPath.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            
            if fileSize == model.sizeBytes {
                NSLog("✅ Model already in cache: \(model.filename)")
                return cacheModelPath
            }
        }
        
        // Copy from bundle to cache
        guard let bundlePath = modelsBundle?.appendingPathComponent(model.filename),
              fileManager.fileExists(atPath: bundlePath.path) else {
            throw BundledModelError.modelNotFoundInBundle("Model \(model.filename) not found in app bundle")
        }
        
        NSLog("📦 Copying model from bundle to cache...")
        
        // Remove existing file if corrupted
        try? fileManager.removeItem(at: cacheModelPath)
        
        // Copy with progress tracking
        try await copyModelWithProgress(from: bundlePath, to: cacheModelPath, model: model)
        
        NSLog("✅ Model copied to cache: \(model.filename)")
        return cacheModelPath
    }
    
    private func copyModelWithProgress(from source: URL, to destination: URL, model: BundledModel) async throws {
        let chunkSize = 1024 * 1024 * 10 // 10MB chunks
        
        let sourceHandle = try FileHandle(forReadingFrom: source)
        defer { sourceHandle.closeFile() }
        
        fileManager.createFile(atPath: destination.path, contents: nil)
        let destHandle = try FileHandle(forWritingTo: destination)
        defer { destHandle.closeFile() }
        
        var totalBytesRead: Int64 = 0
        
        while totalBytesRead < model.sizeBytes {
            let chunk = sourceHandle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            
            destHandle.write(chunk)
            totalBytesRead += Int64(chunk.count)
            
            let progress = 0.1 + (Double(totalBytesRead) / Double(model.sizeBytes)) * 0.7
            
            await MainActor.run {
                self.modelLoadingProgress = progress
            }
        }
    }
    
    private func validateModelFile(at path: URL, for model: BundledModel) async throws {
        let attributes = try fileManager.attributesOfItem(atPath: path.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        
        guard fileSize == model.sizeBytes else {
            throw BundledModelError.corruptedModel("File size mismatch: expected \(model.sizeBytes), got \(fileSize)")
        }
        
        // Additional validation: check if it's a valid GGUF file
        let handle = try FileHandle(forReadingFrom: path)
        defer { handle.closeFile() }
        
        let header = handle.readData(ofLength: 4)
        let ggufMagic = Data([0x47, 0x47, 0x55, 0x46]) // "GGUF"
        
        guard header == ggufMagic else {
            throw BundledModelError.corruptedModel("Invalid GGUF magic number")
        }
        
        NSLog("✅ Model file validation passed")
    }
    
    // MARK: - Bundle Management
    
    /// Check if required models are bundled with the app
    static func validateAppBundle() -> BundleValidationResult {
        let bundle = Bundle.main
        
        guard let modelsBundle = bundle.url(forResource: "AI-Models", withExtension: nil) else {
            return .modelsNotBundled("AI-Models directory not found in app bundle")
        }
        
        let model = BundledModel.gemma3n_2B_Q8
        let modelPath = modelsBundle.appendingPathComponent(model.filename)
        
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            return .modelsMissing("Model file \(model.filename) not found in bundle")
        }
        
        // Check file size
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: modelPath.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            
            guard fileSize > 1_000_000_000 else { // At least 1GB
                return .modelsCorrupted("Model file appears corrupted (size: \(fileSize) bytes)")
            }
            
        } catch {
            return .modelsCorrupted("Cannot read model file attributes: \(error)")
        }
        
        return .valid("All bundled models validated successfully")
    }
}

// MARK: - Supporting Types

enum BundledModelError: LocalizedError {
    case modelNotFoundInBundle(String)
    case corruptedModel(String)
    case copyFailed(String)
    case validationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .modelNotFoundInBundle(let message):
            return "Model not found in bundle: \(message)"
        case .corruptedModel(let message):
            return "Corrupted model: \(message)"
        case .copyFailed(let message):
            return "Copy failed: \(message)"
        case .validationFailed(let message):
            return "Validation failed: \(message)"
        }
    }
}

enum BundleValidationResult {
    case valid(String)
    case modelsNotBundled(String)
    case modelsMissing(String)
    case modelsCorrupted(String)
    
    var isValid: Bool {
        switch self {
        case .valid:
            return true
        default:
            return false
        }
    }
    
    var message: String {
        switch self {
        case .valid(let msg), .modelsNotBundled(let msg), .modelsMissing(let msg), .modelsCorrupted(let msg):
            return msg
        }
    }
}