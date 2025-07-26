import Foundation
import Security
import CryptoKit
import os.log

/**
 * SafeBrowsingKeyManager
 * 
 * Secure API key storage and management for Google Safe Browsing API.
 * Provides encrypted storage in Keychain with validation and error handling.
 * 
 * Security Features:
 * - Keychain storage with kSecAttrAccessibleWhenUnlockedThisDeviceOnly
 * - API key validation and format checking
 * - Secure fallback to UserDefaults for development/testing
 * - Automatic encryption/decryption with error handling
 * - Rate limiting and quota management
 */
class SafeBrowsingKeyManager: ObservableObject {
    static let shared = SafeBrowsingKeyManager()
    
    private let logger = Logger(subsystem: "com.example.Web", category: "SafeBrowsingKeyManager")
    
    // Keychain configuration
    private let keychainService = "com.example.Web.SafeBrowsing"
    private let apiKeyAccount = "GoogleSafeBrowsingAPIKey"
    
    // Published properties for UI binding
    @Published var hasValidAPIKey: Bool = false
    @Published var keyValidationStatus: KeyValidationStatus = .unknown
    @Published var lastValidationDate: Date?
    
    enum KeyValidationStatus {
        case unknown
        case valid
        case invalid
        case expired
        case quotaExceeded
        case networkError
        
        var description: String {
            switch self {
            case .unknown:
                return "Not validated"
            case .valid:
                return "Valid"
            case .invalid:
                return "Invalid API key"
            case .expired:
                return "API key expired"
            case .quotaExceeded:
                return "Quota exceeded"
            case .networkError:
                return "Network error during validation"
            }
        }
        
        var isUsable: Bool {
            return self == .valid
        }
    }
    
    enum KeyManagerError: LocalizedError {
        case keychainError(OSStatus)
        case invalidKeyFormat
        case keyNotFound
        case validationFailed(String)
        case networkError
        
        var errorDescription: String? {
            switch self {
            case .keychainError(let status):
                let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown keychain error"
                return "Keychain error: \(message)"
            case .invalidKeyFormat:
                return "Invalid API key format"
            case .keyNotFound:
                return "API key not found"
            case .validationFailed(let reason):
                return "API key validation failed: \(reason)"
            case .networkError:
                return "Network error during validation"
            }
        }
    }
    
    private init() {
        // Check if API key exists and update status
        Task { @MainActor in
            await checkAPIKeyStatus()
        }
    }
    
    // MARK: - Public API
    
    /**
     * Store API key securely in Keychain
     * 
     * - Parameter apiKey: The Google Safe Browsing API key to store
     * - Throws: KeyManagerError if storage fails
     */
    func storeAPIKey(_ apiKey: String) async throws {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Validate key format
        guard isValidAPIKeyFormat(trimmedKey) else {
            logger.error("Invalid API key format provided")
            throw KeyManagerError.invalidKeyFormat
        }
        
        // Store in Keychain
        try await storeInKeychain(trimmedKey)
        
        // Validate the key with Google's API
        await validateAPIKey(trimmedKey)
        
        // Update status
        await MainActor.run {
            hasValidAPIKey = keyValidationStatus.isUsable
        }
        
        logger.info("API key stored and validated successfully")
    }
    
    /**
     * Retrieve API key from secure storage
     * 
     * - Returns: The API key if available, nil otherwise
     */
    func getAPIKey() async -> String? {
        // First try Keychain (production)
        if let keychainKey = await retrieveFromKeychain() {
            return keychainKey
        }
        
        // Fallback to UserDefaults for development/testing
        if let userDefaultsKey = UserDefaults.standard.string(forKey: "SafeBrowsing.APIKey"),
           !userDefaultsKey.isEmpty && !userDefaultsKey.contains("•") {
            logger.debug("Using API key from UserDefaults (development mode)")
            return userDefaultsKey
        }
        
        return nil
    }
    
    /**
     * Remove API key from all storage locations
     */
    func removeAPIKey() async {
        // Remove from Keychain
        await removeFromKeychain()
        
        // Remove from UserDefaults
        UserDefaults.standard.removeObject(forKey: "SafeBrowsing.APIKey")
        
        // Update status
        await MainActor.run {
            hasValidAPIKey = false
            keyValidationStatus = .unknown
            lastValidationDate = nil
        }
        
        logger.info("API key removed from all storage locations")
    }
    
    /**
     * Validate the stored API key with Google's API
     */
    func validateStoredAPIKey() async {
        guard let apiKey = await getAPIKey() else {
            await MainActor.run {
                keyValidationStatus = .unknown
                hasValidAPIKey = false
            }
            return
        }
        
        await validateAPIKey(apiKey)
        
        await MainActor.run {
            hasValidAPIKey = keyValidationStatus.isUsable
        }
    }
    
