import Foundation

/// Automatic tokenizer.model downloader for Gemma models
/// Downloads the proper SentencePiece tokenizer from Hugging Face - NO MORE HARDCODED BULLSHIT!
class TokenizerDownloader {
    
    static let shared = TokenizerDownloader()
    
    private let session = URLSession.shared
    
    private init() {}
    
    /// Available Gemma models with their tokenizer URLs
    enum GemmaModel: String, CaseIterable {
        case gemma2_2B_IT = "google/gemma-2-2b-it"
        case gemma2_9B_IT = "google/gemma-2-9b-it" 
        case gemma2_27B_IT = "google/gemma-2-27b-it"
        case gemma3_1B_IT = "google/gemma-3-1b-it"
        case gemma3_27B_IT = "google/gemma-3-27b-it"
        
        var displayName: String {
            switch self {
            case .gemma2_2B_IT: return "Gemma 2 2B Instruct"
            case .gemma2_9B_IT: return "Gemma 2 9B Instruct"
            case .gemma2_27B_IT: return "Gemma 2 27B Instruct"
            case .gemma3_1B_IT: return "Gemma 3 1B Instruct"
            case .gemma3_27B_IT: return "Gemma 3 27B Instruct"
            }
        }
        
        var tokenizerURL: String {
            return "https://huggingface.co/\(self.rawValue)/resolve/main/tokenizer.model"
        }
    }
    
    /// Download tokenizer.model for a specific Gemma model
    func downloadTokenizer(for model: GemmaModel, to destinationPath: URL) async throws {
        NSLog("🚀 Downloading REAL tokenizer for \(model.displayName)...")
        NSLog("📡 URL: \(model.tokenizerURL)")
        
        guard let url = URL(string: model.tokenizerURL) else {
            throw TokenizerError.invalidURL("Invalid tokenizer URL for \(model.rawValue)")
        }
        
        // Create directory if needed
        let directory = destinationPath.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        
        do {
            // Download with progress tracking
            let (data, response) = try await session.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw TokenizerError.downloadFailed("Invalid response type")
            }
            
            guard httpResponse.statusCode == 200 else {
                throw TokenizerError.downloadFailed("HTTP \(httpResponse.statusCode)")
            }
            
            // Validate that we got a real SentencePiece model file
            guard data.count > 1000 else { // SentencePiece models are typically several MB
                throw TokenizerError.invalidFile("Downloaded file too small (\(data.count) bytes)")
            }
            
            // Check for SentencePiece magic bytes
            if !data.starts(with: [0x0A]) {
                NSLog("⚠️ Warning: File doesn't start with expected SentencePiece magic bytes")
            }
            
            // Write to destination
            try data.write(to: destinationPath)
            
            NSLog("✅ Successfully downloaded tokenizer.model (\(formatFileSize(data.count)))")
            NSLog("📁 Saved to: \(destinationPath.path)")
            
        } catch {
            NSLog("❌ Failed to download tokenizer: \(error)")
            throw TokenizerError.downloadFailed(error.localizedDescription)
        }
    }
    
    /// Check if tokenizer exists at path
    func tokenizerExists(at path: URL) -> Bool {
        return FileManager.default.fileExists(atPath: path.path)
    }
    
    /// Get tokenizer file size if it exists
    func tokenizerFileSize(at path: URL) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path.path),
              let fileSize = attributes[.size] as? Int64 else {
            return nil
        }
        return fileSize
    }
    
    /// Validate that a tokenizer file is valid SentencePiece format
    func validateTokenizer(at path: URL) throws {
        let data = try Data(contentsOf: path)
        
        guard data.count > 1000 else {
            throw TokenizerError.invalidFile("Tokenizer file too small")
        }
        
        // Basic SentencePiece format validation
        // SentencePiece files typically start with protobuf data
        if !data.starts(with: [0x0A]) {
            NSLog("⚠️ Warning: Tokenizer file may not be valid SentencePiece format")
        }
        
        NSLog("✅ Tokenizer file appears valid (\(formatFileSize(data.count)))")
    }
    
    /// Get recommended model based on system capabilities
    func recommendedModel() -> GemmaModel {
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let memoryGB = totalMemory / (1024 * 1024 * 1024)
        
        if memoryGB >= 32 {
            return .gemma2_9B_IT  // For high-memory systems
        } else if memoryGB >= 16 {
            return .gemma2_2B_IT  // For typical systems
        } else {
            return .gemma3_1B_IT  // For lower-memory systems
        }
    }
    
    private func formatFileSize(_ bytes: Int) -> String {
        let mb = Double(bytes) / (1024 * 1024)
        return String(format: "%.1f MB", mb)
    }
}

// MARK: - Errors

enum TokenizerError: LocalizedError {
    case invalidURL(String)
    case downloadFailed(String)
    case invalidFile(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL(let message):
            return "Invalid URL: \(message)"
        case .downloadFailed(let message):
            return "Download Failed: \(message)"
        case .invalidFile(let message):
            return "Invalid File: \(message)"
        }
    }
}