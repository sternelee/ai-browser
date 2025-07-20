# Phase 4: Security & Privacy - Detailed Implementation

## Overview
This phase implements comprehensive security and privacy features including a native ad blocker with EasyList integration, secure password management with Keychain, and advanced privacy protections.

## 1. Native Ad Blocker

### High-Performance Content Blocking
```swift
// AdBlockService.swift - Native content blocking with EasyList integration
import WebKit
import Network
import CryptoKit

class AdBlockService: ObservableObject {
    static let shared = AdBlockService()
    
    @Published var isEnabled: Bool = true {
        didSet {
            if isEnabled != oldValue {
                updateContentBlockingRules()
            }
        }
    }
    
    @Published var blockedRequestsCount: Int = 0
    @Published var blockedRequestsToday: Int = 0
    @Published var filterListsStatus: [String: FilterListStatus] = [:]
    
    private let contentRuleListStore = WKContentRuleListStore.default()
    private var activeRuleLists: [WKContentRuleList] = []
    private let maxRulesPerList = 50000 // WebKit limit
    
    // Enhanced filter lists with priority and categories
    private let filterLists = [
        FilterList(
            name: "EasyList",
            url: URL(string: "https://easylist.to/easylist/easylist.txt")!,
            category: .ads,
            priority: .high,
            isEnabled: true
        ),
        FilterList(
            name: "EasyPrivacy",
            url: URL(string: "https://easylist.to/easylist/easyprivacy.txt")!,
            category: .privacy,
            priority: .high,
            isEnabled: true
        ),
        FilterList(
            name: "uBlock Origin",
            url: URL(string: "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters.txt")!,
            category: .comprehensive,
            priority: .medium,
            isEnabled: false
        ),
        FilterList(
            name: "Fanboy Annoyances",
            url: URL(string: "https://easylist.to/easylist/fanboy-annoyance.txt")!,
            category: .annoyances,
            priority: .low,
            isEnabled: false
        )
    ]
    
    struct FilterList {
        let name: String
        let url: URL
        let category: Category
        let priority: Priority
        let isEnabled: Bool
        
        enum Category {
            case ads, privacy, comprehensive, annoyances, malware
        }
        
        enum Priority {
            case high, medium, low
        }
    }
    
    struct FilterListStatus {
        let lastUpdated: Date
        let ruleCount: Int
        let isActive: Bool
        let errorMessage: String?
    }
    
    init() {
        loadStoredSettings()
        loadContentBlockingRules()
        setupDailyStatsReset()
    }
    
    // MARK: - WebView Configuration
    func configureWebView(_ webView: WKWebView) {
        guard isEnabled else { return }
        
        // Add active rule lists
        for ruleList in activeRuleLists {
            webView.configuration.userContentController.add(ruleList)
        }
        
        // Add JavaScript for tracking and enhanced blocking
        let blockingScript = generateBlockingScript()
        let script = WKUserScript(source: blockingScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        webView.configuration.userContentController.addUserScript(script)
        webView.configuration.userContentController.add(self, name: "adBlockHandler")
        
        // Setup request interception
        setupRequestInterception(for: webView)
    }
    
    private func generateBlockingScript() -> String {
        return """
        (function() {
            'use strict';
            
            let blockedCount = 0;
            const blockedDomains = new Set();
            
            // Enhanced request blocking
            const originalFetch = window.fetch;
            const originalXHROpen = XMLHttpRequest.prototype.open;
            const originalImageSrc = Object.getOwnPropertyDescriptor(HTMLImageElement.prototype, 'src');
            
            // Tracking pixel detection patterns
            const trackingPatterns = [
                /\\b(analytics|tracking|metrics|stats|telemetry)\\b/i,
                /\\b(doubleclick|googlesyndication|googletagmanager)\\b/i,
                /\\b(facebook\\.com\\/tr|connect\\.facebook\\.net)\\b/i,
                /\\b(twitter\\.com\\/i\\/adsct)\\b/i,
                /\\b(amazon-adsystem|adsystem\\.amazon)\\b/i
            ];
            
            function isTrackingRequest(url) {
                return trackingPatterns.some(pattern => pattern.test(url));
            }
            
            function reportBlocked(url) {
                blockedCount++;
                const domain = new URL(url).hostname;
                blockedDomains.add(domain);
                
                window.webkit.messageHandlers.adBlockHandler.postMessage({
                    type: 'blocked',
                    url: url,
                    domain: domain,
                    count: blockedCount
                });
            }
            
            // Enhanced fetch interception
            window.fetch = function(...args) {
                const url = args[0];
                if (typeof url === 'string' && isTrackingRequest(url)) {
                    reportBlocked(url);
                    return Promise.reject(new TypeError('Blocked by Ad Blocker'));
                }
                
                return originalFetch.apply(this, args).catch(error => {
                    if (error.message && error.message.includes('blocked')) {
                        reportBlocked(url);
                    }
                    throw error;
                });
            };
            
            // Enhanced XMLHttpRequest interception
            XMLHttpRequest.prototype.open = function(method, url, ...args) {
                if (isTrackingRequest(url)) {
                    reportBlocked(url);
                    throw new Error('Blocked by Ad Blocker');
                }
                
                this.addEventListener('error', function() {
                    reportBlocked(url);
                });
                
                return originalXHROpen.apply(this, [method, url, ...args]);
            };
            
            // Image source interception
            Object.defineProperty(HTMLImageElement.prototype, 'src', {
                get: originalImageSrc.get,
                set: function(value) {
                    if (isTrackingRequest(value)) {
                        reportBlocked(value);
                        return;
                    }
                    originalImageSrc.set.call(this, value);
                }
            });
            
            // Mutation observer for dynamic content
            const observer = new MutationObserver(function(mutations) {
                mutations.forEach(function(mutation) {
                    mutation.addedNodes.forEach(function(node) {
                        if (node.nodeType === Node.ELEMENT_NODE) {
                            // Check for tracking scripts
                            if (node.tagName === 'SCRIPT' && node.src && isTrackingRequest(node.src)) {
                                node.remove();
                                reportBlocked(node.src);
                            }
                            
                            // Check for tracking images
                            if (node.tagName === 'IMG' && node.src && isTrackingRequest(node.src)) {
                                node.remove();
                                reportBlocked(node.src);
                            }
                        }
                    });
                });
            });
            
            observer.observe(document, { childList: true, subtree: true });
            
            // Report stats periodically
            setInterval(() => {
                if (blockedCount > 0) {
                    window.webkit.messageHandlers.adBlockHandler.postMessage({
                        type: 'stats',
                        totalBlocked: blockedCount,
                        blockedDomains: Array.from(blockedDomains)
                    });
                }
            }, 5000);
            
        })();
        """
    }
    
    private func setupRequestInterception(for webView: WKWebView) {
        // Additional request interception at the WebKit level
        let userContentController = webView.configuration.userContentController
        
        // Custom URL scheme handler for blocked requests
        let schemeHandler = BlockedContentSchemeHandler()
        webView.configuration.setURLSchemeHandler(schemeHandler, forURLScheme: "blocked")
    }
    
    // MARK: - Filter List Management
    private func loadContentBlockingRules() {
        Task {
            await updateFilterLists()
            await compileContentRules()
        }
    }
    
    private func updateFilterLists() async {
        let enabledLists = filterLists.filter { $0.isEnabled }
        
        await withTaskGroup(of: Void.self) { group in
            for filterList in enabledLists {
                group.addTask {
                    await self.downloadAndProcessFilterList(filterList)
                }
            }
        }
    }
    
    private func downloadAndProcessFilterList(_ filterList: FilterList) async {
        do {
            print("Downloading filter list: \(filterList.name)")
            
            let (data, response) = try await URLSession.shared.data(from: filterList.url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                await updateFilterListStatus(filterList.name, error: "HTTP Error")
                return
            }
            
            let rules = String(data: data, encoding: .utf8) ?? ""
            let contentRules = await convertToContentBlockingRules(rules, for: filterList)
            
            await compileRuleList(name: filterList.name, rules: contentRules)
            await updateFilterListStatus(filterList.name, ruleCount: contentRules.components(separatedBy: "\n").count)
            
        } catch {
            print("Failed to download filter list \(filterList.name): \(error)")
            await updateFilterListStatus(filterList.name, error: error.localizedDescription)
        }
    }
    
    private func convertToContentBlockingRules(_ adBlockRules: String, for filterList: FilterList) async -> String {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let lines = adBlockRules.components(separatedBy: .newlines)
                var contentRules: [[String: Any]] = []
                var ruleCount = 0
                
                for line in lines {
                    guard ruleCount < self.maxRulesPerList else { break }
                    
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    
                    // Skip comments, empty lines, and metadata
                    guard !trimmed.isEmpty && 
                          !trimmed.hasPrefix("!") && 
                          !trimmed.hasPrefix("[") &&
                          !trimmed.hasPrefix("# ") else { continue }
                    
                    // Process different rule types
                    if let rule = self.processBlockingRule(trimmed) {
                        contentRules.append(rule)
                        ruleCount += 1
                    } else if let rule = self.processHidingRule(trimmed) {
                        contentRules.append(rule)
                        ruleCount += 1
                    } else if let rule = self.processWhitelistRule(trimmed) {
                        contentRules.append(rule)
                        ruleCount += 1
                    }
                }
                
                let ruleSet = [
                    "version": 1,
                    "rules": contentRules
                ]
                
                do {
                    let jsonData = try JSONSerialization.data(withJSONObject: ruleSet, options: .prettyPrinted)
                    let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
                    continuation.resume(returning: jsonString)
                } catch {
                    continuation.resume(returning: "[]")
                }
            }
        }
    }
    
    private func processBlockingRule(_ rule: String) -> [String: Any]? {
        // Handle basic blocking rules (||example.com^)
        if rule.hasPrefix("||") && rule.hasSuffix("^") {
            let domain = String(rule.dropFirst(2).dropLast(1))
            return [
                "trigger": [
                    "url-filter": ".*\(NSRegularExpression.escapedPattern(for: domain)).*",
                    "resource-type": ["document", "image", "script", "style-sheet", "raw", "font"]
                ],
                "action": [
                    "type": "block"
                ]
            ]
        }
        
        // Handle path-based blocking (example.com/ads/*)
        if rule.contains("/") && !rule.contains("##") {
            let urlFilter = NSRegularExpression.escapedPattern(for: rule.replacingOccurrences(of: "*", with: ".*"))
            return [
                "trigger": [
                    "url-filter": urlFilter,
                    "resource-type": ["image", "script", "style-sheet", "raw"]
                ],
                "action": [
                    "type": "block"
                ]
            ]
        }
        
        return nil
    }
    
    private func processHidingRule(_ rule: String) -> [String: Any]? {
        // Handle element hiding rules (example.com##.ad-banner)
        if rule.contains("##") {
            let parts = rule.components(separatedBy: "##")
            guard parts.count == 2 else { return nil }
            
            let domain = parts[0]
            let selector = parts[1]
            
            return [
                "trigger": [
                    "url-filter": ".*",
                    "if-domain": domain.isEmpty ? ["*"] : [domain]
                ],
                "action": [
                    "type": "css-display-none",
                    "selector": selector
                ]
            ]
        }
        
        return nil
    }
    
    private func processWhitelistRule(_ rule: String) -> [String: Any]? {
        // Handle whitelist rules (@@||example.com^)
        if rule.hasPrefix("@@") {
            let cleanRule = String(rule.dropFirst(2))
            if cleanRule.hasPrefix("||") && cleanRule.hasSuffix("^") {
                let domain = String(cleanRule.dropFirst(2).dropLast(1))
                return [
                    "trigger": [
                        "url-filter": ".*\(NSRegularExpression.escapedPattern(for: domain)).*"
                    ],
                    "action": [
                        "type": "ignore-previous-rules"
                    ]
                ]
            }
        }
        
        return nil
    }
    
    private func compileRuleList(name: String, rules: String) async {
        do {
            try await contentRuleListStore?.compileContentRuleList(
                forIdentifier: name,
                encodedContentRuleList: rules
            )
            print("Successfully compiled rule list: \(name)")
        } catch {
            print("Failed to compile rule list \(name): \(error)")
            await updateFilterListStatus(name, error: error.localizedDescription)
        }
    }
    
    private func compileContentRules() async {
        activeRuleLists.removeAll()
        
        do {
            for filterList in filterLists where filterList.isEnabled {
                if let ruleList = try await contentRuleListStore?.contentRuleList(forIdentifier: filterList.name) {
                    activeRuleLists.append(ruleList)
                }
            }
            
            await MainActor.run {
                updateContentBlockingRules()
            }
        } catch {
            print("Failed to load content rules: \(error)")
        }
    }
    
    @MainActor
    private func updateFilterListStatus(_ name: String, ruleCount: Int = 0, error: String? = nil) {
        filterListsStatus[name] = FilterListStatus(
            lastUpdated: Date(),
            ruleCount: ruleCount,
            isActive: error == nil,
            errorMessage: error
        )
    }
    
    private func updateContentBlockingRules() {
        // Notify all active webviews to update their content blocking rules
        NotificationCenter.default.post(name: .updateContentBlocking, object: activeRuleLists)
    }
    
    // MARK: - Statistics and Storage
    private func loadStoredSettings() {
        if let data = UserDefaults.standard.data(forKey: "adBlockSettings"),
           let settings = try? JSONDecoder().decode(AdBlockSettings.self, from: data) {
            isEnabled = settings.isEnabled
            blockedRequestsCount = settings.totalBlockedRequests
        }
        
        // Load daily stats
        let today = Calendar.current.startOfDay(for: Date())
        if let lastResetDate = UserDefaults.standard.object(forKey: "lastStatsReset") as? Date,
           Calendar.current.isDate(lastResetDate, inSameDayAs: today) {
            blockedRequestsToday = UserDefaults.standard.integer(forKey: "blockedRequestsToday")
        } else {
            resetDailyStats()
        }
    }
    
    private func saveSettings() {
        let settings = AdBlockSettings(
            isEnabled: isEnabled,
            totalBlockedRequests: blockedRequestsCount
        )
        
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: "adBlockSettings")
        }
        
        UserDefaults.standard.set(blockedRequestsToday, forKey: "blockedRequestsToday")
    }
    
    private func setupDailyStatsReset() {
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            let today = Calendar.current.startOfDay(for: Date())
            if let lastReset = UserDefaults.standard.object(forKey: "lastStatsReset") as? Date,
               !Calendar.current.isDate(lastReset, inSameDayAs: today) {
                self.resetDailyStats()
            }
        }
    }
    
    private func resetDailyStats() {
        blockedRequestsToday = 0
        UserDefaults.standard.set(Date(), forKey: "lastStatsReset")
        UserDefaults.standard.set(0, forKey: "blockedRequestsToday")
    }
    
    struct AdBlockSettings: Codable {
        let isEnabled: Bool
        let totalBlockedRequests: Int
    }
}

// MARK: - Script Message Handler
extension AdBlockService: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "adBlockHandler",
              let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }
        
        DispatchQueue.main.async {
            switch type {
            case "blocked":
                self.blockedRequestsCount += 1
                self.blockedRequestsToday += 1
                self.saveSettings()
                
            case "stats":
                if let totalBlocked = body["totalBlocked"] as? Int {
                    self.blockedRequestsCount += totalBlocked
                    self.blockedRequestsToday += totalBlocked
                    self.saveSettings()
                }
                
            default:
                break
            }
        }
    }
}

// MARK: - Custom URL Scheme Handler
class BlockedContentSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        // Return empty response for blocked content
        let response = URLResponse(
            url: urlSchemeTask.request.url!,
            mimeType: "text/plain",
            expectedContentLength: 0,
            textEncodingName: nil
        )
        
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didFinish()
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Handle task cancellation
    }
}

// MARK: - Notification Extensions
extension Notification.Name {
    static let updateContentBlocking = Notification.Name("updateContentBlocking")
}
```

