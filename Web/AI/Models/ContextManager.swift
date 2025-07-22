import Foundation
import WebKit
import Combine

/// Context manager for extracting and processing tab content for AI assistance
/// Handles real-time content extraction, summarization, and context optimization
@MainActor
class ContextManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var currentTokenCount: Int = 0
    @Published var isProcessingContext: Bool = false
    @Published var lastContextUpdate: Date?
    
    // MARK: - Context Storage
    
    private var tabContextCache: [String: TabContext] = [:] // UUID -> TabContext
    private var contextHistory: [ContextSnapshot] = []
    private let maxHistoryItems = 50
    private let maxTokensPerTab = 2000
    private let maxTotalTokens = 32000
    
    // MARK: - Dependencies
    
    private weak var tabManager: TabManager?
    private let contextProcessor: ContextProcessor
    private let summarizationService: SummarizationService
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        self.contextProcessor = ContextProcessor()
        self.summarizationService = SummarizationService()
        
        NSLog("📝 Context Manager initialized")
    }
    
    func initialize() {
        // Find TabManager instance
        findTabManager()
        
        // Set up automatic context updates
        setupContextUpdates()
        
        NSLog("📝 Context Manager setup completed")
    }
    
    // MARK: - Public Interface
    
    /// Get current context for AI processing
    func getCurrentContext() async -> ContextData? {
        isProcessingContext = true
        defer { isProcessingContext = false }
        
        do {
            guard let tabManager = tabManager else {
                NSLog("⚠️ TabManager not available for context extraction")
                return nil
            }
            
            let activeTab = tabManager.activeTab
            let allTabs = Array(tabManager.tabs)
            
            // Extract context from active tab
            var activeTabContext: TabContext?
            if let activeTab = activeTab {
                activeTabContext = await extractTabContext(activeTab)
            }
            
            // Get recent tab contexts (up to 5 most recent)
            let recentTabContexts = await extractRecentTabContexts(allTabs, excluding: activeTab?.id)
            
            // Get browsing history context
            let historyContext = await extractHistoryContext()
            
            // Create combined context
            let contextData = ContextData(
                activeTab: activeTabContext,
                recentTabs: recentTabContexts,
                historyContext: historyContext,
                timestamp: Date()
            )
            
            // Update token count
            currentTokenCount = contextData.estimatedTokenCount
            lastContextUpdate = Date()
            
            return contextData
            
        } catch {
            NSLog("❌ Context extraction failed: \(error)")
            return nil
        }
    }
    
    /// Get context for a specific tab
    func getTabContext(_ tabId: String) async -> TabContext? {
        // Check cache first
        if let cached = tabContextCache[tabId], 
           Date().timeIntervalSince(cached.extractedAt) < 300 { // 5 minutes cache
            return cached
        }
        
        // Find tab and extract context
        guard let tabManager = tabManager,
              let tab = tabManager.tabs.first(where: { $0.id.uuidString == tabId }) else {
            return nil
        }
        
        return await extractTabContext(tab)
    }
    
    /// Force refresh context for all tabs
    func refreshAllContexts() async {
        guard let tabManager = tabManager else { return }
        
        isProcessingContext = true
        
        for tab in tabManager.tabs {
            let context = await extractTabContext(tab)
            if let context = context {
                tabContextCache[tab.id.uuidString] = context
            }
        }
        
        isProcessingContext = false
        lastContextUpdate = Date()
        
        NSLog("🔄 All tab contexts refreshed")
    }
    
    /// Clear context cache
    func clearCache() {
        tabContextCache.removeAll()
        contextHistory.removeAll()
        currentTokenCount = 0
        lastContextUpdate = nil
        
        NSLog("🗑️ Context cache cleared")
    }
    
    /// Get context history for analysis
    func getContextHistory(limit: Int = 10) -> [ContextSnapshot] {
        return Array(contextHistory.prefix(limit))
    }
    
    // MARK: - Private Methods
    
    private func findTabManager() {
        // This would typically be injected, but for now we'll search for it
        // In a real implementation, this would be properly dependency injected
        NSLog("🔍 Searching for TabManager instance...")
    }
    
    private func setupContextUpdates() {
        // Set up periodic context updates
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updateContextIfNeeded()
            }
        }
    }
    
    private func updateContextIfNeeded() async {
        // Only update if we haven't updated recently
        guard let lastUpdate = lastContextUpdate,
              Date().timeIntervalSince(lastUpdate) > 30 else {
            return
        }
        
        // Extract context for active tab only to minimize processing
        guard let tabManager = tabManager,
              let activeTab = tabManager.activeTab else {
            return
        }
        
        let context = await extractTabContext(activeTab)
        if let context = context {
            tabContextCache[activeTab.id.uuidString] = context
        }
    }
    
    private func extractTabContext(_ tab: Tab) async -> TabContext? {
        guard let webView = tab.webView,
              let url = tab.url else {
            return nil
        }
        
        do {
            // Extract page content
            let pageContent = try await extractPageContent(from: webView)
            
            // Process and summarize content
            let processedContent = await contextProcessor.processContent(
                pageContent,
                maxTokens: maxTokensPerTab
            )
            
            // Create tab context
            let tabContext = TabContext(
                tabId: tab.id.uuidString,
                url: url,
                title: tab.title ?? "Untitled",
                content: processedContent,
                extractedAt: Date(),
                tokenCount: contextProcessor.estimateTokens(processedContent)
            )
            
            // Cache the context
            tabContextCache[tab.id.uuidString] = tabContext
            
            return tabContext
            
        } catch {
            NSLog("❌ Failed to extract context for tab \(tab.title ?? "Untitled"): \(error)")
            return nil
        }
    }
    
    private func extractPageContent(from webView: WKWebView) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            // JavaScript to extract clean text content from the page
            let script = """
                function extractContent() {
                    // Remove script and style elements
                    const scripts = document.querySelectorAll('script, style, nav, footer, aside');
                    scripts.forEach(el => el.remove());
                    
                    // Get main content areas
                    const selectors = ['main', 'article', '[role="main"]', '.content', '#content'];
                    let mainContent = null;
                    
                    for (const selector of selectors) {
                        mainContent = document.querySelector(selector);
                        if (mainContent) break;
                    }
                    
                    // Fallback to body if no main content found
                    const contentElement = mainContent || document.body;
                    
                    // Extract text with basic formatting
                    function extractTextFromElement(element) {
                        let text = '';
                        const walker = document.createTreeWalker(
                            element,
                            NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT,
                            null,
                            false
                        );
                        
                        let node;
                        while (node = walker.nextNode()) {
                            if (node.nodeType === Node.TEXT_NODE) {
                                const textContent = node.textContent.trim();
                                if (textContent.length > 0) {
                                    text += textContent + ' ';
                                }
                            } else if (node.nodeType === Node.ELEMENT_NODE) {
                                const tagName = node.tagName.toLowerCase();
                                if (['h1', 'h2', 'h3', 'h4', 'h5', 'h6'].includes(tagName)) {
                                    text += '\\n\\n';
                                } else if (['p', 'div', 'br'].includes(tagName)) {
                                    text += '\\n';
                                }
                            }
                        }
                        
                        return text;
                    }
                    
                    const content = extractTextFromElement(contentElement);
                    
                    return {
                        content: content.replace(/\\s+/g, ' ').trim(),
                        title: document.title || '',
                        url: window.location.href,
                        headings: Array.from(document.querySelectorAll('h1, h2, h3')).map(h => h.textContent.trim()).filter(h => h.length > 0)
                    };
                }
                
                extractContent();
            """
            
            webView.evaluateJavaScript(script) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let result = result as? [String: Any],
                      let content = result["content"] as? String else {
                    continuation.resume(throwing: ContextError.extractionFailed("Failed to extract content"))
                    return
                }
                
                continuation.resume(returning: content)
            }
        }
    }
    
    private func extractRecentTabContexts(_ tabs: [Tab], excluding excludedId: UUID?) async -> [TabContext] {
        let filteredTabs = tabs
            .filter { $0.id != excludedId }
            .sorted { ($0.lastActiveTime ?? Date.distantPast) > ($1.lastActiveTime ?? Date.distantPast) }
            .prefix(5)
        
        var contexts: [TabContext] = []
        
        for tab in filteredTabs {
            if let context = await extractTabContext(tab) {
                contexts.append(context)
            }
        }
        
        return contexts
    }
    
    private func extractHistoryContext() async -> HistoryContext? {
        // This would integrate with the browser's history service
        // For now, return placeholder
        return HistoryContext(
            recentDomains: [],
            topSites: [],
            searchQueries: []
        )
    }
    
    private func createContextSnapshot(_ data: ContextData) {
        let snapshot = ContextSnapshot(
            timestamp: Date(),
            activeTabUrl: data.activeTab?.url,
            tabCount: data.recentTabs.count,
            totalTokens: data.estimatedTokenCount
        )
        
        contextHistory.insert(snapshot, at: 0)
        
        // Limit history size
        if contextHistory.count > maxHistoryItems {
            contextHistory.removeLast()
        }
    }
}