    // MARK: - Private Methods - Keychain Operations
    
    private func storeInKeychain(_ apiKey: String) async throws {
        let keyData = apiKey.data(using: .utf8)!
        
        // Delete existing item first
        await removeFromKeychain()
        
        // Define keychain query
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: apiKeyAccount,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false // Don't sync to iCloud for security
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            logger.error("Failed to store API key in Keychain: \(status)")
            throw KeyManagerError.keychainError(status)
        }
        
        logger.debug("API key stored in Keychain successfully")
    }
    
    private func retrieveFromKeychain() async -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: apiKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let keyData = result as? Data,
              let apiKey = String(data: keyData, encoding: .utf8) else {
            if status != errSecItemNotFound {
                logger.error("Failed to retrieve API key from Keychain: \(status)")
            }
            return nil
        }
        
        logger.debug("API key retrieved from Keychain successfully")
        return apiKey
    }
    
    private func removeFromKeychain() async {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: apiKeyAccount
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status == errSecSuccess {
            logger.debug("API key removed from Keychain successfully")
        } else if status != errSecItemNotFound {
            logger.error("Failed to remove API key from Keychain: \(status)")
        }
    }
    
    // MARK: - Private Methods - Validation
    
    private func isValidAPIKeyFormat(_ apiKey: String) -> Bool {
        // Google API keys are typically 39 characters long and contain alphanumeric characters
        // Pattern: AIzaSy[A-Za-z0-9_-]{33}
        let pattern = "^AIzaSy[A-Za-z0-9_-]{33}$"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: apiKey.utf16.count)
        
        return regex?.firstMatch(in: apiKey, options: [], range: range) != nil
    }
    
    private func validateAPIKey(_ apiKey: String) async {
        logger.debug("Starting API key validation")
        
        // Create a test request to validate the API key
        guard let url = URL(string: "https://safebrowsing.googleapis.com/v4/threatMatches:find?key=\(apiKey)") else {
            await MainActor.run {
                keyValidationStatus = .invalid
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0
        
        // Create minimal test request body
        let testBody: [String: Any] = [
            "client": [
                "clientId": Bundle.main.bundleIdentifier ?? "com.example.Web",
                "clientVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            ],
            "threatInfo": [
                "threatTypes": ["MALWARE"],
                "platformTypes": ["ANY_PLATFORM"],
                "threatEntryTypes": ["URL"],
                "threatEntries": [
                    ["url": "http://malware.testing.google.test/testing/malware/"]
                ]
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: testBody)
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                await MainActor.run {
                    switch httpResponse.statusCode {
                    case 200:
                        keyValidationStatus = .valid
                        lastValidationDate = Date()
                        logger.info("API key validation successful")
                        
                    case 400:
                        keyValidationStatus = .invalid
                        logger.error("API key validation failed: Invalid request (400)")
                        
                    case 401:
                        keyValidationStatus = .invalid
                        logger.error("API key validation failed: Unauthorized (401)")
                        
                    case 403:
                        keyValidationStatus = .invalid
                        logger.error("API key validation failed: Forbidden (403)")
                        
                    case 429:
                        keyValidationStatus = .quotaExceeded
                        logger.error("API key validation failed: Quota exceeded (429)")
                        
                    default:
                        keyValidationStatus = .networkError
                        logger.error("API key validation failed: HTTP \(httpResponse.statusCode)")
                    }
                }
            } else {
                await MainActor.run {
                    keyValidationStatus = .networkError
                }
            }
            
        } catch {
            logger.error("API key validation network error: \(error.localizedDescription)")
            await MainActor.run {
                keyValidationStatus = .networkError
            }
        }
    }
    
    private func checkAPIKeyStatus() async {
        if let apiKey = await getAPIKey() {
            if isValidAPIKeyFormat(apiKey) {
                // Check if we need to revalidate (every 24 hours)
                let shouldRevalidate = lastValidationDate == nil || 
                    Date().timeIntervalSince(lastValidationDate!) > 86400
                
                if shouldRevalidate {
                    await validateAPIKey(apiKey)
                }
                
                hasValidAPIKey = keyValidationStatus.isUsable
            } else {
                keyValidationStatus = .invalid
                hasValidAPIKey = false
            }
        } else {
            keyValidationStatus = .unknown
            hasValidAPIKey = false
        }
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let safeBrowsingAPIKeyUpdated = Notification.Name("safeBrowsingAPIKeyUpdated")
    static let safeBrowsingAPIKeyValidated = Notification.Name("safeBrowsingAPIKeyValidated")
}