import SwiftUI
import WebKit
import Combine
import UniformTypeIdentifiers
import ObjectiveC

class Tab: ObservableObject, Identifiable, Transferable, Equatable {
    let id = UUID()
    @Published var url: URL?
    @Published var title: String = "New Tab"
    @Published var favicon: NSImage?
    @Published var themeColor: NSColor?
    @Published var isLoading: Bool = false
    @Published var estimatedProgress: Double = 0.0
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var isIncognito: Bool = false
    @Published var lastAccessed: Date = Date()
    @Published var isActive: Bool = false
    
    // Performance optimization features
    @Published var isHibernated: Bool = false
    @Published var snapshot: NSImage?
    @Published var memoryUsage: Int64 = 0
    
    // Navigation history
    private(set) var backHistory: [HistoryEntry] = []
    private(set) var forwardHistory: [HistoryEntry] = []
    
    // WebView reference - keeping strong reference to prevent deallocation during tab switches
    private var _webView: WKWebView?
    
    // Track WebView ownership using associated objects
    private static var webViewOwnershipKey: UInt8 = 0
    
    var webView: WKWebView? {
        get { _webView }
        set {
            // CRITICAL: Prevent WebView sharing between tabs to fix content duplication bug
            if let newWebView = newValue {
                // Check if this WebView is already assigned to another tab
                let existingOwnerId = objc_getAssociatedObject(newWebView, &Self.webViewOwnershipKey) as? UUID
                
                if let existingId = existingOwnerId, existingId != id {
                    print("🚨 CRITICAL: Attempting to assign WebView from another tab! Expected: \(id), Got: \(existingId)")
                    return // Reject assignment to prevent content bleeding
                }
                
                // Set ownership tracking for this WebView
                objc_setAssociatedObject(newWebView, &Self.webViewOwnershipKey, id, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
            _webView = newValue
        }
    }
    
    // Simple hibernation timer for backward compatibility
    private var hibernationTimer: Timer?
    private let hibernationThreshold: TimeInterval = 1800 // Increased to 30 minutes to prevent aggressive hibernation
    
    struct HistoryEntry {
        let url: URL
        let title: String
        let timestamp: Date
    }
    
    init(url: URL? = nil, isIncognito: Bool = false) {
        self.url = url
        self.isIncognito = isIncognito
        
        // Start simple hibernation timer
        startHibernationTimer()
    }
    
    // MARK: - Navigation Methods
    func goBack() {
        webView?.goBack()
    }
    
    func goForward() {
        webView?.goForward()
    }
    
    func reload() {
        webView?.reload()
    }
    
    func stopLoading() {
        webView?.stopLoading()
    }
    
    func navigate(to url: URL) {
        self.url = url
        updateLastAccessed()
        
        // Trigger navigation in the webView if it exists
        if let webView = webView {
            let request = URLRequest(url: url)
            webView.load(request)
        }
    }
    
    // MARK: - Performance Management
    func hibernate() {
        // Only hibernate if tab has been inactive for a very long time and not loading
        // Don't hibernate tabs that are actively loading or recently accessed
        guard !isActive && !isHibernated && !isLoading else { return }
        guard Date().timeIntervalSince(lastAccessed) > hibernationThreshold else { return }
        
        // Create snapshot before hibernating
        createSnapshot()
        
        // Keep WebView in memory but mark as hibernated for UI purposes
        // This prevents content loss while still indicating hibernated state
        isHibernated = true
        
        // Tab hibernated successfully
    }
    
    func wakeUp() {
        guard isHibernated else { return }
        
        isHibernated = false
        updateLastAccessed()
        
        // Tab woken up successfully
    }
    
    private func createSnapshot() {
        guard let webView = webView else { return }
        
        let config = WKSnapshotConfiguration()
        let bounds = webView.bounds
        
        // Use safe rect validation to prevent Double/Int conversion issues
        let safeBounds = SafeNumericConversions.validateSafeRect(bounds)
        guard safeBounds.width > 0 && safeBounds.height > 0 else {
            return
        }
        
        config.rect = safeBounds
        
        webView.takeSnapshot(with: config) { [weak self] image, error in
            DispatchQueue.main.async {
                self?.snapshot = image
            }
        }
    }
    
    private func updateLastAccessed() {
        lastAccessed = Date()
        startHibernationTimer()
    }
    
    private func startHibernationTimer() {
        hibernationTimer?.invalidate()
        hibernationTimer = Timer.scheduledTimer(withTimeInterval: hibernationThreshold, repeats: false) { [weak self] _ in
            if !(self?.isActive ?? true) && !(self?.isLoading ?? false) {
                self?.hibernate()
            }
        }
    }
    
    func notifyLoadingStateChanged() {
        // Restart hibernation timer when loading state changes
        if !isActive {
            startHibernationTimer()
        }
    }
    
    // MARK: - Print functionality
    func printPage() {
        guard let webView = webView else { return }
        
        let printInfo = NSPrintInfo.shared
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.orientation = .portrait
        
        let printOperation = NSPrintOperation(view: webView, printInfo: printInfo)
        printOperation.showsProgressPanel = true
        printOperation.canSpawnSeparateThread = true
        
        printOperation.run()
    }
    
    // MARK: - Find in page
    func findInPage(_ searchText: String, forward: Bool = true) {
        guard let webView = webView else { return }
        
        let script = "window.find('\(searchText)', false, \(!forward), true)"
        webView.evaluateJavaScript(script)
    }
    
    deinit {
        hibernationTimer?.invalidate()
    }
    
    // MARK: - Equatable Implementation
    static func == (lhs: Tab, rhs: Tab) -> Bool {
        return lhs.id == rhs.id
    }
    
    // MARK: - Transferable Implementation
    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation { tab in
            tab.id.uuidString
        }
    }
}