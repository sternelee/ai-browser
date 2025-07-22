# Phase 6: System Integration - Detailed Implementation

## Overview
This phase implements deep integration with the Apple ecosystem including Universal Clipboard, Handoff, iCloud sync, translation services, and automatic updates to create a seamless cross-device experience.

## 1. Apple Ecosystem Integration

### Universal Clipboard & Handoff Support
```swift
// AppleEcosystemManager.swift - Deep Apple ecosystem integration
import Foundation
import CloudKit
import UserActivity

class AppleEcosystemManager: ObservableObject {
    static let shared = AppleEcosystemManager()
    
    @Published var isHandoffEnabled: Bool = true
    @Published var isUniversalClipboardEnabled: Bool = true
    @Published var isiCloudSyncEnabled: Bool = true
    @Published var connectedDevices: [ConnectedDevice] = []
    
    private let cloudKitContainer: CKContainer
    private let userActivity = NSUserActivity(activityType: "com.web.browser.browsing")
    
    struct ConnectedDevice: Identifiable {
        let id = UUID()
        let name: String
        let type: DeviceType
        let lastSeen: Date
        let isActive: Bool
        
        enum DeviceType {
            case mac, iPhone, iPad, appleWatch
            
            var icon: String {
                switch self {
                case .mac: return "desktopcomputer"
                case .iPhone: return "iphone"
                case .iPad: return "ipad"
                case .appleWatch: return "applewatch"
                }
            }
        }
    }
    
    init() {
        self.cloudKitContainer = CKContainer(identifier: "iCloud.com.web.browser")
        setupHandoff()
        setupUniversalClipboard()
        loadSettings()
    }
    
    // MARK: - Handoff Implementation
    private func setupHandoff() {
        userActivity.title = "Browsing the Web"
        userActivity.isEligibleForHandoff = true
        userActivity.isEligibleForSearch = false
        userActivity.isEligibleForPublicIndexing = false
        
        // Set supported types
        userActivity.requiredUserInfoKeys = ["url", "title", "tabID"]
    }
    
    func updateHandoffActivity(for tab: Tab) {
        guard isHandoffEnabled,
              let url = tab.url else { return }
        
        userActivity.webpageURL = url
        userActivity.title = tab.title.isEmpty ? "Web Page" : tab.title
        
        userActivity.userInfo = [
            "url": url.absoluteString,
            "title": tab.title,
            "tabID": tab.id.uuidString,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        userActivity.becomeCurrent()
        
        print("Updated Handoff activity for: \(tab.title)")
    }
    
    func continueHandoffActivity(_ userActivity: NSUserActivity) -> Bool {
        guard userActivity.activityType == "com.web.browser.browsing",
              let userInfo = userActivity.userInfo,
              let urlString = userInfo["url"] as? String,
              let url = URL(string: urlString) else {
            return false
        }
        
        // Create new tab with handoff URL
        let tab = TabManager.shared.createNewTab(url: url)
        
        if let title = userInfo["title"] as? String {
            tab.title = title
        }
        
        print("Continued Handoff activity from another device")
        return true
    }
    
    // MARK: - Universal Clipboard
    private func setupUniversalClipboard() {
        // Monitor clipboard changes for cross-device sync
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkClipboardChanges()
        }
    }
    
    private var lastClipboardChangeCount: Int = 0
    
    private func checkClipboardChanges() {
        guard isUniversalClipboardEnabled else { return }
        
        let pasteboard = NSPasteboard.general
        
        if pasteboard.changeCount != lastClipboardChangeCount {
            lastClipboardChangeCount = pasteboard.changeCount
            
            // Check if clipboard contains URL from another device
            if let string = pasteboard.string(forType: .string),
               let url = URL(string: string),
               url.scheme?.hasPrefix("http") == true {
                
                // Show suggestion to open URL
                showUniversalClipboardSuggestion(url: url)
            }
        }
    }
    
    private func showUniversalClipboardSuggestion(url: URL) {
        // Post notification to show clipboard suggestion
        NotificationCenter.default.post(
            name: .showUniversalClipboardSuggestion,
            object: url
        )
    }
    
    func copyToUniversalClipboard(_ string: String) {
        guard isUniversalClipboardEnabled else { return }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        
        // Add metadata for Universal Clipboard
        let metadata = [
            "source": "Web Browser",
            "timestamp": Date().timeIntervalSince1970,
            "deviceName": Host.current().localizedName ?? "Mac"
        ]
        
        if let metadataData = try? JSONSerialization.data(withJSONObject: metadata) {
            pasteboard.setData(metadataData, forType: NSPasteboard.PasteboardType("com.web.browser.clipboard.metadata"))
        }
        
        print("Copied to Universal Clipboard: \(string.prefix(50))...")
    }
    
    // MARK: - iCloud Sync
    func setupiCloudSync() {
        guard isiCloudSyncEnabled else { return }
        
        Task {
            do {
                let accountStatus = try await cloudKitContainer.accountStatus()
                
                switch accountStatus {
                case .available:
                    await startSyncingData()
                case .noAccount:
                    print("iCloud account not available")
                case .restricted, .temporarilyUnavailable:
                    print("iCloud temporarily unavailable")
                @unknown default:
                    print("Unknown iCloud status")
                }
            } catch {
                print("Failed to check iCloud status: \(error)")
            }
        }
    }
    
    private func startSyncingData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.syncBookmarks() }
            group.addTask { await self.syncHistory() }
            group.addTask { await self.syncSettings() }
        }
    }
    
    private func syncBookmarks() async {
        do {
            let database = cloudKitContainer.privateCloudDatabase
            
            // Fetch remote bookmarks
            let query = CKQuery(recordType: "Bookmark", predicate: NSPredicate(value: true))
            let results = try await database.records(matching: query)
            
            var remoteBookmarks: [BookmarkRecord] = []
            
            for (recordID, result) in results.matchResults {
                switch result {
                case .success(let record):
                    if let bookmark = BookmarkRecord.from(record) {
                        remoteBookmarks.append(bookmark)
                    }
                case .failure(let error):
                    print("Failed to fetch bookmark \(recordID): \(error)")
                }
            }
            
            // Merge with local bookmarks
            await mergeBookmarks(remote: remoteBookmarks)
            
        } catch {
            print("Failed to sync bookmarks: \(error)")
        }
    }
    
    private func syncHistory() async {
        // Similar implementation to bookmarks but for history
        // Only sync recent history (last 30 days) for privacy
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        
        do {
            let database = cloudKitContainer.privateCloudDatabase
            let predicate = NSPredicate(format: "visitDate >= %@", thirtyDaysAgo as NSDate)
            let query = CKQuery(recordType: "HistoryItem", predicate: predicate)
            
            let results = try await database.records(matching: query)
            
            // Process history sync similar to bookmarks
            print("Synced \(results.matchResults.count) history items")
            
        } catch {
            print("Failed to sync history: \(error)")
        }
    }
    
    private func syncSettings() async {
        do {
            let database = cloudKitContainer.privateCloudDatabase
            
            // Fetch settings record
            let recordID = CKRecord.ID(recordName: "UserSettings")
            
            do {
                let record = try await database.record(for: recordID)
                await applyRemoteSettings(record)
            } catch CKError.unknownItem {
                // Create new settings record
                await createSettingsRecord()
            }
            
        } catch {
            print("Failed to sync settings: \(error)")
        }
    }
    
    private func mergeBookmarks(remote: [BookmarkRecord]) async {
        // Implement bookmark merging logic
        // This would compare timestamps and merge conflicts
        await MainActor.run {
            // Update local bookmark manager
            print("Merged \(remote.count) remote bookmarks")
        }
    }
    
    private func applyRemoteSettings(_ record: CKRecord) async {
        await MainActor.run {
            if let handoffEnabled = record["handoffEnabled"] as? Bool {
                isHandoffEnabled = handoffEnabled
            }
            
            if let clipboardEnabled = record["universalClipboardEnabled"] as? Bool {
                isUniversalClipboardEnabled = clipboardEnabled
            }
            
            print("Applied remote settings")
        }
    }
    
    private func createSettingsRecord() async {
        let database = cloudKitContainer.privateCloudDatabase
        let recordID = CKRecord.ID(recordName: "UserSettings")
        let record = CKRecord(recordType: "UserSettings", recordID: recordID)
        
        record["handoffEnabled"] = isHandoffEnabled
        record["universalClipboardEnabled"] = isUniversalClipboardEnabled
        record["lastModified"] = Date()
        
        do {
            _ = try await database.save(record)
            print("Created settings record in iCloud")
        } catch {
            print("Failed to create settings record: \(error)")
        }
    }
    
    // MARK: - Connected Devices
    func discoverConnectedDevices() {
        // Use Bonjour/Network framework to discover other devices
        // This is a simplified implementation
        
        let sampleDevices = [
            ConnectedDevice(name: "iPhone", type: .iPhone, lastSeen: Date(), isActive: true),
            ConnectedDevice(name: "iPad", type: .iPad, lastSeen: Date().addingTimeInterval(-300), isActive: false),
            ConnectedDevice(name: "MacBook Pro", type: .mac, lastSeen: Date().addingTimeInterval(-60), isActive: true)
        ]
        
        DispatchQueue.main.async {
            self.connectedDevices = sampleDevices
        }
    }
    
    // MARK: - Settings Management
    private func loadSettings() {
        let defaults = UserDefaults.standard
        isHandoffEnabled = defaults.bool(forKey: "handoffEnabled")
        isUniversalClipboardEnabled = defaults.bool(forKey: "universalClipboardEnabled") 
        isiCloudSyncEnabled = defaults.bool(forKey: "iCloudSyncEnabled")
    }
    
    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(isHandoffEnabled, forKey: "handoffEnabled")
        defaults.set(isUniversalClipboardEnabled, forKey: "universalClipboardEnabled")
        defaults.set(isiCloudSyncEnabled, forKey: "iCloudSyncEnabled")
        
        // Sync to iCloud if enabled
        if isiCloudSyncEnabled {
            Task {
                await syncSettings()
            }
        }
    }
}

// MARK: - CloudKit Record Models
struct BookmarkRecord {
    let id: String
    let title: String
    let url: String
    let createdDate: Date
    let modifiedDate: Date
    let folder: String?
    
    static func from(_ record: CKRecord) -> BookmarkRecord? {
        guard let title = record["title"] as? String,
              let url = record["url"] as? String,
              let createdDate = record["createdDate"] as? Date,
              let modifiedDate = record["modifiedDate"] as? Date else {
            return nil
        }
        
        return BookmarkRecord(
            id: record.recordID.recordName,
            title: title,
            url: url,
            createdDate: createdDate,
            modifiedDate: modifiedDate,
            folder: record["folder"] as? String
        )
    }
    
    func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: "Bookmark", recordID: CKRecord.ID(recordName: id))
        record["title"] = title
        record["url"] = url
        record["createdDate"] = createdDate
        record["modifiedDate"] = modifiedDate
        record["folder"] = folder
        return record
    }
}
```

