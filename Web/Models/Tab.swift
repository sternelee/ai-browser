import SwiftUI
import WebKit
import Combine
import UniformTypeIdentifiers

class Tab: ObservableObject, Identifiable, Transferable {
    let id = UUID()
    @Published var url: URL?
    @Published var title: String = "New Tab"
    @Published var favicon: NSImage?
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
    
    // WebView reference (weak to prevent retain cycles)
    weak var webView: WKWebView?
    
    // Hibernation threshold (5 minutes of inactivity)
    private let hibernationThreshold: TimeInterval = 300
    private var hibernationTimer: Timer?
    
    struct HistoryEntry {
        let url: URL
        let title: String
        let timestamp: Date
    }
    
    init(url: URL? = nil, isIncognito: Bool = false) {
        self.url = url
        self.isIncognito = isIncognito
        
        // Start hibernation timer
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
    }
    
    // MARK: - Performance Management
    func hibernate() {
        guard !isActive && !isHibernated else { return }
        
        // Create snapshot before hibernating
        createSnapshot()
        
        // Remove WebView to free memory
        webView?.removeFromSuperview()
        webView = nil
        isHibernated = true
    }
    
    func wakeUp() {
        guard isHibernated else { return }
        
        isHibernated = false
        // WebView will be recreated when needed
        updateLastAccessed()
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
            if !(self?.isActive ?? true) {
                self?.hibernate()
            }
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
    
    // MARK: - Transferable Implementation
    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation { tab in
            tab.id.uuidString
        }
    }
}