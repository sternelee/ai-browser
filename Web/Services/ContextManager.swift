import Foundation
import WebKit
import SwiftUI
import CoreData

/// Manages webpage content extraction and context generation for AI integration
/// Provides cleaned, summarized webpage content to enhance AI responses
class ContextManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isExtracting: Bool = false
    @Published var lastExtractedContext: WebpageContext?
    @Published var contextStatus: String = "Ready"
    
    // MARK: - Singleton
    
    static let shared = ContextManager()
    
    // MARK: - Properties
    
    /// Maximum number of characters allowed in `WebpageContext.text`.
    /// 0 ➜ unlimited (no truncation). We default to **0** because modern Apple-Silicon devices can easily feed tens of thousands of characters to the 2B Gemma model.
    /// If we later decide to cap it dynamically, we just need to set this to a non-zero value.
    private let maxContentLength: Int = 0
    private let contentExtractionTimeout = 10.0 // seconds
    private var lastExtractionTime: Date?
    private let minExtractionInterval: TimeInterval = 2.0 // Prevent spam extraction
    
    // ENHANCED: Content extraction caching
    private var contextCache: [String: CachedContext] = [:]
    private let maxCacheSize = 50 // Maximum number of cached contexts
    private let cacheExpirationTime: TimeInterval = 300 // 5 minutes
    private var cacheAccessOrder: [String] = [] // For LRU eviction
    
    // HISTORY CONTEXT CONFIGURATION
    private let maxHistoryItems = 10 // Limit history items for context
    private let maxHistoryDays: TimeInterval = 1 * 24 * 60 * 60 // 1 day lookback
    private let maxHistoryContentLength = 3000 // Limit history context size
    
    // Privacy settings for history context
    @Published var isHistoryContextEnabled: Bool = true
    @Published var historyContextScope: HistoryContextScope = .recent
    
    private init() {
        NSLog("🔮 ContextManager initialized")
    }
    
    // MARK: - Public Interface
    
    /// Extract context from the currently active tab
    func extractCurrentPageContext(from tabManager: TabManager) async -> WebpageContext? {
        guard let activeTab = tabManager.activeTab,
              let webView = activeTab.webView else {
            NSLog("⚠️ No active tab or WebView available for context extraction")
            return nil
        }
        
        // Throttle extractions to prevent performance issues
        if let lastTime = lastExtractionTime,
           Date().timeIntervalSince(lastTime) < minExtractionInterval {
            return lastExtractedContext
        }
        
        return await extractPageContext(from: webView, tab: activeTab)
    }
    
    /// Extract context from specific WebView with intelligent caching
    func extractPageContext(from webView: WKWebView, tab: Tab) async -> WebpageContext? {
        guard let url = webView.url?.absoluteString else {
            NSLog("⚠️ No URL available for context extraction")
            return nil
        }
        
        // Check cache first
        if let cachedContext = getCachedContext(for: url) {
            NSLog("🎯 Using cached context: \(cachedContext.context.text.count) characters from \(cachedContext.context.title)")
            
            await MainActor.run {
                lastExtractedContext = cachedContext.context
            }
            
            return cachedContext.context
        }
        
        await MainActor.run {
            isExtracting = true
            contextStatus = "Extracting page content..."
        }
        
        defer {
            Task { @MainActor in
                isExtracting = false
                contextStatus = "Ready"
            }
            lastExtractionTime = Date()
        }
        
        do {
            let context = try await performContentExtraction(from: webView, tab: tab)
            
            // Cache the extracted context
            cacheContext(context, for: url)
            
            await MainActor.run {
                lastExtractedContext = context
            }
            
            NSLog("✅ Context extracted: \(context.text.count) characters from \(context.url)")
            return context
            
        } catch {
            NSLog("❌ Context extraction failed: \(error.localizedDescription)")
            await MainActor.run {
                contextStatus = "Extraction failed"
            }
            return nil
        }
    }
    
    /// Returns a rich, structured context string for the AI model by combining the current page data
    /// with optional browsing-history context. The page section includes title, URL, word count,
    /// a list of headings & prominent links, and finally the raw (truncated) body text.
    func getFormattedContext(from context: WebpageContext?, includeHistory: Bool = true) -> String? {
        var sections: [String] = []

        // 1. Current page
        if let context = context {
            let formattedContext = formatWebpageContext(context)
            sections.append(formattedContext)
            NSLog("🔍 Formatted context length: \(formattedContext.count) characters from \(context.title)")
        } else {
            NSLog("⚠️ No context provided to getFormattedContext")
        }

        // 2. Browsing history (optional)
        if includeHistory && isHistoryContextEnabled, let historyContext = getHistoryContext() {
            sections.append(historyContext)
        }

        guard !sections.isEmpty else { 
            NSLog("⚠️ No sections to format - returning nil")
            return nil 
        }
        
        let finalContext = sections.joined(separator: "\n\n---\n\n")
        NSLog("✅ Final formatted context: \(finalContext.count) characters")
        return finalContext
    }

    /// Builds a well-structured string from a `WebpageContext` that is optimised for LLM consumption.
    /// – Headings provide document outline.
    /// – Links surface key outbound references.
    /// – We keep the *full* cleaned text (up to `maxContentLength`) so the model can quote exact phrasing if necessary.
    private func formatWebpageContext(_ ctx: WebpageContext) -> String {
        // Headings (limit to first 12 for brevity)
        let headingLines: String = ctx.headings.prefix(12).map { "- \($0)" }.joined(separator: "\n")

        // Prominent links (limit 10) – already "text (url)" formatted by JS extractor
        let linkLines: String = ctx.links.prefix(10).map { "- \($0)" }.joined(separator: "\n")

        // Optionally include a quick preview/summary (first 2-3 sentences) to guide the model before the wall of text
        let preview: String = {
            // Rough sentence splitting on period/exclamation/question marks.
            let delimiters: Set<Character> = [".", "!", "?"]
            var current = ""
            var sentences: [String] = []
            for char in ctx.text {
                current.append(char)
                if delimiters.contains(char) {
                    let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        sentences.append(trimmed)
                    }
                    current = ""
                }
                if sentences.count >= 3 { break }
            }
            return sentences.joined(separator: " ")
        }()

        // Re-compute word count to avoid stale/incorrect values from earlier extractions
        let dynamicWordCount = ctx.text.split { $0.isWhitespace || $0.isNewline }.count

        let formattedResult = """
        Current webpage context:
        Title: \(ctx.title)
        URL: \(ctx.url)
        Word Count: \(dynamicWordCount)

        Outline (headings):
        \(headingLines.isEmpty ? "(none)" : headingLines)

        Prominent links:
        \(linkLines.isEmpty ? "(none)" : linkLines)

        Preview:
        \(preview)

        Full content (truncated to \(maxContentLength) chars):
        \(ctx.text)
        """
        
        NSLog("🔍 formatWebpageContext result length: \(formattedResult.count) characters, text length: \(ctx.text.count)")
        return formattedResult
    }
    
    /// Get browsing history context for AI processing
    func getHistoryContext() -> String? {
        let historyItems = extractRelevantHistory()
        guard !historyItems.isEmpty else { return nil }
        
        var historyParts: [String] = ["Recent browsing history context:"]
        
        for (index, item) in historyItems.enumerated() {
            let timeAgo = formatTimeAgo(item.lastVisitDate)
            let domain = extractDomain(from: item.url) ?? "unknown"
            
            let historyEntry = "\(index + 1). \(item.title ?? "Untitled") (\(domain)) - visited \(timeAgo)"
            historyParts.append(historyEntry)
        }
        
        let historyContext = historyParts.joined(separator: "\n")
        
        // Limit history context size
        if historyContext.count > maxHistoryContentLength {
            let truncated = String(historyContext.prefix(maxHistoryContentLength))
            return truncated + "... (history truncated for context)"
        }
        
        return historyContext
    }
    
    /// Check if context extraction is available for the current tab
    func canExtractContext(from tabManager: TabManager) -> Bool {
        guard let activeTab = tabManager.activeTab,
              let webView = activeTab.webView,
              let url = webView.url else {
            return false
        }
        
        // Don't extract from special URLs
        let scheme = url.scheme?.lowercased() ?? ""
        return scheme == "http" || scheme == "https"
    }
    
    // MARK: - History Context Methods
    
    /// Extract relevant browsing history for AI context
    private func extractRelevantHistory() -> [HistoryItem] {
        let historyService = HistoryService.shared
        let cutoffDate = Date().addingTimeInterval(-maxHistoryDays)
        
        // Get recent history based on scope
        let historyItems: [HistoryItem]
        
        switch historyContextScope {
        case .recent:
            historyItems = Array(historyService.recentHistory.prefix(maxHistoryItems))
        case .today:
            let startOfDay = Calendar.current.startOfDay(for: Date())
            historyItems = historyService.getHistory(from: startOfDay, to: Date())
        case .lastHour:
            let oneHourAgo = Date().addingTimeInterval(-3600)
            historyItems = historyService.getHistory(from: oneHourAgo, to: Date())
        case .mostVisited:
            historyItems = historyService.getMostVisited(limit: maxHistoryItems)
        }
        
        // Filter out items older than cutoff and limit results
        let filteredItems = historyItems
            .filter { $0.lastVisitDate >= cutoffDate }
            .filter { !shouldExcludeFromHistoryContext($0.url) }
            .prefix(maxHistoryItems)
        
        return Array(filteredItems)
    }
    
    /// Check if URL should be excluded from history context
    private func shouldExcludeFromHistoryContext(_ url: String) -> Bool {
        let excludedDomains = [
            "localhost", "127.0.0.1", "::1",
            "chrome://", "webkit://", "about:",
            "data:", "file://"
        ]
        
        for excludedDomain in excludedDomains {
            if url.contains(excludedDomain) {
                return true
            }
        }
        
        // Exclude sensitive domains (banking, medical, etc.)
        let sensitiveDomains = [
            "bank", "medical", "health", "pharmacy",
            "login", "auth", "secure", "private"
        ]
        
        let lowercaseUrl = url.lowercased()
        for sensitiveDomain in sensitiveDomains {
            if lowercaseUrl.contains(sensitiveDomain) {
                return true
            }
        }
        
        return false
    }
    
    /// Extract domain from URL for context display
    private func extractDomain(from url: String) -> String? {
        guard let urlObj = URL(string: url) else { return nil }
        return urlObj.host
    }
    
    /// Format time ago string for history context
    private func formatTimeAgo(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        
        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }
    
    /// Configure history context settings
    func configureHistoryContext(enabled: Bool, scope: HistoryContextScope) {
        isHistoryContextEnabled = enabled
        historyContextScope = scope
        NSLog("🔮 History context configured: enabled=\(enabled), scope=\(scope)")
    }
    
    /// Clear history context cache (for privacy)
    func clearHistoryContextCache() {
        // Clear any cached history context data
        NSLog("🗑️ History context cache cleared")
    }
    
    // MARK: - Content Caching Methods
    
    /// Get cached context for URL if it exists and is still fresh
    private func getCachedContext(for url: String) -> CachedContext? {
        // Clean up expired entries first
        cleanExpiredCache()
        
        guard let cachedContext = contextCache[url] else {
            return nil
        }
        
        // Check if cache entry is still fresh
        if Date().timeIntervalSince(cachedContext.cachedAt) > cacheExpirationTime {
            contextCache.removeValue(forKey: url)
            cacheAccessOrder.removeAll { $0 == url }
            return nil
        }
        
        // Update access order for LRU
        cacheAccessOrder.removeAll { $0 == url }
        cacheAccessOrder.append(url)
        
        return cachedContext
    }
    
    /// Cache extracted context for future use
    private func cacheContext(_ context: WebpageContext, for url: String) {
        // Only cache high-quality content
        guard context.contentQuality > 15 else {
            NSLog("🚫 Skipping cache for low-quality content (quality: \(context.contentQuality))")
            return
        }
        
        // Implement LRU eviction if cache is full
        if contextCache.count >= maxCacheSize {
            evictLeastRecentlyUsed()
        }
        
        let cachedContext = CachedContext(
            context: context,
            cachedAt: Date(),
            accessCount: 1
        )
        
        contextCache[url] = cachedContext
        cacheAccessOrder.removeAll { $0 == url }
        cacheAccessOrder.append(url)
        
        NSLog("💾 Context cached for \(URL(string: url)?.host ?? "unknown"): \(context.text.count) characters, quality: \(context.contentQuality)")
    }
    
    /// Remove expired cache entries
    private func cleanExpiredCache() {
        let now = Date()
        let expiredUrls = contextCache.compactMap { (url, cachedContext) in
            now.timeIntervalSince(cachedContext.cachedAt) > cacheExpirationTime ? url : nil
        }
        
        for url in expiredUrls {
            contextCache.removeValue(forKey: url)
            cacheAccessOrder.removeAll { $0 == url }
        }
        
        if !expiredUrls.isEmpty {
            NSLog("🧹 Cleaned \(expiredUrls.count) expired cache entries")
        }
    }
    
    /// Evict least recently used cache entries
    private func evictLeastRecentlyUsed() {
        let removeCount = maxCacheSize / 4 // Remove 25% of cache when full
        let urlsToRemove = Array(cacheAccessOrder.prefix(removeCount))
        
        for url in urlsToRemove {
            contextCache.removeValue(forKey: url)
            cacheAccessOrder.removeAll { $0 == url }
        }
        
        NSLog("🗑️ Evicted \(urlsToRemove.count) LRU cache entries")
    }
    
    /// Clear all cached contexts
    func clearContextCache() {
        contextCache.removeAll()
        cacheAccessOrder.removeAll()
        NSLog("🗑️ All context cache cleared")
    }
    
    /// Get cache statistics for debugging
    func getCacheStatistics() -> (size: Int, hitRate: Double, avgQuality: Double) {
        let size = contextCache.count
        
        let totalAccess = contextCache.values.reduce(0) { $0 + $1.accessCount }
        let hitRate = totalAccess > 0 ? Double(size) / Double(totalAccess) : 0.0
        
        let avgQuality = contextCache.isEmpty ? 0.0 : 
            Double(contextCache.values.reduce(0) { $0 + $1.context.contentQuality }) / Double(size)
        
        return (size: size, hitRate: hitRate, avgQuality: avgQuality)
    }
    
    // MARK: - Private Methods
    
    private func performContentExtraction(from webView: WKWebView, tab: Tab) async throws -> WebpageContext {
        // ENHANCED: Multi-strategy content extraction with comprehensive fallbacks
        
        var bestContext: WebpageContext?
        var extractionStrategies: [ExtractionStrategy] = []
        
        // Strategy 1: Enhanced JavaScript extraction (primary)
        extractionStrategies.append(.enhancedJavaScript)
        
        // Strategy 2: Network request interception (if available)
        extractionStrategies.append(.networkInterception)
        
        // Strategy 3: Lazy-load scroll extraction
        extractionStrategies.append(.lazyLoadScroll)
        
        // Strategy 4: Emergency DOM extraction
        extractionStrategies.append(.emergencyExtraction)
        
        for (index, strategy) in extractionStrategies.enumerated() {
            NSLog("🔍 Attempting extraction strategy \(index + 1): \(strategy.description)")
            
            do {
                let context = try await executeExtractionStrategy(strategy, webView: webView, tab: tab)
                
                if bestContext == nil || context.contentQuality > (bestContext?.contentQuality ?? 0) {
                    bestContext = context
                }
                
                // If we have high-quality content, we can stop
                if context.isHighQuality {
                    NSLog("✅ High-quality content found with \(strategy.description)")
                    break
                }
                
                // If strategy recommends no retry, continue to next strategy
                if !context.shouldRetry && context.contentQuality > 10 {
                    NSLog("📈 Acceptable content found with \(strategy.description)")
                    break
                }
                
            } catch {
                NSLog("❌ Strategy \(strategy.description) failed: \(error.localizedDescription)")
                continue
            }
        }
        
        guard let finalContext = bestContext else {
            throw ContextError.extractionTimeout
        }
        
        return finalContext
    }
    
    private func executeExtractionStrategy(_ strategy: ExtractionStrategy, webView: WKWebView, tab: Tab) async throws -> WebpageContext {
        switch strategy {
        case .enhancedJavaScript:
            return try await performJavaScriptExtraction(webView: webView, tab: tab)
            
        case .networkInterception:
            // For now, fall back to JavaScript - network interception would require WKURLScheme handling
            return try await performJavaScriptExtraction(webView: webView, tab: tab)
            
        case .lazyLoadScroll:
            return try await performLazyLoadExtraction(webView: webView, tab: tab)
            
        case .emergencyExtraction:
            return try await performEmergencyExtraction(webView: webView, tab: tab)
        }
    }
    
    private func performJavaScriptExtraction(webView: WKWebView, tab: Tab) async throws -> WebpageContext {
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<WebpageContext, Error>) in
            let script = contentExtractionJavaScript

            // Set timeout for JavaScript execution
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: UInt64(contentExtractionTimeout * 1_000_000_000))
                cont.resume(throwing: ContextError.extractionTimeout)
            }

            // Execute JavaScript on main thread
            Task { @MainActor in
                webView.evaluateJavaScript(script) { result, error in
                    timeoutTask.cancel()
                    if let error = error {
                        cont.resume(throwing: ContextError.javascriptError(error.localizedDescription))
                        return
                    }
                    guard let data = result as? [String: Any] else {
                        cont.resume(throwing: ContextError.invalidResponse)
                        return
                    }
                    do {
                        let context = try self.parseExtractionResult(data, from: webView, tab: tab)
                        cont.resume(returning: context)
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    private func performLazyLoadExtraction(webView: WKWebView, tab: Tab) async throws -> WebpageContext {
        // First trigger lazy loading
        await triggerLazyLoadScroll(on: webView)
        
        // Wait for content to load
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Then perform JavaScript extraction
        return try await performJavaScriptExtraction(webView: webView, tab: tab)
    }
    
    private func performEmergencyExtraction(webView: WKWebView, tab: Tab) async throws -> WebpageContext {
        // Simplified extraction that just gets all visible text
        let emergencyScript = """
        (function() {
            try {
                var title = document.title || '';
                var url = window.location.href;
                var bodyText = document.body.innerText || document.body.textContent || '';
                
                // Clean basic content
                var cleanedText = bodyText
                    .replace(/\\s+/g, ' ')
                    .replace(/\\n+/g, '\\n')
                    .trim();
                
                var wordCount = cleanedText.split(/\\s+/).filter(w => w.length > 0).length;
                
                return {
                    success: true,
                    text: cleanedText,
                    title: title,
                    url: url,
                    headings: [],
                    links: [],
                    wordCount: wordCount,
                    extractionMethod: 'emergency',
                    contentQuality: Math.min(cleanedText.length / 50, 15), // Basic quality score
                    frameworksDetected: [],
                    extractionAttempt: 1,
                    isContentStable: true,
                    contentChanges: 0,
                    shouldRetry: false
                };
                
            } catch (error) {
                return {
                    success: false,
                    error: error.toString(),
                    text: 'Emergency extraction failed',
                    title: document.title || 'Unknown',
                    url: window.location.href,
                    headings: [],
                    links: [],
                    wordCount: 0,
                    extractionMethod: 'emergency-error',
                    contentQuality: 0,
                    frameworksDetected: [],
                    extractionAttempt: 1
                };
            }
        })();
        """
        
        return try await withCheckedThrowingContinuation { cont in
            Task { @MainActor in
                webView.evaluateJavaScript(emergencyScript) { result, error in
                    if let error = error {
                        cont.resume(throwing: ContextError.javascriptError(error.localizedDescription))
                        return
                    }
                    guard let data = result as? [String: Any] else {
                        cont.resume(throwing: ContextError.invalidResponse)
                        return
                    }
                    do {
                        let context = try self.parseExtractionResult(data, from: webView, tab: tab)
                        cont.resume(returning: context)
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    private func parseExtractionResult(_ data: [String: Any], from webView: WKWebView, tab: Tab) throws -> WebpageContext {
        guard let rawText = data["text"] as? String,
              let title = data["title"] as? String,
              let url = data["url"] as? String else {
            throw ContextError.missingRequiredFields
        }
        
        // Clean and process the content
        let cleanedText = cleanExtractedContent(rawText)
        let truncatedText = truncateContent(cleanedText)
        
        // Extract additional metadata
        let headings = data["headings"] as? [String] ?? []
        let links = data["links"] as? [String] ?? []

        // Re-compute word count on the Swift side to avoid under-count issues seen on some dynamic sites (e.g. Reddit).
        let wordCount = truncatedText.split { $0.isWhitespace || $0.isNewline }.count
        let extractionMethod = data["extractionMethod"] as? String ?? "unknown"
        let postCount = data["postCount"] as? Int ?? 0
        let isMultiPost = data["isMultiPost"] as? Bool ?? false
        
        // ENHANCED: Extract new quality metrics
        let contentQuality = data["contentQuality"] as? Int ?? 0
        let frameworksDetected = data["frameworksDetected"] as? [String] ?? []
        let extractionAttempt = data["extractionAttempt"] as? Int ?? 1
        let isContentStable = data["isContentStable"] as? Bool ?? true
        let contentChanges = data["contentChanges"] as? Int ?? 0
        let shouldRetry = data["shouldRetry"] as? Bool ?? false
        
        // ENHANCED: Log comprehensive extraction results
        if isMultiPost {
            NSLog("🔥 Multi-post extraction: \(postCount) posts from \(URL(string: url)?.host ?? "unknown site")")
        }
        
        if !frameworksDetected.isEmpty {
            NSLog("🎯 Frameworks detected: \(frameworksDetected.joined(separator: ", "))")
        }
        
        NSLog("📊 Extraction method: \(extractionMethod), Posts: \(postCount), Content length: \(truncatedText.count), Quality: \(contentQuality), Attempt: \(extractionAttempt), Stable: \(isContentStable), Changes: \(contentChanges)")
        
        // Store enhanced metrics for potential retry logic
        if shouldRetry {
            NSLog("🔄 Content quality insufficient (\(contentQuality)), retry recommended")
        }
        
        return WebpageContext(
            url: url,
            title: title,
            text: truncatedText,
            headings: headings,
            links: links,
            wordCount: wordCount,
            extractionDate: Date(),
            tabId: tab.id,
            // Store enhanced metrics for future use
            extractionMethod: extractionMethod,
            contentQuality: contentQuality,
            frameworksDetected: frameworksDetected,
            isContentStable: isContentStable,
            shouldRetry: shouldRetry
        )
    }
    
    // Enhanced retry logic based on content quality metrics
    private func shouldRetryExtraction(for context: WebpageContext) -> Bool {
        // Use the JavaScript-calculated shouldRetry flag as primary indicator
        if context.shouldRetry {
            return true
        }
        
        // Additional fallback checks for backward compatibility
        return context.contentQuality < 20 || 
               context.text.count < 200 || 
               (!context.isContentStable && context.wordCount < 100)
    }
    
    private func cleanExtractedContent(_ text: String) -> String {
        // Remove excessive whitespace and clean up content
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n+", with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleaned
    }
    
    private func truncateContent(_ text: String) -> String {
        // If no limit set or text is within limit, return as-is
        if maxContentLength == 0 || text.count <= maxContentLength {
            return text
        }

        // Truncate at word boundary
        let truncated = String(text.prefix(maxContentLength))
        if let lastSpace = truncated.lastIndex(of: " ") {
            let result = String(truncated[..<lastSpace])
            return result + "... (content truncated)"
        }

        return String(text.prefix(maxContentLength)) + "... (content truncated)"
    }
    
    // MARK: - JavaScript for Content Extraction
    
    private var contentExtractionJavaScript: String {
        """
        (function() {
            // ENHANCED 2025: Modern content extraction with MutationObserver and framework detection
            
            // Global state for enhanced extraction
            window.contentExtractionState = window.contentExtractionState || {
                observers: [],
                attempts: 0,
                maxAttempts: 5,
                isMonitoring: false,
                foundContent: null,
                frameworks: [],
                contentStability: { changes: 0, lastChange: Date.now() }
            };
            
            var state = window.contentExtractionState;
            
            function detectFrameworks() {
                var frameworks = [];
                
                // React detection
                if (window.React || window.__REACT_DEVTOOLS_GLOBAL_HOOK__ || 
                    document.querySelector('[data-reactroot]') || 
                    document.querySelector('[data-react-]')) {
                    frameworks.push('react');
                }
                
                // Vue detection  
                if (window.Vue || document.querySelector('[data-v-]') || 
                    document.querySelector('.v-')) {
                    frameworks.push('vue');
                }
                
                // Angular detection
                if (window.ng || window.getAllAngularRootElements || 
                    document.querySelector('[ng-app]') || 
                    document.querySelector('[data-ng-]')) {
                    frameworks.push('angular');
                }
                
                // Next.js detection
                if (window.__NEXT_DATA__ || document.querySelector('#__next')) {
                    frameworks.push('nextjs');
                }
                
                // Svelte detection
                if (document.querySelector('[data-svelte-]')) {
                    frameworks.push('svelte');
                }
                
                return frameworks;
            }
            
            function setupMutationObserver() {
                if (state.isMonitoring) return;
                
                var observer = new MutationObserver(function(mutations) {
                    var significantChanges = 0;
                    
                    mutations.forEach(function(mutation) {
                        if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
                            // Check if added nodes contain meaningful content
                            for (var i = 0; i < mutation.addedNodes.length; i++) {
                                var node = mutation.addedNodes[i];
                                if (node.nodeType === Node.ELEMENT_NODE) {
                                    var text = node.textContent || '';
                                    if (text.trim().length > 50) {
                                        significantChanges++;
                                    }
                                }
                            }
                        }
                    });
                    
                    if (significantChanges > 0) {
                        state.contentStability.changes += significantChanges;
                        state.contentStability.lastChange = Date.now();
                    }
                });
                
                observer.observe(document.body, {
                    childList: true,
                    subtree: true,
                    characterData: true
                });
                
                state.observers.push(observer);
                state.isMonitoring = true;
            }
            
            function calculateContentQuality(text) {
                if (!text || text.length < 50) return 0;
                
                var quality = 0;
                var sentences = text.split(/[.!?]+/).filter(s => s.trim().length > 10);
                var words = text.split(/\\s+/).filter(w => w.length > 2);
                var uniqueWords = new Set(words.map(w => w.toLowerCase()));
                
                // Sentence structure scoring
                quality += Math.min(sentences.length * 2, 20);
                
                // Vocabulary diversity scoring
                var diversity = uniqueWords.size / Math.max(words.length, 1);
                quality += diversity * 30;
                
                // Length scoring (diminishing returns)
                quality += Math.min(text.length / 100, 25);
                
                // Penalize repetitive content
                var repetitivePatterns = text.match(/(\\b\\w+\\b)(?=.*\\1.*\\1)/gi);
                if (repetitivePatterns && repetitivePatterns.length > words.length * 0.3) {
                    quality *= 0.7; // 30% penalty for repetitive content
                }
                
                return Math.round(quality);
            }
            
            function extractWithFrameworkSupport() {
                var content = '';
                var method = 'unknown';
                
                // Framework-specific extraction strategies
                if (state.frameworks.includes('react')) {
                    // React: Look for common React patterns
                    var reactSelectors = [
                        '[data-testid*="post"]', '[data-testid*="content"]',
                        '.react-content', '[id*="react"]', '[class*="Post"]',
                        '[role="article"]', '[role="main"]'
                    ];
                    
                    for (var i = 0; i < reactSelectors.length; i++) {
                        var elements = document.querySelectorAll(reactSelectors[i]);
                        if (elements.length > 0) {
                            for (var j = 0; j < elements.length; j++) {
                                var text = elements[j].textContent || '';
                                if (text.trim().length > 100) {
                                    content += text.trim() + '\\n\\n';
                                    method = 'react-framework';
                                }
                            }
                            if (content) break;
                        }
                    }
                }
                
                if (!content && state.frameworks.includes('vue')) {
                    // Vue: Look for Vue-specific patterns
                    var vueSelectors = [
                        '[v-for]', '.vue-content', '[data-v-]',
                        '.v-card', '.v-content'
                    ];
                    
                    for (var i = 0; i < vueSelectors.length; i++) {
                        var elements = document.querySelectorAll(vueSelectors[i]);
                        if (elements.length > 0) {
                            for (var j = 0; j < elements.length; j++) {
                                var text = elements[j].textContent || '';
                                if (text.trim().length > 100) {
                                    content += text.trim() + '\\n\\n';
                                    method = 'vue-framework';
                                }
                            }
                            if (content) break;
                        }
                    }
                }
                
                return { content: content, method: method };
            }
            
            try {
                state.attempts++;
                
                // Detect frameworks on first attempt
                if (state.attempts === 1) {
                    state.frameworks = detectFrameworks();
                    setupMutationObserver();
                }
                
                // Get page metadata
                var title = document.title || '';
                var url = window.location.href;
                
                // Extract headings for structure understanding
                var headings = [];
                var headingElements = document.querySelectorAll('h1, h2, h3, h4, h5, h6');
                for (var i = 0; i < headingElements.length; i++) {
                    var heading = headingElements[i];
                    if (heading.textContent && heading.textContent.trim()) {
                        headings.push(heading.tagName.toLowerCase() + ': ' + heading.textContent.trim());
                    }
                }
                
                var extractedContent = '';
                var contentFound = false;
                var postCount = 0;
                var extractionMethod = 'fallback';
                
                // STRATEGY 1: Framework-aware extraction
                var frameworkResult = extractWithFrameworkSupport();
                if (frameworkResult.content) {
                    extractedContent = frameworkResult.content;
                    extractionMethod = frameworkResult.method;
                    contentFound = true;
                }
                
                // STRATEGY 2: Enhanced multi-post extraction with Reddit-specific improvements
                if (!contentFound) {
                    var multiPostSelectors = [
                        // Reddit-specific selectors (2025 updated)
                        '[data-testid="post-content"]', '[data-click-id="text"]',
                        '.Post', '[data-adclicklocation="text"]',
                        '.usertext-body', '[data-testid="comment"]',
                        
                        // Generic forum selectors
                        '.message-body', '.post-message', '.forum-post', '.bb-post',
                        '.post-content', '.message-content', '.topic-post',
                        '.comment-body', '.reply-content',
                        
                        // Social media selectors
                        '[data-testid*="post"]', '[data-testid*="tweet"]',
                        '.feed-item', '.timeline-item', '.story-content',
                        
                        // General content selectors
                        '.post', '.entry', '.article-item', '.content-item',
                        '[class*="post"]', '[class*="message"]', '[class*="comment"]',
                        '[role="article"]', '[itemtype*="Article"]'
                    ];
                    
                    for (var s = 0; s < multiPostSelectors.length && postCount < 20; s++) {
                        var posts = document.querySelectorAll(multiPostSelectors[s]);
                        
                        for (var p = 0; p < posts.length && postCount < 20; p++) {
                            var post = posts[p];
                            var postText = post.textContent || post.innerText || '';
                            
                            // Enhanced content validation
                            if (postText.trim().length > 50 && calculateContentQuality(postText) > 10) {
                                postCount++;
                                extractedContent += 'POST ' + postCount + ': ' + postText.trim() + '\\n\\n';
                                contentFound = true;
                                extractionMethod = 'multi-post-enhanced';
                            }
                        }
                    }
                }
                
                // STRATEGY 3: Single content extraction with semantic scoring
                if (!contentFound) {
                    var singleContentSelectors = [
                        // Primary content selectors (highest priority)
                        'article', 'main', '[role="main"]', '.main-content', '#main-content',
                        '.article-content', '.entry-content', '.content-area',
                        
                        // News and blog selectors  
                        '.article-body', '.story-body', '.entry-body', '.post-body',
                        '.article-text', '.story-content', '.article-wrap',
                        '.prose', '.content-wrapper', '.page-content',
                        
                        // Documentation and wiki selectors
                        '.documentation', '.docs', '.doc-content', '.readme',
                        '.wiki-content', '.markdown-body',
                        
                        // E-commerce selectors
                        '.product-description', '.item-details', '.listing-content'
                    ];
                    
                    var bestContent = { text: '', score: 0, method: 'structured' };
                    
                    for (var i = 0; i < singleContentSelectors.length; i++) {
                        var elements = document.querySelectorAll(singleContentSelectors[i]);
                        for (var j = 0; j < elements.length; j++) {
                            var element = elements[j];
                            if (element && element.textContent) {
                                var text = element.textContent.trim();
                                var score = calculateContentQuality(text);
                                
                                if (score > bestContent.score && text.length > 200) {
                                    bestContent = { text: text, score: score, method: 'structured-semantic' };
                                }
                            }
                        }
                    }
                    
                    if (bestContent.text) {
                        extractedContent = bestContent.text;
                        extractionMethod = bestContent.method;
                        contentFound = true;
                    }
                }
                
                // STRATEGY 4: Intelligent paragraph extraction
                if (!contentFound) {
                    var paragraphs = document.querySelectorAll('p, div, span');
                    var contentBlocks = [];
                    
                    for (var i = 0; i < paragraphs.length; i++) {
                        var p = paragraphs[i];
                        if (p.textContent && p.textContent.trim().length > 30) {
                            var quality = calculateContentQuality(p.textContent);
                            if (quality > 5) {
                                contentBlocks.push({
                                    text: p.textContent.trim(),
                                    quality: quality
                                });
                            }
                        }
                    }
                    
                    // Sort by quality and take the best content
                    contentBlocks.sort((a, b) => b.quality - a.quality);
                    var topBlocks = contentBlocks.slice(0, 10);
                    
                    if (topBlocks.length > 0) {
                        extractedContent = topBlocks.map(block => block.text).join('\\n\\n');
                        extractionMethod = 'semantic-paragraphs';
                        contentFound = true;
                    }
                }
                
                // FINAL FALLBACK: Enhanced emergency extraction
                var finalText = extractedContent.trim();
                if (!finalText || finalText.length < 100) {
                    var allTextNodes = [];
                    var walker = document.createTreeWalker(
                        document.body,
                        NodeFilter.SHOW_TEXT,
                        function(node) {
                            var parent = node.parentElement;
                            if (parent && (
                                parent.tagName === 'SCRIPT' || 
                                parent.tagName === 'STYLE' || 
                                parent.tagName === 'NOSCRIPT' ||
                                parent.style.display === 'none' || 
                                parent.hidden ||
                                parent.getAttribute('aria-hidden') === 'true'
                            )) {
                                return NodeFilter.FILTER_REJECT;
                            }
                            var text = node.textContent.trim();
                            return text.length > 20 ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
                        }
                    );
                    
                    var node;
                    while (node = walker.nextNode()) {
                        var text = node.textContent.trim();
                        if (calculateContentQuality(text) > 5) {
                            allTextNodes.push(text);
                        }
                    }
                    
                    if (allTextNodes.length > 0) {
                        finalText = allTextNodes.join(' ').replace(/\\s+/g, ' ').trim();
                        extractionMethod = 'emergency-semantic';
                    }
                }
                
                // ENHANCED: Advanced content cleaning while preserving structure
                finalText = finalText
                    .replace(/[ \\t]+/g, ' ')
                    .replace(/\\n\\s*\\n/g, '\\n\\n')
                    .replace(/\\n{3,}(?!POST|COMMENT)/g, '\\n\\n')
                    // Remove common web artifacts with context awareness
                    .replace(/(?:Share|Copy link|Advertisement|Skip to content|Continue reading|Read more|Vote|Reply|permalink|embed|save|context|full comments)\\s*/gi, '')
                    // Remove navigation elements
                    .replace(/(?:Home|About|Contact|Menu|Navigation|Search|Login|Register)\\s*(?:\\||•|-)\\s*/gi, '')
                    .trim();
                
                // Extract enhanced links with quality scoring
                var links = [];
                var linkElements = document.querySelectorAll('article a[href], main a[href], .content a[href], .post-content a[href], [role="article"] a[href]');
                for (var i = 0; i < Math.min(linkElements.length, 20); i++) {
                    var link = linkElements[i];
                    if (link.textContent && link.textContent.trim() && link.href && 
                        !link.href.startsWith('javascript:') && 
                        !link.href.startsWith('#') &&
                        !link.href.includes('void(0)')) {
                        var linkText = link.textContent.trim();
                        if (linkText.length > 3 && linkText.length < 120 && 
                            calculateContentQuality(linkText) > 3) {
                            links.push(linkText + ' (' + link.href + ')');
                        }
                    }
                }
                
                // Calculate final metrics
                var wordCount = finalText.trim().split(/\\s+/).filter(function(word) {
                    return word.length > 0 && word.match(/[a-zA-Z0-9]/);
                }).length;
                
                var contentQuality = calculateContentQuality(finalText);
                var isStable = (Date.now() - state.contentStability.lastChange) > 2000; // 2 seconds of stability
                
                // Store result for potential retry logic
                state.foundContent = {
                    text: finalText,
                    quality: contentQuality,
                    wordCount: wordCount,
                    stable: isStable
                };
                
                return {
                    success: true,
                    text: finalText,
                    title: title,
                    url: url,
                    headings: headings.slice(0, 30),
                    links: links.slice(0, 20),
                    wordCount: wordCount,
                    extractionTime: new Date().toISOString(),
                    contentLength: finalText.length,
                    extractionMethod: extractionMethod,
                    postCount: postCount,
                    isMultiPost: postCount > 1,
                    // ENHANCED METRICS
                    contentQuality: contentQuality,
                    frameworksDetected: state.frameworks,
                    extractionAttempt: state.attempts,
                    isContentStable: isStable,
                    contentChanges: state.contentStability.changes,
                    shouldRetry: contentQuality < 20 && !isStable && state.attempts < state.maxAttempts
                };
                
            } catch (error) {
                return {
                    success: false,
                    error: error.toString(),
                    text: document.body.textContent || 'Unable to extract content',
                    title: document.title || 'Unknown',
                    url: window.location.href,
                    headings: [],
                    links: [],
                    wordCount: 0,
                    contentLength: 0,
                    extractionMethod: 'error',
                    contentQuality: 0,
                    frameworksDetected: [],
                    extractionAttempt: state.attempts
                };
            }
        })();
        """
    }

    /// Programmatically scrolls the page to the bottom (and briefly back to top) to trigger lazy-loaded content like virtualised lists.
    /// Must be called on the main actor because it touches the WebView JS runtime.
    private func triggerLazyLoadScroll(on webView: WKWebView) async {
        await MainActor.run {
            let js = "(function(){ const scrollBottom = () => window.scrollTo(0, document.body.scrollHeight); scrollBottom(); setTimeout(scrollBottom, 200); setTimeout(() => window.scrollTo(0,0), 400); })();"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}

// MARK: - Supporting Types

/// Cached context entry with metadata
struct CachedContext {
    let context: WebpageContext
    let cachedAt: Date
    var accessCount: Int
}

/// Represents extracted webpage content and metadata
struct WebpageContext: Identifiable, Codable {
    let id = UUID()
    let url: String
    let title: String
    let text: String
    let headings: [String]
    let links: [String]
    let wordCount: Int
    let extractionDate: Date
    let tabId: UUID
    
    // ENHANCED: Quality and extraction metadata
    let extractionMethod: String
    let contentQuality: Int
    let frameworksDetected: [String]
    let isContentStable: Bool
    let shouldRetry: Bool
    
    // Default initializer for backward compatibility
    init(url: String, title: String, text: String, headings: [String], links: [String], 
         wordCount: Int, extractionDate: Date, tabId: UUID,
         extractionMethod: String = "unknown", contentQuality: Int = 0, 
         frameworksDetected: [String] = [], isContentStable: Bool = true, shouldRetry: Bool = false) {
        self.url = url
        self.title = title
        self.text = text
        self.headings = headings
        self.links = links
        self.wordCount = wordCount
        self.extractionDate = extractionDate
        self.tabId = tabId
        self.extractionMethod = extractionMethod
        self.contentQuality = contentQuality
        self.frameworksDetected = frameworksDetected
        self.isContentStable = isContentStable
        self.shouldRetry = shouldRetry
    }
    
    /// Get a concise summary for display
    var summary: String {
        let previewLength = 100
        if text.count <= previewLength {
            return text
        }
        
        let truncated = String(text.prefix(previewLength))
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "..."
        }
        return truncated + "..."
    }
    
    /// Check if the context is still fresh
    var isFresh: Bool {
        Date().timeIntervalSince(extractionDate) < 300 // 5 minutes
    }
    
    /// Check if the content quality is sufficient for AI processing
    var isHighQuality: Bool {
        return contentQuality >= 25 && wordCount >= 50
    }
    
    /// Get quality description for debugging
    var qualityDescription: String {
        switch contentQuality {
        case 0..<10:
            return "Very Poor"
        case 10..<20:
            return "Poor"
        case 20..<35:
            return "Fair"
        case 35..<50:
            return "Good"
        case 50..<70:
            return "Very Good"
        default:
            return "Excellent"
        }
    }
}

/// History context scope options
enum HistoryContextScope: String, CaseIterable {
    case recent = "recent"
    case today = "today"
    case lastHour = "lastHour"
    case mostVisited = "mostVisited"
    
    var displayName: String {
        switch self {
        case .recent:
            return "Recent History"
        case .today:
            return "Today Only"
        case .lastHour:
            return "Last Hour"
        case .mostVisited:
            return "Most Visited"
        }
    }
}

/// Content extraction strategies
enum ExtractionStrategy: CaseIterable {
    case enhancedJavaScript
    case networkInterception
    case lazyLoadScroll
    case emergencyExtraction
    
    var description: String {
        switch self {
        case .enhancedJavaScript:
            return "Enhanced JavaScript"
        case .networkInterception:
            return "Network Interception"
        case .lazyLoadScroll:
            return "Lazy-Load Scroll"
        case .emergencyExtraction:
            return "Emergency DOM"
        }
    }
}

/// Context extraction errors
enum ContextError: LocalizedError {
    case noWebView
    case noActiveTab
    case extractionTimeout
    case javascriptError(String)
    case invalidResponse
    case missingRequiredFields
    case contentTooLarge
    
    var errorDescription: String? {
        switch self {
        case .noWebView:
            return "No WebView available for content extraction"
        case .noActiveTab:
            return "No active tab available"
        case .extractionTimeout:
            return "Content extraction timed out"
        case .javascriptError(let message):
            return "JavaScript error: \(message)"
        case .invalidResponse:
            return "Invalid response from content extraction"
        case .missingRequiredFields:
            return "Missing required fields in extraction result"
        case .contentTooLarge:
            return "Webpage content is too large to process"
        }
    }
}