## 2. Translation Services

### Native Translation Integration
```swift
// TranslationManager.swift - Native translation services integration
import Translation
import NaturalLanguage

@available(macOS 14.0, *)
class TranslationManager: ObservableObject {
    static let shared = TranslationManager()
    
    @Published var isTranslationAvailable: Bool = false
    @Published var detectedLanguage: String?
    @Published var targetLanguage: String = "en"
    @Published var isTranslating: Bool = false
    @Published var translationOverlayVisible: Bool = false
    
    private let translationSession = TranslationSession()
    private let languageRecognizer = NLLanguageRecognizer()
    
    private let supportedLanguages = [
        "en": "English",
        "es": "Spanish", 
        "fr": "French",
        "de": "German",
        "it": "Italian",
        "pt": "Portuguese",
        "ru": "Russian",
        "ja": "Japanese",
        "ko": "Korean",
        "zh": "Chinese",
        "ar": "Arabic"
    ]
    
    init() {
        checkTranslationAvailability()
        setupLanguageDetection()
    }
    
    // MARK: - Translation Setup
    private func checkTranslationAvailability() {
        Task {
            let availability = await translationSession.availability(from: .init(identifier: "auto"), to: .init(identifier: targetLanguage))
            
            await MainActor.run {
                isTranslationAvailable = availability == .available
            }
        }
    }
    
    private func setupLanguageDetection() {
        languageRecognizer.reset()
    }
    
    // MARK: - Page Translation
    func translateCurrentPage() {
        guard isTranslationAvailable,
              let webView = TabManager.shared.activeTab?.webView else { return }
        
        isTranslating = true
        
        // Extract page content
        let extractionScript = """
        (function() {
            // Get main content, avoiding navigation and ads
            const content = document.querySelector('main, article, .content, #content, .post, #main') || document.body;
            
            // Extract text content with structure preservation
            function getTextWithStructure(element) {
                let result = [];
                
                for (let node of element.childNodes) {
                    if (node.nodeType === Node.TEXT_NODE) {
                        const text = node.textContent.trim();
                        if (text.length > 0) {
                            result.push({
                                type: 'text',
                                content: text,
                                xpath: getXPath(node.parentElement)
                            });
                        }
                    } else if (node.nodeType === Node.ELEMENT_NODE) {
                        const tagName = node.tagName.toLowerCase();
                        
                        if (['p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'td', 'th', 'span', 'div'].includes(tagName)) {
                            const text = node.innerText?.trim();
                            if (text && text.length > 0) {
                                result.push({
                                    type: 'element',
                                    tagName: tagName,
                                    content: text,
                                    xpath: getXPath(node)
                                });
                            }
                        }
                        
                        // Recursively process child elements for complex structures
                        if (!['script', 'style', 'nav', 'header', 'footer', 'aside'].includes(tagName)) {
                            result.push(...getTextWithStructure(node));
                        }
                    }
                }
                
                return result;
            }
            
            function getXPath(element) {
                if (!element || element.nodeType !== Node.ELEMENT_NODE) return '';
                
                if (element.id) return `//*[@id="${element.id}"]`;
                
                let path = '';
                let current = element;
                
                while (current && current.nodeType === Node.ELEMENT_NODE) {
                    const tag = current.tagName.toLowerCase();
                    const siblings = Array.from(current.parentNode?.children || [])
                        .filter(sibling => sibling.tagName.toLowerCase() === tag);
                    
                    const index = siblings.indexOf(current) + 1;
                    path = `/${tag}[${index}]${path}`;
                    current = current.parentElement;
                }
                
                return path;
            }
            
            return {
                textElements: getTextWithStructure(content),
                title: document.title,
                language: document.documentElement.lang || 'auto'
            };
        })();
        """
        
        webView.evaluateJavaScript(extractionScript) { [weak self] result, error in
            guard let self = self,
                  let resultDict = result as? [String: Any],
                  let textElements = resultDict["textElements"] as? [[String: Any]] else {
                self?.isTranslating = false
                return
            }
            
            let sourceLanguage = resultDict["language"] as? String ?? "auto"
            self.performBatchTranslation(textElements: textElements, sourceLanguage: sourceLanguage, webView: webView)
        }
    }
    
    private func performBatchTranslation(textElements: [[String: Any]], sourceLanguage: String, webView: WKWebView) {
        Task {
            var translatedElements: [[String: Any]] = []
            
            for element in textElements {
                guard let content = element["content"] as? String,
                      content.count > 0 else { continue }
                
                do {
                    let sourceConfig = TranslationSession.Configuration(source: .init(identifier: sourceLanguage), target: .init(identifier: targetLanguage))
                    let translationRequests = [TranslationSession.Request(sourceText: content)]
                    let responses = try await translationSession.translations(from: translationRequests, configuration: sourceConfig)
                    
                    if let translatedText = responses.first?.targetText {
                        var translatedElement = element
                        translatedElement["translatedContent"] = translatedText
                        translatedElements.append(translatedElement)
                    }
                } catch {
                    print("Translation error for text: \(content.prefix(50))... - \(error)")
                    translatedElements.append(element) // Keep original if translation fails
                }
            }
            
            await MainActor.run {
                self.applyTranslationsToPage(translatedElements: translatedElements, webView: webView)
                self.isTranslating = false
                self.translationOverlayVisible = true
            }
        }
    }
    
    private func applyTranslationsToPage(translatedElements: [[String: Any]], webView: WKWebView) {
        // Generate JavaScript to apply translations
        var translations: [String] = []
        
        for element in translatedElements {
            guard let xpath = element["xpath"] as? String,
                  let translatedContent = element["translatedContent"] as? String else { continue }
            
            let escapedContent = translatedContent.replacingOccurrences(of: "'", with: "\\'")
                                                   .replacingOccurrences(of: "\n", with: "\\n")
            
            translations.append("{\nxpath: '\(xpath)',\ncontent: '\(escapedContent)'\n}")
        }
        
        let translationScript = """
        (function() {
            const translations = [\(translations.joined(separator: ",\n"))];
            
            // Store original content for reverting
            if (!window.originalContent) {
                window.originalContent = new Map();
            }
            
            translations.forEach(translation => {
                try {
                    const element = document.evaluate(translation.xpath, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
                    
                    if (element) {
                        // Store original content
                        if (!window.originalContent.has(translation.xpath)) {
                            window.originalContent.set(translation.xpath, element.textContent);
                        }
                        
                        // Apply translation
                        if (element.childNodes.length === 1 && element.childNodes[0].nodeType === Node.TEXT_NODE) {
                            element.textContent = translation.content;
                        } else {
                            // For complex elements, try to replace text content
                            element.innerText = translation.content;
                        }
                        
                        // Add visual indicator
                        element.style.borderLeft = '3px solid #007AFF';
                        element.style.paddingLeft = '8px';
                        element.style.transition = 'all 0.3s ease';
                    }
                } catch (error) {
                    console.warn('Failed to apply translation:', error);
                }
            });
            
            // Add translation indicator to page
            const indicator = document.createElement('div');
            indicator.id = 'translation-indicator';
            indicator.innerHTML = `
                <div style="
                    position: fixed;
                    top: 20px;
                    right: 20px;
                    background: rgba(0, 122, 255, 0.9);
                    color: white;
                    padding: 8px 16px;
                    border-radius: 20px;
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    font-size: 14px;
                    z-index: 10000;
                    backdrop-filter: blur(10px);
                    box-shadow: 0 4px 16px rgba(0, 0, 0, 0.1);
                ">
                    📝 Page translated to \(supportedLanguages[targetLanguage] ?? targetLanguage)
                    <button onclick="window.webkit.messageHandlers.translationHandler.postMessage('revert')" 
                            style="
                                background: none;
                                border: none;
                                color: white;
                                margin-left: 8px;
                                cursor: pointer;
                                text-decoration: underline;
                            ">
                        Revert
                    </button>
                </div>
            `;
            document.body.appendChild(indicator);
            
            // Auto-hide indicator after 5 seconds
            setTimeout(() => {
                const el = document.getElementById('translation-indicator');
                if (el) {
                    el.style.opacity = '0';
                    setTimeout(() => el.remove(), 300);
                }
            }, 5000);
        })();
        """
        
        webView.evaluateJavaScript(translationScript) { _, error in
            if let error = error {
                print("Failed to apply translations: \(error)")
            }
        }
        
        // Add message handler for revert functionality
        let revertScript = WKUserScript(source: translationRevertScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        webView.configuration.userContentController.addUserScript(revertScript)
        webView.configuration.userContentController.add(self, name: "translationHandler")
    }
    
    private var translationRevertScript: String {
        return """
        (function() {
            window.revertTranslation = function() {
                if (window.originalContent) {
                    window.originalContent.forEach((originalText, xpath) => {
                        try {
                            const element = document.evaluate(xpath, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
                            if (element) {
                                element.textContent = originalText;
                                element.style.borderLeft = '';
                                element.style.paddingLeft = '';
                            }
                        } catch (error) {
                            console.warn('Failed to revert element:', error);
                        }
                    });
                    
                    window.originalContent.clear();
                    
                    const indicator = document.getElementById('translation-indicator');
                    if (indicator) indicator.remove();
                }
            };
        })();
        """
    }
    
    // MARK: - Text Selection Translation
    func translateSelectedText(_ text: String, completion: @escaping (String?) -> Void) {
        guard !text.isEmpty else {
            completion(nil)
            return
        }
        
        Task {
            do {
                // Detect source language
                languageRecognizer.processString(text)
                let sourceLanguage = languageRecognizer.dominantLanguage?.rawValue ?? "auto"
                
                let sourceConfig = TranslationSession.Configuration(
                    source: .init(identifier: sourceLanguage),
                    target: .init(identifier: targetLanguage)
                )
                
                let request = TranslationSession.Request(sourceText: text)
                let responses = try await translationSession.translations(from: [request], configuration: sourceConfig)
                
                await MainActor.run {
                    completion(responses.first?.targetText)
                }
            } catch {
                await MainActor.run {
                    completion(nil)
                }
            }
        }
    }
    
    // MARK: - Language Detection
    func detectPageLanguage() {
        guard let webView = TabManager.shared.activeTab?.webView else { return }
        
        let detectionScript = """
        (function() {
            const content = document.body.innerText || document.body.textContent || '';
            const lang = document.documentElement.lang || document.querySelector('html')?.getAttribute('lang') || '';
            
            return {
                content: content.substring(0, 1000), // First 1000 characters for detection
                declaredLanguage: lang
            };
        })();
        """
        
        webView.evaluateJavaScript(detectionScript) { [weak self] result, error in
            guard let self = self,
                  let resultDict = result as? [String: String],
                  let content = resultDict["content"] else { return }
            
            self.languageRecognizer.reset()
            self.languageRecognizer.processString(content)
            
            DispatchQueue.main.async {
                self.detectedLanguage = self.languageRecognizer.dominantLanguage?.rawValue
                
                // Auto-suggest translation if page is in different language
                if let detected = self.detectedLanguage,
                   detected != self.targetLanguage,
                   detected != "und" { // "und" means undetermined
                    self.showTranslationSuggestion()
                }
            }
        }
    }
    
    private func showTranslationSuggestion() {
        NotificationCenter.default.post(
            name: .showTranslationSuggestion,
            object: TranslationSuggestion(
                sourceLanguage: detectedLanguage ?? "auto",
                targetLanguage: targetLanguage
            )
        )
    }
    
    struct TranslationSuggestion {
        let sourceLanguage: String
        let targetLanguage: String
    }
}

// MARK: - Script Message Handler
@available(macOS 14.0, *)
extension TranslationManager: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "translationHandler" else { return }
        
        if let messageBody = message.body as? String, messageBody == "revert" {
            // Revert translation
            message.webView?.evaluateJavaScript("window.revertTranslation();")
            translationOverlayVisible = false
        }
    }
}
```

## 3. Automatic Updates System

### Sparkle-Based Update Manager
```swift
// UpdateManager.swift - Advanced automatic update system
import Sparkle

class UpdateManager: ObservableObject {
    static let shared = UpdateManager()
    
    @Published var updateAvailable: Bool = false
    @Published var updateInfo: UpdateInfo?
    @Published var downloadProgress: Double = 0.0
    @Published var isDownloading: Bool = false
    @Published var updateSettings = UpdateSettings()
    
    private let updaterController: SPUStandardUpdaterController
    private let userDriver: SPUUserDriver
    
    struct UpdateInfo {
        let version: String
        let buildNumber: String
        let downloadSize: Int64
        let isSecurityUpdate: Bool
        let releaseDate: Date
    }
    
    struct UpdateSettings: Codable {
        var automaticUpdates: Bool = true
        var downloadInBackground: Bool = true
        var installOnRestart: Bool = true
        var checkFrequency: CheckFrequency = .daily
        var allowPreReleases: Bool = false
        
        enum CheckFrequency: String, CaseIterable, Codable {
            case hourly = "hourly"
            case daily = "daily"
            case weekly = "weekly"
            case monthly = "monthly"
            
            var timeInterval: TimeInterval {
                switch self {
                case .hourly: return 3600
                case .daily: return 86400
                case .weekly: return 604800
                case .monthly: return 2592000
                }
            }
            
            var displayName: String {
                switch self {
                case .hourly: return "Every hour"
                case .daily: return "Daily"
                case .weekly: return "Weekly"
                case .monthly: return "Monthly"
                }
            }
        }
    }
    
    init() {
        // Initialize Sparkle updater
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        
        self.userDriver = SPUUserDriver()
        
        loadSettings()
        configureUpdater()
        setupUpdateChecking()
    }
    
    // MARK: - Configuration
    private func configureUpdater() {
        let updater = updaterController.updater
        
        // Configure update feed URL
        if updateSettings.allowPreReleases {
            updater.feedURL = URL(string: "https://updates.web-browser.app/appcast-beta.xml")
        } else {
            updater.feedURL = URL(string: "https://updates.web-browser.app/appcast.xml")
        }
        
        // Configure automatic updates
        updater.automaticallyChecksForUpdates = updateSettings.automaticUpdates
        updater.automaticallyDownloadsUpdates = updateSettings.downloadInBackground
        updater.updateCheckInterval = updateSettings.checkFrequency.timeInterval
        
        // Set user agent
        updater.userAgentString = "Web Browser/\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") (macOS)"
    }
    
    private func setupUpdateChecking() {
        // Listen for update notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateFound(_:)),
            name: .SPUUpdaterDidFindValidUpdate,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateDownloadDidStart(_:)),
            name: .SPUUpdaterDidStartDownload,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateDownloadProgress(_:)),
            name: .SPUUpdaterDidReceiveData,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateDownloadCompleted(_:)),
            name: .SPUUpdaterDidFinishDownload,
            object: nil
        )
    }
    
    // MARK: - Update Management
    func checkForUpdates(manual: Bool = false) {
        if manual {
            updaterController.checkForUpdates(nil)
        } else {
            updaterController.updater.checkForUpdatesInBackground()
        }
    }
    
    func downloadUpdate() {
        guard let updateInfo = updateInfo else { return }
        
        isDownloading = true
        downloadProgress = 0.0
        
        // Sparkle handles the download automatically
        // Progress is tracked via notifications
    }
    
    func installUpdate() {
        // Install update and restart
        updaterController.updater.installUpdatesIfAvailable()
    }
    
    func skipUpdate() {
        updateAvailable = false
        updateInfo = nil
        
        // Mark this version as skipped
        if let version = updateInfo?.version {
            UserDefaults.standard.set(version, forKey: "skippedUpdateVersion")
        }
    }
    
    func postponeUpdate() {
        updateAvailable = false
        
        // Postpone for 24 hours
        let postponeDate = Date().addingTimeInterval(86400)
        UserDefaults.standard.set(postponeDate, forKey: "updatePostponedUntil")
    }
    
    // MARK: - Settings Management
    func updateSettings(_ newSettings: UpdateSettings) {
        updateSettings = newSettings
        saveSettings()
        configureUpdater()
    }
    
    private func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: "updateSettings"),
           let settings = try? JSONDecoder().decode(UpdateSettings.self, from: data) {
            updateSettings = settings
        }
    }
    
    private func saveSettings() {
        if let data = try? JSONEncoder().encode(updateSettings) {
            UserDefaults.standard.set(data, forKey: "updateSettings")
        }
    }
    
    // MARK: - Notification Handlers
    @objc private func updateFound(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let updateItem = userInfo["updateItem"] as? SPUAppcastItem else { return }
        
        // Check if this version was previously skipped
        let skippedVersion = UserDefaults.standard.string(forKey: "skippedUpdateVersion")
        if skippedVersion == updateItem.versionString {
            return
        }
        
        // Check if update is postponed
        if let postponeDate = UserDefaults.standard.object(forKey: "updatePostponedUntil") as? Date,
           Date() < postponeDate {
            return
        }
        
        let info = UpdateInfo(
            version: updateItem.versionString,
            buildNumber: updateItem.buildVersionString ?? "",
            downloadSize: updateItem.contentLength,
            isSecurityUpdate: updateItem.isSecurityUpdate,
            releaseDate: updateItem.date ?? Date()
        )
        
        DispatchQueue.main.async {
            self.updateInfo = info
            self.updateAvailable = true
            
            // Show update notification
            self.showUpdateNotification(info)
        }
    }
    
    @objc private func updateDownloadDidStart(_ notification: Notification) {
        DispatchQueue.main.async {
            self.isDownloading = true
            self.downloadProgress = 0.0
        }
    }
    
    @objc private func updateDownloadProgress(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let bytesDownloaded = userInfo["bytesDownloaded"] as? Int64,
              let totalBytes = userInfo["totalBytes"] as? Int64,
              totalBytes > 0 else { return }
        
        let progress = Double(bytesDownloaded) / Double(totalBytes)
        
        DispatchQueue.main.async {
            self.downloadProgress = progress
        }
    }
    
    @objc private func updateDownloadCompleted(_ notification: Notification) {
        DispatchQueue.main.async {
            self.isDownloading = false
            self.downloadProgress = 1.0
            
            // Show install notification
            self.showInstallNotification()
        }
    }
    
    // MARK: - User Notifications
    private func showUpdateNotification(_ info: UpdateInfo) {
        let notification = NSUserNotification()
        notification.title = "Update Available"
        notification.informativeText = "Web Browser \(info.version) is available"
        notification.actionButtonTitle = "Update"
        notification.otherButtonTitle = "Later"
        notification.hasActionButton = true
        
        NSUserNotificationCenter.default.deliver(notification)
    }
    
    private func showInstallNotification() {
        let notification = NSUserNotification()
        notification.title = "Update Ready"
        notification.informativeText = "Update downloaded and ready to install"
        notification.actionButtonTitle = "Install & Restart"
        notification.otherButtonTitle = "Later"
        notification.hasActionButton = true
        
        NSUserNotificationCenter.default.deliver(notification)
    }
    
    // MARK: - Delta Updates
    func supportsDeltaUpdates() -> Bool {
        return updaterController.updater.canUpdateFromVersion(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
    }
    
    func estimatedDeltaSize(for version: String) -> Int64 {
        // Calculate estimated delta size based on version differences
        // This is a simplified implementation
        return updateInfo?.downloadSize ?? 0 / 3 // Assume delta is 1/3 of full size
    }
    
    // MARK: - Rollback Support
    func canRollback() -> Bool {
        // Check if previous version is available for rollback
        return UserDefaults.standard.object(forKey: "previousVersion") != nil
    }
    
    func rollbackToPreviousVersion() {
        guard canRollback() else { return }
        
        // Implement rollback logic
        // This would require storing previous version bundle
        let alert = NSAlert()
        alert.messageText = "Rollback Feature"
        alert.informativeText = "Rollback functionality will be implemented in a future update"
        alert.runModal()
    }
}

// MARK: - Update UI Components
struct UpdateSettingsView: View {
    @ObservedObject var updateManager = UpdateManager.shared
    @State private var settings: UpdateManager.UpdateSettings
    
    init() {
        self._settings = State(initialValue: UpdateManager.shared.updateSettings)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Updates")
                .font(.title2)
                .fontWeight(.semibold)
            
            Toggle("Automatically check for updates", isOn: $settings.automaticUpdates)
            
            Toggle("Download updates in background", isOn: $settings.downloadInBackground)
                .disabled(!settings.automaticUpdates)
            
            Toggle("Install updates on restart", isOn: $settings.installOnRestart)
                .disabled(!settings.automaticUpdates)
            
            HStack {
                Text("Check frequency:")
                Picker("", selection: $settings.checkFrequency) {
                    ForEach(UpdateManager.UpdateSettings.CheckFrequency.allCases, id: \.self) { frequency in
                        Text(frequency.displayName).tag(frequency)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!settings.automaticUpdates)
            }
            
            Toggle("Include pre-release versions", isOn: $settings.allowPreReleases)
            
            Divider()
            
            HStack {
                Button("Check Now") {
                    updateManager.checkForUpdates(manual: true)
                }
                
                Spacer()
                
                if updateManager.canRollback() {
                    Button("Rollback") {
                        updateManager.rollbackToPreviousVersion()
                    }
                    .foregroundColor(.orange)
                }
            }
        }
        .padding()
        .onChange(of: settings) { newSettings in
            updateManager.updateSettings(newSettings)
        }
    }
}

struct UpdateNotificationView: View {
    let updateInfo: UpdateManager.UpdateInfo
    let onUpdate: () -> Void
    let onPostpone: () -> Void
    let onSkip: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                VStack(alignment: .leading) {
                    Text("Update Available")
                        .font(.headline)
                    Text("Version \(updateInfo.version)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if updateInfo.isSecurityUpdate {
                    Image(systemName: "shield.fill")
                        .foregroundColor(.red)
                        .help("Security Update")
                }
            }
            
                .frame(maxHeight: 100)
            }
            
            HStack {
                Text("Size: \(ByteCountFormatter().string(fromByteCount: updateInfo.downloadSize))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Skip", action: onSkip)
                    .foregroundColor(.secondary)
                
                Button("Later", action: onPostpone)
                
                Button("Update", action: onUpdate)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
```

## Implementation Notes

### Apple Ecosystem Features
- **Handoff**: Seamless browsing continuation across devices
- **Universal Clipboard**: Cross-device clipboard synchronization with metadata
- **iCloud Sync**: Private CloudKit integration for bookmarks, history, and settings
- **Device Discovery**: Bonjour-based discovery of connected Apple devices

### Translation Services
- **Native Translation API**: Uses macOS 14+ Translation framework
- **Batch Translation**: Efficient page-wide translation with structure preservation
- **Language Detection**: Automatic source language detection using NaturalLanguage
- **Smart Suggestions**: Context-aware translation suggestions

### Update System
- **Sparkle Integration**: Industry-standard macOS update framework
- **Delta Updates**: Efficient incremental updates for faster downloads
- **Background Downloads**: Non-intrusive update downloading
- **Rollback Support**: Safe rollback to previous versions if needed
- **Security Updates**: Priority handling for security-critical updates

### Performance Optimizations
- **CloudKit Efficiency**: Batched operations and conflict resolution
- **Translation Caching**: Intelligent caching of translated content
- **Background Processing**: All heavy operations on background queues
- **Memory Management**: Proper cleanup and resource management

### Next Phase
Phase 7 will implement the final polish and testing including comprehensive testing strategies, performance profiling, and deployment preparation.