## 2. Password Manager Integration

### Secure Password Management with Keychain
```swift
// PasswordManager.swift - Secure password management with advanced features
import Security
import CryptoKit
import LocalAuthentication

class PasswordManager: ObservableObject {
    static let shared = PasswordManager()
    
    @Published var savedPasswords: [SavedPassword] = []
    @Published var isAutofillEnabled: Bool = true
    @Published var requireBiometricAuth: Bool = true
    @Published var passwordGeneratorSettings = PasswordGeneratorSettings()
    
    private let serviceName = "com.web.browser.passwords"
    private let encryptionKey: SymmetricKey
    private let context = LAContext()
    
    struct SavedPassword: Identifiable, Codable {
        let id = UUID()
        let website: String
        let username: String
        let encryptedPassword: Data
        let dateCreated: Date
        let lastUsed: Date
        let lastModified: Date
        let strength: PasswordStrength
        let notes: String?
        
        enum PasswordStrength: String, Codable {
            case weak, medium, strong, veryStrong
        }
    }
    
    struct PasswordGeneratorSettings: Codable {
        var length: Int = 16
        var includeUppercase: Bool = true
        var includeLowercase: Bool = true
        var includeNumbers: Bool = true
        var includeSymbols: Bool = true
        var excludeSimilar: Bool = true
        var excludeAmbiguous: Bool = true
    }
    
    init() {
        // Generate or retrieve encryption key
        self.encryptionKey = getOrCreateEncryptionKey()
        loadSavedPasswords()
        loadSettings()
    }
    
    // MARK: - Encryption Key Management
    private func getOrCreateEncryptionKey() -> SymmetricKey {
        let keyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(serviceName).encryptionKey",
            kSecAttrAccount as String: "masterKey",
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(keyQuery as CFDictionary, &result)
        
        if status == errSecSuccess, let keyData = result as? Data {
            return SymmetricKey(data: keyData)
        } else {
            // Generate new key
            let newKey = SymmetricKey(size: .bits256)
            let keyData = newKey.withUnsafeBytes { Data($0) }
            
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "\(serviceName).encryptionKey",
                kSecAttrAccount as String: "masterKey",
                kSecValueData as String: keyData,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
            
            SecItemAdd(addQuery as CFDictionary, nil)
            return newKey
        }
    }
    
    // MARK: - Password Storage and Retrieval
    func savePassword(website: String, username: String, password: String, notes: String? = nil) async -> Bool {
        guard await authenticateUser() else { return false }
        
        do {
            let encryptedPassword = try encryptPassword(password)
            let strength = analyzePasswordStrength(password)
            
            let savedPassword = SavedPassword(
                website: website,
                username: username,
                encryptedPassword: encryptedPassword,
                dateCreated: Date(),
                lastUsed: Date(),
                lastModified: Date(),
                strength: strength,
                notes: notes
            )
            
            // Save to Keychain
            let account = "\(website):\(username)"
            let passwordData = try JSONEncoder().encode(savedPassword)
            
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceName,
                kSecAttrAccount as String: account,
                kSecValueData as String: passwordData,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
            
            // Delete existing entry
            SecItemDelete(query as CFDictionary)
            
            // Add new entry
            let status = SecItemAdd(query as CFDictionary, nil)
            
            if status == errSecSuccess {
                await MainActor.run {
                    // Remove existing password for same website/username
                    savedPasswords.removeAll { $0.website == website && $0.username == username }
                    savedPasswords.append(savedPassword)
                    savedPasswords.sort { $0.lastUsed > $1.lastUsed }
                }
                return true
            }
        } catch {
            print("Failed to save password: \(error)")
        }
        
        return false
    }
    
    func loadPassword(for website: String, username: String) async -> String? {
        guard await authenticateUser() else { return nil }
        
        let account = "\(website):\(username)"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess,
           let data = result as? Data,
           let savedPassword = try? JSONDecoder().decode(SavedPassword.self, from: data) {
            
            do {
                let decryptedPassword = try decryptPassword(savedPassword.encryptedPassword)
                
                // Update last used date
                await updateLastUsed(for: savedPassword)
                
                return decryptedPassword
            } catch {
                print("Failed to decrypt password: \(error)")
            }
        }
        
        return nil
    }
    
    func deletePassword(for website: String, username: String) async -> Bool {
        guard await authenticateUser() else { return false }
        
        let account = "\(website):\(username)"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status == errSecSuccess {
            await MainActor.run {
                savedPasswords.removeAll { $0.website == website && $0.username == username }
            }
            return true
        }
        
        return false
    }
    
    // MARK: - Password Generation
    func generateSecurePassword(settings: PasswordGeneratorSettings? = nil) -> String {
        let config = settings ?? passwordGeneratorSettings
        
        var characters = ""
        
        if config.includeLowercase {
            characters += config.excludeSimilar ? "abcdefghijkmnopqrstuvwxyz" : "abcdefghijklmnopqrstuvwxyz"
        }
        
        if config.includeUppercase {
            characters += config.excludeSimilar ? "ABCDEFGHJKLMNPQRSTUVWXYZ" : "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        }
        
        if config.includeNumbers {
            characters += config.excludeSimilar ? "23456789" : "0123456789"
        }
        
        if config.includeSymbols {
            let symbols = config.excludeAmbiguous ? "!@#$%^&*-_=+[]{}|;:,.<>?" : "!@#$%^&*()-_=+[]{}\\|;:'\",.<>?/~`"
            characters += symbols
        }
        
        guard !characters.isEmpty else { return "" }
        
        var password = ""
        let charactersArray = Array(characters)
        
        // Ensure at least one character from each selected category
        if config.includeLowercase {
            let lowercase = config.excludeSimilar ? "abcdefghijkmnopqrstuvwxyz" : "abcdefghijklmnopqrstuvwxyz"
            password += String(lowercase.randomElement()!)
        }
        
        if config.includeUppercase {
            let uppercase = config.excludeSimilar ? "ABCDEFGHJKLMNPQRSTUVWXYZ" : "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
            password += String(uppercase.randomElement()!)
        }
        
        if config.includeNumbers {
            let numbers = config.excludeSimilar ? "23456789" : "0123456789"
            password += String(numbers.randomElement()!)
        }
        
        if config.includeSymbols {
            let symbols = config.excludeAmbiguous ? "!@#$%^&*-_=+[]{}|;:,.<>?" : "!@#$%^&*()-_=+[]{}\\|;:'\",.<>?/~`"
            password += String(symbols.randomElement()!)
        }
        
        // Fill remaining length with random characters
        for _ in password.count..<config.length {
            password += String(charactersArray.randomElement()!)
        }
        
        // Shuffle the password to avoid predictable patterns
        return String(password.shuffled())
    }
    
    func analyzePasswordStrength(_ password: String) -> SavedPassword.PasswordStrength {
        var score = 0
        
        // Length score
        if password.count >= 8 { score += 1 }
        if password.count >= 12 { score += 1 }
        if password.count >= 16 { score += 1 }
        
        // Character variety
        if password.contains(where: { $0.isLowercase }) { score += 1 }
        if password.contains(where: { $0.isUppercase }) { score += 1 }
        if password.contains(where: { $0.isNumber }) { score += 1 }
        if password.contains(where: { "!@#$%^&*()-_=+[]{}\\|;:'\",.<>?/~`".contains($0) }) { score += 1 }
        
        // Complexity bonuses
        if password.count >= 20 { score += 1 }
        if !hasCommonPatterns(password) { score += 1 }
        
        switch score {
        case 0...2: return .weak
        case 3...4: return .medium
        case 5...6: return .strong
        default: return .veryStrong
        }
    }
    
    private func hasCommonPatterns(_ password: String) -> Bool {
        let commonPatterns = [
            "123456", "password", "qwerty", "abc123", "letmein",
            "admin", "welcome", "monkey", "dragon", "master"
        ]
        
        let lowercasePassword = password.lowercased()
        return commonPatterns.contains { lowercasePassword.contains($0) }
    }
    
    // MARK: - Autofill Support
    func configureAutofill(for webView: WKWebView) {
        guard isAutofillEnabled else { return }
        
        let autofillScript = generateAutofillScript()
        let script = WKUserScript(source: autofillScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        webView.configuration.userContentController.addUserScript(script)
        webView.configuration.userContentController.add(self, name: "autofillHandler")
    }
    
    private func generateAutofillScript() -> String {
        return """
        (function() {
            'use strict';
            
            let formObserver;
            let lastFormCheck = 0;
            const FORM_CHECK_INTERVAL = 1000;
            
            function findLoginForms() {
                const forms = document.querySelectorAll('form');
                const loginForms = [];
                
                forms.forEach(form => {
                    const emailInput = form.querySelector('input[type="email"], input[name*="email"], input[name*="username"], input[autocomplete*="username"]');
                    const passwordInput = form.querySelector('input[type="password"]');
                    
                    if (emailInput && passwordInput) {
                        loginForms.push({
                            form: form,
                            emailInput: emailInput,
                            passwordInput: passwordInput,
                            website: window.location.hostname
                        });
                    }
                });
                
                return loginForms;
            }
            
            function addAutofillButtons(loginForm) {
                if (loginForm.emailInput.hasAttribute('data-autofill-added')) return;
                
                loginForm.emailInput.setAttribute('data-autofill-added', 'true');
                
                // Create autofill button
                const button = document.createElement('button');
                button.type = 'button';
                button.innerHTML = '🔑';
                button.style.cssText = `
                    position: absolute;
                    right: 8px;
                    top: 50%;
                    transform: translateY(-50%);
                    background: none;
                    border: none;
                    font-size: 16px;
                    cursor: pointer;
                    z-index: 1000;
                    opacity: 0.7;
                    transition: opacity 0.2s;
                `;
                
                button.addEventListener('mouseenter', () => button.style.opacity = '1');
                button.addEventListener('mouseleave', () => button.style.opacity = '0.7');
                
                button.addEventListener('click', (e) => {
                    e.preventDefault();
                    window.webkit.messageHandlers.autofillHandler.postMessage({
                        type: 'requestCredentials',
                        website: loginForm.website,
                        username: loginForm.emailInput.value
                    });
                });
                
                // Position the input relatively
                const inputStyle = window.getComputedStyle(loginForm.emailInput);
                if (inputStyle.position === 'static') {
                    loginForm.emailInput.style.position = 'relative';
                }
                
                // Add button to input container
                const container = loginForm.emailInput.parentElement;
                container.style.position = 'relative';
                container.appendChild(button);
            }
            
            function handleFormSubmission() {
                const loginForms = findLoginForms();
                
                loginForms.forEach(loginForm => {
                    loginForm.form.addEventListener('submit', () => {
                        const username = loginForm.emailInput.value;
                        const password = loginForm.passwordInput.value;
                        
                        if (username && password) {
                            window.webkit.messageHandlers.autofillHandler.postMessage({
                                type: 'saveCredentials',
                                website: loginForm.website,
                                username: username,
                                password: password
                            });
                        }
                    });
                });
            }
            
            function checkForForms() {
                const now = Date.now();
                if (now - lastFormCheck < FORM_CHECK_INTERVAL) return;
                lastFormCheck = now;
                
                const loginForms = findLoginForms();
                
                loginForms.forEach(loginForm => {
                    addAutofillButtons(loginForm);
                });
                
                if (loginForms.length > 0) {
                    handleFormSubmission();
                }
            }
            
            // Initial check
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', checkForForms);
            } else {
                checkForForms();
            }
            
            // Periodic checks for dynamic content
            setInterval(checkForForms, FORM_CHECK_INTERVAL);
            
            // Watch for dynamic form additions
            formObserver = new MutationObserver(function(mutations) {
                let shouldCheck = false;
                mutations.forEach(function(mutation) {
                    mutation.addedNodes.forEach(function(node) {
                        if (node.nodeType === Node.ELEMENT_NODE) {
                            if (node.tagName === 'FORM' || node.querySelector('form')) {
                                shouldCheck = true;
                            }
                        }
                    });
                });
                
                if (shouldCheck) {
                    setTimeout(checkForForms, 100);
                }
            });
            
            formObserver.observe(document.body, { childList: true, subtree: true });
            
        })();
        """
    }
    
    // MARK: - Authentication
    private func authenticateUser() async -> Bool {
        guard requireBiometricAuth else { return true }
        
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.biometryAny, localizedReason: "Authenticate to access saved passwords") { success, error in
                continuation.resume(returning: success)
            }
        }
    }
    
    // MARK: - Encryption/Decryption
    private func encryptPassword(_ password: String) throws -> Data {
        let passwordData = Data(password.utf8)
        let sealedBox = try AES.GCM.seal(passwordData, using: encryptionKey)
        return sealedBox.combined!
    }
    
    private func decryptPassword(_ encryptedData: Data) throws -> String {
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let decryptedData = try AES.GCM.open(sealedBox, using: encryptionKey)
        return String(data: decryptedData, encoding: .utf8) ?? ""
    }
    
    // MARK: - Data Management
    private func loadSavedPasswords() {
        // Load metadata from UserDefaults (actual passwords stay in Keychain)
        if let data = UserDefaults.standard.data(forKey: "passwordMetadata"),
           let metadata = try? JSONDecoder().decode([SavedPassword].self, from: data) {
            savedPasswords = metadata.sorted { $0.lastUsed > $1.lastUsed }
        }
    }
    
    private func savePasswordMetadata() {
        if let data = try? JSONEncoder().encode(savedPasswords) {
            UserDefaults.standard.set(data, forKey: "passwordMetadata")
        }
    }
    
    private func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: "passwordManagerSettings"),
           let settings = try? JSONDecoder().decode(PasswordManagerSettings.self, from: data) {
            isAutofillEnabled = settings.isAutofillEnabled
            requireBiometricAuth = settings.requireBiometricAuth
            passwordGeneratorSettings = settings.generatorSettings
        }
    }
    
    private func saveSettings() {
        let settings = PasswordManagerSettings(
            isAutofillEnabled: isAutofillEnabled,
            requireBiometricAuth: requireBiometricAuth,
            generatorSettings: passwordGeneratorSettings
        )
        
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: "passwordManagerSettings")
        }
    }
    
    private func updateLastUsed(for password: SavedPassword) async {
        await MainActor.run {
            if let index = savedPasswords.firstIndex(where: { $0.id == password.id }) {
                savedPasswords[index] = SavedPassword(
                    website: password.website,
                    username: password.username,
                    encryptedPassword: password.encryptedPassword,
                    dateCreated: password.dateCreated,
                    lastUsed: Date(),
                    lastModified: password.lastModified,
                    strength: password.strength,
                    notes: password.notes
                )
                
                // Re-sort by last used
                savedPasswords.sort { $0.lastUsed > $1.lastUsed }
                savePasswordMetadata()
            }
        }
    }
    
    struct PasswordManagerSettings: Codable {
        let isAutofillEnabled: Bool
        let requireBiometricAuth: Bool
        let generatorSettings: PasswordGeneratorSettings
    }
}

