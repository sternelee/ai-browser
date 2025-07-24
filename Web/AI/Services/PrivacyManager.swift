import Foundation
import CryptoKit

/// Privacy manager for AI conversation data
/// Handles AES-256 encryption, data retention, and privacy controls
class PrivacyManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var encryptionEnabled: Bool = true
    @Published var dataRetentionDays: Int = 7
    @Published var isInitialized: Bool = false
    
    // MARK: - Private Properties
    
    private var encryptionKey: SymmetricKey?
    private let keychain = Keychain(service: "com.web.ai.privacy")
    private let fileManager = FileManager.default
    private var secureDataDirectory: URL
    
    // MARK: - Configuration
    
    private let encryptionKeyIdentifier = "ai_conversation_encryption_key"
    private let maxDataRetentionDays = 30
    private let minDataRetentionDays = 1
    
    // MARK: - Initialization
    
    init() {
        // Set up secure data directory
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        secureDataDirectory = applicationSupport.appendingPathComponent("Web/AI/SecureData")
        
        // Ensure secure directory exists
        do {
            try fileManager.createDirectory(at: secureDataDirectory, withIntermediateDirectories: true)
            
            // Set directory to not be backed up
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try secureDataDirectory.setResourceValues(resourceValues)
            
        } catch {
            NSLog("❌ Failed to create secure data directory: \(error)")
        }
        
        NSLog("🔒 Privacy Manager initialized")
    }
    
    // MARK: - Public Interface
    
    /// Initialize privacy system without accessing keychain (delayed until first use)
    func initialize() async throws {
        do {
            // Skip encryption key setup on initialization to avoid keychain access
            // Key will be generated lazily when first needed
            
            // Clean up expired data (doesn't require keychain)
            try await cleanupExpiredData()
            
            isInitialized = true
            NSLog("✅ Privacy Manager initialization completed (keychain access deferred)")
            
        } catch {
            NSLog("❌ Privacy Manager initialization failed: \(error)")
            throw PrivacyError.initializationFailed(error.localizedDescription)
        }
    }
    
    /// Encrypt conversation data
    func encryptConversationData(_ data: Data) async throws -> EncryptedData {
        // Lazy initialization of encryption key when first needed
        if encryptionKey == nil {
            try await setupEncryptionKey()
        }
        
        guard let key = encryptionKey else {
            throw PrivacyError.encryptionKeyNotAvailable
        }
        
        do {
            // Generate nonce for this encryption operation
            let nonce = AES.GCM.Nonce()
            
            // Encrypt the data
            let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)
            
            // Create encrypted data wrapper
            let encryptedData = EncryptedData(
                ciphertext: sealedBox.ciphertext,
                nonce: nonce,
                tag: sealedBox.tag,
                timestamp: Date()
            )
            
            return encryptedData
            
        } catch {
            throw PrivacyError.encryptionFailed(error.localizedDescription)
        }
    }
    
    /// Decrypt conversation data
    func decryptConversationData(_ encryptedData: EncryptedData) async throws -> Data {
        // Lazy initialization of encryption key when first needed
        if encryptionKey == nil {
            try await setupEncryptionKey()
        }
        
        guard let key = encryptionKey else {
            throw PrivacyError.encryptionKeyNotAvailable
        }
        
        do {
            // Reconstruct sealed box
            let sealedBox = try AES.GCM.SealedBox(
                nonce: encryptedData.nonce,
                ciphertext: encryptedData.ciphertext,
                tag: encryptedData.tag
            )
            
            // Decrypt the data
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            
            return decryptedData
            
        } catch {
            throw PrivacyError.decryptionFailed(error.localizedDescription)
        }
    }
    
    /// Store encrypted conversation
    func storeConversation(_ conversation: ConversationExport) async throws {
        do {
            // TODO: Serialize conversation when Codable conformance is fixed
            let data = Data() // Placeholder
            // let data = try JSONEncoder().encode(conversation)
            
            // Encrypt data
            let encryptedData = try await encryptConversationData(data)
            
            // Store encrypted data
            let filename = "conversation_\(conversation.sessionId).encrypted"
            let fileURL = secureDataDirectory.appendingPathComponent(filename)
            
            // TODO: Implement proper serialization for EncryptedData
            let encryptedBytes = Data() // Placeholder
            try encryptedBytes.write(to: fileURL)
            
            NSLog("🔒 Encrypted conversation stored: \(filename)")
            
        } catch {
            throw PrivacyError.storageError(error.localizedDescription)
        }
    }
    
    /// Retrieve and decrypt conversation
    func retrieveConversation(_ sessionId: String) async throws -> ConversationExport? {
        do {
            let filename = "conversation_\(sessionId).encrypted"
            let fileURL = secureDataDirectory.appendingPathComponent(filename)
            
            guard fileManager.fileExists(atPath: fileURL.path) else {
                return nil
            }
            
            // TODO: Implement proper deserialization for EncryptedData
            let encryptedBytes = try Data(contentsOf: fileURL)
            // let encryptedData = try JSONDecoder().decode(EncryptedData.self, from: encryptedBytes)
            return nil // Placeholder
            
            /*
            // Check if data has expired
            let age = Date().timeIntervalSince(encryptedData.timestamp)
            if age > TimeInterval(dataRetentionDays * 24 * 3600) {
                // Data has expired, delete it
                try fileManager.removeItem(at: fileURL)
                NSLog("🗑️ Expired conversation data deleted: \(filename)")
                return nil
            }
            
            // Decrypt data
            let decryptedData = try decryptConversationData(encryptedData)
            
            // Deserialize conversation
            let conversation = try JSONDecoder().decode(ConversationExport.self, from: decryptedData)
            
            return conversation
            */
            
        } catch {
            throw PrivacyError.retrievalError(error.localizedDescription)
        }
    }
    
    /// Get list of stored conversation sessions
    func getStoredSessions() async throws -> [String] {
        do {
            let contents = try fileManager.contentsOfDirectory(at: secureDataDirectory, includingPropertiesForKeys: nil)
            
            let sessions = contents
                .filter { $0.pathExtension == "encrypted" }
                .compactMap { url -> String? in
                    let filename = url.deletingPathExtension().lastPathComponent
                    if filename.hasPrefix("conversation_") {
                        return String(filename.dropFirst("conversation_".count))
                    }
                    return nil
                }
            
            return sessions
            
        } catch {
            throw PrivacyError.retrievalError(error.localizedDescription)
        }
    }
    
    /// Delete specific conversation
    func deleteConversation(_ sessionId: String) async throws {
        let filename = "conversation_\(sessionId).encrypted"
        let fileURL = secureDataDirectory.appendingPathComponent(filename)
        
        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
                NSLog("🗑️ Conversation deleted: \(sessionId)")
            }
        } catch {
            throw PrivacyError.deletionError(error.localizedDescription)
        }
    }
    
    /// Delete all AI conversation data
    func purgeAllData() async throws {
        do {
            let contents = try fileManager.contentsOfDirectory(at: secureDataDirectory, includingPropertiesForKeys: nil)
            
            for fileURL in contents {
                try fileManager.removeItem(at: fileURL)
            }
            
            NSLog("🗑️ All AI conversation data purged")
            
        } catch {
            throw PrivacyError.purgeError(error.localizedDescription)
        }
    }
    
    /// Update data retention policy
    func updateDataRetentionPolicy(days: Int) async throws {
        let clampedDays = max(minDataRetentionDays, min(maxDataRetentionDays, days))
        dataRetentionDays = clampedDays
        
        // Clean up data that now exceeds the new retention period
        try await cleanupExpiredData()
        
        NSLog("🔒 Data retention policy updated: \(clampedDays) days")
    }
    
    /// Get privacy status
    func getPrivacyStatus() -> PrivacyStatus {
        return PrivacyStatus(
            encryptionEnabled: encryptionEnabled,
            dataRetentionDays: dataRetentionDays,
            hasEncryptionKey: encryptionKey != nil,
            secureDataDirectory: secureDataDirectory,
            storedConversations: (try? fileManager.contentsOfDirectory(at: secureDataDirectory, includingPropertiesForKeys: nil).count) ?? 0
        )
    }
    
    // MARK: - Private Methods
    
    private func setupEncryptionKey() async throws {
        // We want to be resilient: if keychain read fails (e.g. after OS upgrade,
        // permissions reset, or corrupted entry) we generate a fresh key rather
        // than aborting the entire AI launch sequence. Existing encrypted files
        // may become unreadable, but that is preferable to blocking the app.
        do {
            let existingKeyData: Data?
            do {
                existingKeyData = try keychain.getData(encryptionKeyIdentifier)
            } catch {
                // Log and treat as missing – will generate a new key below.
                NSLog("⚠️ Keychain retrieval failed (will regenerate key): \(error)")
                existingKeyData = nil
            }

            if let data = existingKeyData {
                encryptionKey = SymmetricKey(data: data)
                NSLog("🔑 Retrieved existing encryption key from keychain")
            } else {
                // Generate new key
                let newKey = SymmetricKey(size: .bits256)
                encryptionKey = newKey

                // Store key in keychain; ignore duplicate errors as we just tried to read
                do {
                    try keychain.set(newKey.data, forKey: encryptionKeyIdentifier)
                    NSLog("🔑 Generated and stored new encryption key")
                } catch {
                    NSLog("⚠️ Failed to store new key in keychain: \(error)")
                    // Do not throw – we already have a key in memory and can continue.
                }
            }
        }
    }
    
    private func cleanupExpiredData() async throws {
        do {
            let contents = try fileManager.contentsOfDirectory(at: secureDataDirectory, includingPropertiesForKeys: [.contentModificationDateKey])
            
            let cutoffDate = Date().addingTimeInterval(-TimeInterval(dataRetentionDays * 24 * 3600))
            var deletedCount = 0
            
            for fileURL in contents {
                let resourceValues = try fileURL.resourceValues(forKeys: [.contentModificationDateKey])
                
                if let modificationDate = resourceValues.contentModificationDate,
                   modificationDate < cutoffDate {
                    try fileManager.removeItem(at: fileURL)
                    deletedCount += 1
                }
            }
            
            if deletedCount > 0 {
                NSLog("🗑️ Cleaned up \(deletedCount) expired conversation files")
            }
            
        } catch {
            NSLog("⚠️ Failed to cleanup expired data: \(error)")
        }
    }
}

