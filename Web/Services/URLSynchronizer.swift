import Foundation
import WebKit
import Combine
import AppKit
import SwiftUI

/// Centralized URL synchronization service - Single source of truth for URL state management
/// Prevents race conditions and ensures consistent URL display across all components
class URLSynchronizer: ObservableObject {
    static let shared = URLSynchronizer()
    
    // MARK: - Published State
    @Published private(set) var currentURL: String = ""
    @Published private(set) var displayURL: String = ""
    @Published private(set) var pageTitle: String = ""
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var estimatedProgress: Double = 0.0
    
    // MARK: - Private State Management
    private var activeTabID: UUID?
    private var urlUpdateQueue = DispatchQueue(label: "url-synchronizer", qos: .userInteractive)
    private var cancellables = Set<AnyCancellable>()
    
    // Track URL update sources to prevent feedback loops
    private enum URLUpdateSource {
        case webViewNavigation
        case userInput
        case tabSwitch
        case programmatic
    }
    
    private var lastUpdateSource: URLUpdateSource = .programmatic
    private var lastUpdateTime: Date = Date()
    
    private init() {
        setupNotificationObservers()
    }
    
    // MARK: - Public Interface
    
    /// Updates URL from WebView navigation (highest priority - immediate update)
    func updateFromWebViewNavigation(url: URL?, title: String?, isLoading: Bool, progress: Double, tabID: UUID) {
        urlUpdateQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Validate input parameters
            guard self.isValidTabID(tabID) else {
                print("⚠️ URLSynchronizer: Invalid tabID \(tabID) for WebView navigation")
                return
            }
            
            guard self.activeTabID == tabID else { return }
            
            DispatchQueue.main.async {
                self.performURLUpdate(
                    url: url,
                    title: title,
                    isLoading: isLoading,
                    progress: progress,
                    source: .webViewNavigation
                )
            }
        }
    }
    
    /// Updates URL from user input in URL bar
    func updateFromUserInput(urlString: String, tabID: UUID) {
        urlUpdateQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Validate input parameters
            guard self.isValidTabID(tabID) else {
                print("⚠️ URLSynchronizer: Invalid tabID \(tabID) for user input")
                return
            }
            
            guard !urlString.isEmpty else {
                print("⚠️ URLSynchronizer: Empty URL string from user input")
                return
            }
            
            guard self.activeTabID == tabID else { return }
            
            // Validate URL format
            let validatedURL = self.validateAndSanitizeURL(urlString)
            
            DispatchQueue.main.async {
                self.performURLUpdate(
                    url: validatedURL,
                    title: nil,
                    isLoading: false,
                    progress: 0.0,
                    source: .userInput
                )
            }
        }
    }
    
    /// Updates URL when switching tabs (immediate synchronization)
    func updateFromTabSwitch(tabID: UUID, url: URL?, title: String, isLoading: Bool, progress: Double, isHibernated: Bool) {
        urlUpdateQueue.async { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.activeTabID = tabID
                
                // Handle edge case of hibernated tabs
                if isHibernated {
                    // For hibernated tabs, show saved state without triggering navigation
                    self.performURLUpdate(
                        url: url,
                        title: title.isEmpty ? "Tab Hibernated" : title,
                        isLoading: false,
                        progress: 0.0,
                        source: .tabSwitch
                    )
                } else {
                    self.performURLUpdate(
                        url: url,
                        title: title,
                        isLoading: isLoading,
                        progress: progress,
                        source: .tabSwitch
                    )
                }
            }
        }
    }
    
    /// Programmatic URL update (e.g., from navigation controls)
    func updateProgrammatically(url: URL?, title: String?, tabID: UUID) {
        urlUpdateQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Validate input parameters
            guard self.isValidTabID(tabID) else {
                print("⚠️ URLSynchronizer: Invalid tabID \(tabID) for programmatic update")
                return
            }
            
            guard self.activeTabID == tabID else { return }
            
            DispatchQueue.main.async {
                self.performURLUpdate(
                    url: url,
                    title: title,
                    isLoading: false,
                    progress: 0.0,
                    source: .programmatic
                )
            }
        }
    }
    
    /// Get current URL for binding (read-only)
    func getCurrentURLBinding() -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.currentURL ?? ""
            },
            set: { _ in
                // Read-only binding - updates should go through proper channels
            }
        )
    }
    
    /// Get editable URL binding for input fields
    func getEditableURLBinding(for tabID: UUID) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.currentURL ?? ""
            },
            set: { [weak self] newValue in
                self?.updateFromUserInput(urlString: newValue, tabID: tabID)
            }
        )
    }
    
    // MARK: - Private Implementation
    
    private func performURLUpdate(url: URL?, title: String?, isLoading: Bool, progress: Double, source: URLUpdateSource) {
        // Prevent rapid duplicate updates from the same source
        let now = Date()
        let timeSinceLastUpdate = now.timeIntervalSince(lastUpdateTime)
        
        if source == lastUpdateSource && timeSinceLastUpdate < 0.05 {
            return // Debounce rapid updates
        }
        
        lastUpdateSource = source
        lastUpdateTime = now
        
        // Safely update URL state with error handling
        let urlString = url?.absoluteString ?? ""
        let safeTitle = title ?? ""
        let safeProgress = max(0.0, min(1.0, progress.isFinite ? progress : 0.0))
        
        // Validate URL string format
        if !urlString.isEmpty && url == nil {
            print("⚠️ URLSynchronizer: URL string '\(urlString)' could not be converted to URL")
        }
        
        // Update published properties
        self.currentURL = urlString
        self.displayURL = generateDisplayURL(from: urlString, title: safeTitle, source: source)
        self.pageTitle = safeTitle
        self.isLoading = isLoading
        self.estimatedProgress = safeProgress
        
        // Notify components of URL change
        NotificationCenter.default.post(
            name: .urlSynchronizerDidUpdateURL,
            object: nil,
            userInfo: [
                "url": urlString,
                "displayURL": self.displayURL,
                "title": self.pageTitle,
                "source": source,
                "timestamp": now
            ]
        )
    }
    
    private func generateDisplayURL(from urlString: String, title: String?, source: URLUpdateSource) -> String {
        // Handle empty URL string
        guard !urlString.isEmpty else {
            return getFallbackDisplayURL()
        }
        
        // For user input, show raw input (but validate it)
        if source == .userInput {
            return urlString.count < 500 ? urlString : String(urlString.prefix(500)) + "..."
        }
        
        // For navigation, prefer title when available and valid
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty,
           title != "New Tab",
           title.count < 200 {
            return title
        }
        
        // Otherwise, show cleaned URL
        return cleanDisplayURL(urlString)
    }
    
    private func cleanDisplayURL(_ url: String) -> String {
        guard !url.isEmpty else { return "" }
        
        var cleanURL = url
        
        // Remove protocol
        if cleanURL.hasPrefix("https://") {
            cleanURL = String(cleanURL.dropFirst(8))
        } else if cleanURL.hasPrefix("http://") {
            cleanURL = String(cleanURL.dropFirst(7))
        }
        
        // Remove www.
        if cleanURL.hasPrefix("www.") {
            cleanURL = String(cleanURL.dropFirst(4))
        }
        
        // Remove trailing slash
        if cleanURL.hasSuffix("/") {
            cleanURL = String(cleanURL.dropLast())
        }
        
        return cleanURL
    }
    
    private func setupNotificationObservers() {
        // Listen for tab switches
        NotificationCenter.default
            .publisher(for: .tabDidBecomeActive)
            .sink { _ in
                // Tab switch updates will be handled directly by TabManager
                // This is just a placeholder for future tab-specific notifications
            }
            .store(in: &cancellables)
        
        // Listen for navigation completions
        NotificationCenter.default
            .publisher(for: Notification.Name("pageNavigationCompleted"))
            .sink { [weak self] notification in
                if let tabID = notification.object as? UUID,
                   self?.activeTabID == tabID {
                    // Trigger a refresh of URL state from the active tab
                    self?.refreshFromActiveTab()
                }
            }
            .store(in: &cancellables)
    }
    
    private func refreshFromActiveTab() {
        // This method can be called to refresh URL state from the current active tab
        // Implementation would need access to TabManager to get current active tab
    }
    
    // MARK: - Error Handling and Validation
    
    private func isValidTabID(_ tabID: UUID) -> Bool {
        // Basic UUID validation - ensure it's not nil and has valid format
        return tabID.uuidString.count == 36
    }
    
    private func validateAndSanitizeURL(_ urlString: String) -> URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Handle empty or invalid input
        guard !trimmed.isEmpty else { return nil }
        
        // Try to create URL directly first
        if let url = URL(string: trimmed) {
            return url
        }
        
        // Try with https prefix for domain-like strings
        if !trimmed.hasPrefix("http://") && !trimmed.hasPrefix("https://") {
            if let httpsURL = URL(string: "https://\(trimmed)") {
                return httpsURL
            }
        }
        
        // Last resort: return nil for invalid URLs
        print("⚠️ URLSynchronizer: Could not create valid URL from '\(trimmed)'")
        return nil
    }
    
    /// Handles edge cases and provides fallback URL display
    private func getFallbackDisplayURL() -> String {
        return "New Tab"
    }
    
    /// Safely updates URL state with comprehensive error handling
    private func safeURLUpdate(url: URL?, title: String?, isLoading: Bool, progress: Double, source: URLUpdateSource) {
        // Validate progress value
        let safeProgress = max(0.0, min(1.0, progress.isFinite ? progress : 0.0))
        
        // Handle nil URL gracefully
        _ = url?.absoluteString ?? ""
        let safeTitle = title ?? ""
        
        // Perform the update with validated values
        performURLUpdate(
            url: url,
            title: safeTitle,
            isLoading: isLoading,
            progress: safeProgress,
            source: source
        )
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let urlSynchronizerDidUpdateURL = Notification.Name("URLSynchronizerDidUpdateURL")
    static let tabDidBecomeActive = Notification.Name("TabDidBecomeActive")
}