// MARK: - Script Message Handler
extension PasswordManager: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "autofillHandler",
              let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }
        
        switch type {
        case "requestCredentials":
            if let website = body["website"] as? String {
                showAutofillSuggestions(for: website, in: message.webView)
            }
            
        case "saveCredentials":
            if let website = body["website"] as? String,
               let username = body["username"] as? String,
               let password = body["password"] as? String {
                
                Task {
                    await savePassword(website: website, username: username, password: password)
                }
            }
            
        default:
            break
        }
    }
    
    private func showAutofillSuggestions(for website: String, in webView: WKWebView?) {
        let matchingPasswords = savedPasswords.filter { 
            $0.website.contains(website) || website.contains($0.website)
        }
        
        if !matchingPasswords.isEmpty {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .showAutofillSuggestions,
                    object: AutofillSuggestion(passwords: matchingPasswords, webView: webView)
                )
            }
        }
    }
    
    struct AutofillSuggestion {
        let passwords: [SavedPassword]
        let webView: WKWebView?
    }
}

// MARK: - Notification Extensions
extension Notification.Name {
    static let showAutofillSuggestions = Notification.Name("showAutofillSuggestions")
}
```

## 3. Incognito Mode Implementation

### Private Browsing with Enhanced Privacy
```swift
// IncognitoMode.swift - Enhanced private browsing implementation
import WebKit
import Network