// MARK: - Supporting Types

/// Encrypted data container
struct EncryptedData {
    let ciphertext: Data
    let nonce: AES.GCM.Nonce
    let tag: Data
    let timestamp: Date
}

/// Privacy status information
struct PrivacyStatus {
    let encryptionEnabled: Bool
    let dataRetentionDays: Int
    let hasEncryptionKey: Bool
    let secureDataDirectory: URL
    let storedConversations: Int
}

/// Privacy-related errors
enum PrivacyError: LocalizedError {
    case initializationFailed(String)
    case encryptionKeyNotAvailable
    case keyGenerationFailed(String)
    case encryptionFailed(String)
    case decryptionFailed(String)
    case storageError(String)
    case retrievalError(String)
    case deletionError(String)
    case purgeError(String)
    
    var errorDescription: String? {
        switch self {
        case .initializationFailed(let message):
            return "Privacy initialization failed: \(message)"
        case .encryptionKeyNotAvailable:
            return "Encryption key not available"
        case .keyGenerationFailed(let message):
            return "Key generation failed: \(message)"
        case .encryptionFailed(let message):
            return "Encryption failed: \(message)"
        case .decryptionFailed(let message):
            return "Decryption failed: \(message)"
        case .storageError(let message):
            return "Storage error: \(message)"
        case .retrievalError(let message):
            return "Retrieval error: \(message)"
        case .deletionError(let message):
            return "Deletion error: \(message)"
        case .purgeError(let message):
            return "Data purge error: \(message)"
        }
    }
}

// MARK: - Keychain Wrapper

/// Simple keychain wrapper for secure key storage
private class Keychain {
    private let service: String
    
    init(service: String) {
        self.service = service
    }
    
    func set(_ data: Data, forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecDuplicateItem {
            // Update existing item
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key
            ]
            
            let updateAttributes: [String: Any] = [
                kSecValueData as String: data
            ]
            
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw PrivacyError.keyGenerationFailed("Failed to update keychain item")
            }
        } else {
            guard status == errSecSuccess else {
                throw PrivacyError.keyGenerationFailed("Failed to store keychain item")
            }
        }
    }
    
    func getData(_ key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            return nil
        }
        
        guard status == errSecSuccess,
              let data = result as? Data else {
            throw PrivacyError.retrievalError("Failed to retrieve keychain item")
        }
        
        return data
    }
}

// MARK: - Extensions

extension SymmetricKey {
    var data: Data {
        return withUnsafeBytes { bytes in
            Data(bytes)
        }
    }
}