// MARK: - Supporting Types

/// Complete context data for AI processing
struct ContextData {
    let activeTab: TabContext?
    let recentTabs: [TabContext]
    let historyContext: HistoryContext?
    let timestamp: Date
    
    var estimatedTokenCount: Int {
        var count = 0
        count += activeTab?.tokenCount ?? 0
        count += recentTabs.reduce(0) { $0 + $1.tokenCount }
        count += historyContext?.estimatedTokens ?? 0
        return count
    }
}

/// Context for a single tab
struct TabContext {
    let tabId: String
    let url: URL
    let title: String
    let content: String
    let extractedAt: Date
    let tokenCount: Int
    
    var summary: String {
        if content.count > 200 {
            return String(content.prefix(200)) + "..."
        }
        return content
    }
}

/// Historical browsing context
struct HistoryContext {
    let recentDomains: [String]
    let topSites: [String]
    let searchQueries: [String]
    
    var estimatedTokens: Int {
        return (recentDomains.joined().count + 
                topSites.joined().count + 
                searchQueries.joined().count) / 4 // Rough token estimate
    }
}

/// Context snapshot for history tracking
struct ContextSnapshot {
    let timestamp: Date
    let activeTabUrl: URL?
    let tabCount: Int
    let totalTokens: Int
}

/// Context processing errors
enum ContextError: LocalizedError {
    case extractionFailed(String)
    case processingFailed(String)
    case webViewNotAvailable
    
    var errorDescription: String? {
        switch self {
        case .extractionFailed(let message):
            return "Content extraction failed: \(message)"
        case .processingFailed(let message):
            return "Context processing failed: \(message)"
        case .webViewNotAvailable:
            return "WebView not available for content extraction"
        }
    }
}