class IncognitoSession: ObservableObject {
    @Published var isActive: Bool = false
    @Published var incognitoTabs: [Tab] = []
    
    private var incognitoWebViewConfiguration: WKWebViewConfiguration?
    private var privateDataStore: WKWebsiteDataStore?
    
    init() {
        setupIncognitoConfiguration()
    }
    
    private func setupIncognitoConfiguration() {
        // Create non-persistent data store
        privateDataStore = WKWebsiteDataStore.nonPersistent()
        
        // Configure incognito WebView
        let config = WKWebViewConfiguration()
        config.websiteDataStore = privateDataStore!
        
        // Disable various tracking and storage mechanisms
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.allowsAirPlayForMediaPlayback = false
        
        // Enhanced privacy settings
        if #available(macOS 14.0, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
            config.defaultWebpagePreferences.preferredContentMode = .desktop
        }
        
        incognitoWebViewConfiguration = config
    }
    
    func createIncognitoTab(url: URL? = nil) -> Tab {
        let tab = Tab(url: url, isIncognito: true)
        incognitoTabs.append(tab)
        
        if !isActive {
            isActive = true
        }
        
        return tab
    }
    
    func closeIncognitoTab(_ tab: Tab) {
        incognitoTabs.removeAll { $0.id == tab.id }
        
        if incognitoTabs.isEmpty {
            endIncognitoSession()
        }
    }
    
    func endIncognitoSession() {
        // Clear all incognito tabs
        incognitoTabs.removeAll()
        
        // Clear private data store
        if let dataStore = privateDataStore {
            let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
            dataStore.removeData(ofTypes: dataTypes, modifiedSince: Date.distantPast) { }
        }
        
        isActive = false
        
        // Recreate configuration for next session
        setupIncognitoConfiguration()
        
        print("Incognito session ended - all private data cleared")
    }
    
    func getIncognitoConfiguration() -> WKWebViewConfiguration? {
        return incognitoWebViewConfiguration
    }
}
```

## Implementation Notes

### Security Features
- **AES-256 encryption**: All passwords encrypted with device-specific keys
- **Biometric authentication**: Touch ID/Face ID protection for password access
- **Keychain integration**: Secure storage using iOS/macOS Keychain
- **Content blocking**: Native WebKit content blocking with custom rules
- **Incognito mode**: Complete data isolation with non-persistent storage

### Privacy Protections
- **Enhanced tracking prevention**: Advanced JavaScript-based blocking
- **Secure password generation**: Cryptographically secure random passwords
- **Private data clearing**: Automatic cleanup of incognito session data
- **Request interception**: Multiple layers of ad/tracker blocking

### Performance Optimizations
- **Efficient rule compilation**: Optimized content blocking rule processing
- **Lazy loading**: Password metadata loaded separately from encrypted data
- **Background processing**: Filter list updates performed off main thread

### Next Phase
Phase 5 will implement advanced interactions including floating micro-controls, live previews, and adaptive glass effects.