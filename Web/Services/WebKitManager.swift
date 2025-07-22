import Foundation
import WebKit
import Combine

/// Singleton manager for WebKit resources to optimize memory usage through shared process pools
/// and provide centralized configuration for all WKWebView instances
class WebKitManager: ObservableObject {
    static let shared = WebKitManager()
    
    // MARK: - Shared WebKit Resources
    
    /// Shared process pool for memory efficiency across all tabs
    /// Using a single process pool reduces memory overhead and enables cookie/session sharing
    let processPool = WKProcessPool()
    
    /// Default website data store for regular browsing
    let defaultDataStore = WKWebsiteDataStore.default()
    
    /// Non-persistent data store for incognito browsing
    lazy var incognitoDataStore = WKWebsiteDataStore.nonPersistent()
    
    // MARK: - Configuration
    
    private init() {
        setupWebKitOptimizations()
    }
    
    /// Creates optimized WKWebViewConfiguration with shared resources
    /// - Parameter isIncognito: Whether this configuration is for incognito browsing
    /// - Returns: Configured WKWebViewConfiguration with shared process pool
    func createConfiguration(isIncognito: Bool = false) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        
        // Use shared process pool for memory efficiency
        configuration.processPool = processPool
        
        // Use appropriate data store
        configuration.websiteDataStore = isIncognito ? incognitoDataStore : defaultDataStore
        
        // Performance optimizations
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        
        // Security settings - allowsLinkPreview is WKWebView property, not configuration
        
        // Content blocking and ad blocking preparation
        setupContentBlocking(for: configuration)
        
        return configuration
    }
    
    /// Creates WKWebView with optimized configuration
    /// - Parameters:
    ///   - frame: Initial frame for the web view
    ///   - isIncognito: Whether this is for incognito browsing
    /// - Returns: Configured WKWebView instance
    func createWebView(frame: CGRect = CGRect(x: 0, y: 0, width: 100, height: 100), isIncognito: Bool = false) -> WKWebView {
        let configuration = createConfiguration(isIncognito: isIncognito)
        let webView = WKWebView(frame: frame, configuration: configuration)
        
        // Apply standard settings
        applyStandardSettings(to: webView)
        
        return webView
    }
    
    // MARK: - WebKit Optimizations
    
    private func setupWebKitOptimizations() {
        // Suppress verbose WebKit logging for cleaner console output
        setenv("WEBKIT_DISABLE_VERBOSE_LOGGING", "1", 1)
        setenv("WEBKIT_SUPPRESS_PROCESS_LOGS", "1", 1)
        setenv("OS_ACTIVITY_MODE", "disable", 1)
    }
    
    private func setupContentBlocking(for configuration: WKWebViewConfiguration) {
        // Future: Content blocking rules will be added here
        // This is where EasyList and custom ad blocking rules will be implemented
        
        let userContentController = WKUserContentController()
        configuration.userContentController = userContentController
    }
    
    private func applyStandardSettings(to webView: WKWebView) {
        // Standard Safari user agent to prevent Google's embedded browser detection
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        
        // Enable developer tools and inspection
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        
        // Performance settings
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.allowsLinkPreview = true
    }
    
    // MARK: - Memory Management
    
    /// Clears website data for memory management
    /// - Parameter includeIncognito: Whether to also clear incognito data
    func clearWebsiteData(includeIncognito: Bool = false) {
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        
        defaultDataStore.removeData(ofTypes: dataTypes, modifiedSince: Date.distantPast) { }
        
        if includeIncognito {
            incognitoDataStore.removeData(ofTypes: dataTypes, modifiedSince: Date.distantPast) { }
        }
    }
    
    /// Gets current memory usage information for the shared process pool
    /// Note: This is an approximation as WebKit doesn't expose detailed memory metrics
    func getEstimatedMemoryUsage() -> Int64 {
        // This will be enhanced with actual memory monitoring in the MemoryMonitor service
        return 0
    }
}