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
    
    /// Extract context from specific WebView
    func extractPageContext(from webView: WKWebView, tab: Tab) async -> WebpageContext? {
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
            sections.append(formatWebpageContext(context))
        }

        // 2. Browsing history (optional)
        if includeHistory && isHistoryContextEnabled, let historyContext = getHistoryContext() {
            sections.append(historyContext)
        }

        guard !sections.isEmpty else { return nil }
        return sections.joined(separator: "\n\n---\n\n")
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

        return """
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
    
    // MARK: - Private Methods
    
    private func performContentExtraction(from webView: WKWebView, tab: Tab) async throws -> WebpageContext {
        func extractOnce(completion: @escaping (Result<WebpageContext, Error>) -> Void) {
            let script = contentExtractionJavaScript

            // Set timeout for JavaScript execution
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: UInt64(contentExtractionTimeout * 1_000_000_000))
                completion(.failure(ContextError.extractionTimeout))
            }

            // Execute JavaScript on main thread
            Task { @MainActor in
                webView.evaluateJavaScript(script) { result, error in
                    timeoutTask.cancel()
                    if let error = error {
                        completion(.failure(ContextError.javascriptError(error.localizedDescription)))
                        return
                    }
                    guard let data = result as? [String: Any] else {
                        completion(.failure(ContextError.invalidResponse))
                        return
                    }
                    do {
                        let context = try self.parseExtractionResult(data, from: webView, tab: tab)
                        completion(.success(context))
                    } catch {
                        completion(.failure(error))
                    }
                }
            }
        }

        // First attempt
        var context = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<WebpageContext, Error>) in
            extractOnce { res in
                cont.resume(with: res)
            }
        }

        // Retry once if content seems insufficient for known dynamic sites
        if shouldRetryExtraction(for: context) {
            NSLog("🔄 Retrying context extraction after delay for dynamic site…")
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2s
            context = try await withCheckedThrowingContinuation { cont in
                extractOnce { res in
                    cont.resume(with: res)
                }
            }
        }

        return context
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
        
        // ENHANCED: Log multi-post extraction results
        if isMultiPost {
            NSLog("🔥 Multi-post extraction: \(postCount) posts from \(URL(string: url)?.host ?? "unknown site")")
        }
        
        NSLog("📊 Extraction method: \(extractionMethod), Posts: \(postCount), Content length: \(truncatedText.count)")
        
        return WebpageContext(
            url: url,
            title: title,
            text: truncatedText,
            headings: headings,
            links: links,
            wordCount: wordCount,
            extractionDate: Date(),
            tabId: tab.id
        )
    }
    
    // If extracted content looks suspiciously small for well-known dynamic sites, attempt a delayed retry once.
    private func shouldRetryExtraction(for context: WebpageContext) -> Bool {
        // Consider less than 300 chars as possibly insufficient.
        guard context.text.count < 300 else { return false }
        let dynamicDomains = ["reddit.com", "medium.com", "twitter.com", "x.com"]
        return dynamicDomains.contains(where: { context.url.contains($0) })
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
            try {
                // ENHANCED: Comprehensive content extraction for full article reading
                var bodyText = document.body.innerText || document.body.textContent || "";
                
                // Get page metadata
                var title = document.title || "";
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
                
                // ENHANCED: Multi-post extraction for Reddit and forum sites
                var extractedContent = "";
                var contentFound = false;
                var postCount = 0;
                
                // SPECIAL HANDLING: Reddit multi-post extraction
                if (url.includes('reddit.com')) {
                    var redditPosts = document.querySelectorAll('[data-testid="post-content"], .thing, .Post, [data-click-id="text"], .usertext-body');
                    
                    for (var i = 0; i < Math.min(redditPosts.length, 20); i++) {
                        var post = redditPosts[i];
                        var postText = post.textContent || post.innerText || "";
                        
                        // Filter out short posts (likely metadata)
                        if (postText.trim().length > 50) {
                            postCount++;
                            extractedContent += "POST " + postCount + ": " + postText.trim() + "\\n\\n";
                            contentFound = true;
                        }
                    }
                    
                    // Also try to get Reddit comments
                    if (postCount > 0) {
                        var comments = document.querySelectorAll('.Comment, [data-testid="comment"], .usertext .md');
                        var commentCount = 0;
                        
                        for (var i = 0; i < Math.min(comments.length, 15); i++) {
                            var comment = comments[i];
                            var commentText = comment.textContent || comment.innerText || "";
                            
                            if (commentText.trim().length > 30 && commentCount < 10) {
                                commentCount++;
                                extractedContent += "COMMENT " + commentCount + ": " + commentText.trim() + "\\n\\n";
                            }
                        }
                    }
                }
                
                // GENERAL MULTI-POST EXTRACTION: For other forum sites
                if (!contentFound) {
                    var multiPostSelectors = [
                        // Forum post selectors
                        '.message-body', '.post-message', '.forum-post', '.bb-post',
                        '.post-content', '.message-content', '.topic-post',
                        
                        // General post selectors
                        '.post', '.entry', '.article-item', '.content-item',
                        '[class*="post"]', '[class*="message"]', '[class*="comment"]'
                    ];
                    
                    for (var s = 0; s < multiPostSelectors.length && postCount < 15; s++) {
                        var posts = document.querySelectorAll(multiPostSelectors[s]);
                        
                        for (var p = 0; p < posts.length && postCount < 15; p++) {
                            var post = posts[p];
                            var postText = post.textContent || post.innerText || "";
                            
                            if (postText.trim().length > 100) {
                                postCount++;
                                extractedContent += "POST " + postCount + ": " + postText.trim() + "\\n\\n";
                                contentFound = true;
                            }
                        }
                    }
                }
                
                // FALLBACK: Single content extraction for traditional articles
                if (!contentFound) {
                    var singleContentSelectors = [
                        // Primary content selectors (highest priority)
                        'article', 'main', '[role="main"]', '.main-content', '#main-content',
                        '.article-content', '.entry-content', '.content-area',
                        
                        // News site selectors  
                        '.article-body', '.story-body', '.entry-body', '.post-body',
                        '.article-text', '.story-content', '.article-wrap',
                        
                        // Blog selectors
                        '#content', '.content', '#main',
                        
                        // Documentation selectors
                        '.documentation', '.docs', '.doc-content', '.readme'
                    ];
                    
                    // Try each selector in priority order
                    for (var i = 0; i < singleContentSelectors.length && !contentFound; i++) {
                        var elements = document.querySelectorAll(singleContentSelectors[i]);
                        for (var j = 0; j < elements.length; j++) {
                            var element = elements[j];
                            if (element && element.textContent && element.textContent.trim().length > 200) {
                                extractedContent += element.textContent.trim() + "\\n\\n";
                                contentFound = true;
                                break; // Found substantial content, break inner loop
                            }
                        }
                    }
                }
                
                // FALLBACK: If no main content found, extract paragraph content
                if (!contentFound) {
                    var paragraphs = document.querySelectorAll('p');
                    for (var i = 0; i < paragraphs.length; i++) {
                        var p = paragraphs[i];
                        if (p.textContent && p.textContent.trim().length > 50) {
                            extractedContent += p.textContent.trim() + "\\n\\n";
                        }
                    }
                }
                
                // FINAL FALLBACK: Use body text if nothing else worked
                var finalText = extractedContent.trim() || bodyText;
                
                // ENHANCED: Smart content cleaning while preserving POST structure
                finalText = finalText
                    // Normalize whitespace but preserve paragraph breaks and POST markers
                    .replace(/[ \\t]+/g, ' ')
                    .replace(/\\n\\s*\\n/g, '\\n\\n')
                    // Remove excessive line breaks (more than 2) but preserve POST boundaries
                    .replace(/\\n{3,}(?!POST|COMMENT)/g, '\\n\\n')
                    // Clean up common web artifacts
                    .replace(/Share\\s*Copy link\\s*/gi, '')
                    .replace(/Advertisement\\s*/gi, '')
                    .replace(/Skip to content\\s*/gi, '')
                    .replace(/Continue reading\\s*/gi, '')
                    .replace(/Read more\\s*/gi, '')
                    .replace(/Vote\\s*/gi, '')
                    .replace(/Reply\\s*/gi, '')
                    .replace(/permalink\\s*/gi, '')
                    .replace(/embed\\s*/gi, '')
                    .replace(/save\\s*/gi, '')
                    .replace(/context\\s*/gi, '')
                    .replace(/full comments\\s*/gi, '')
                    .trim();
                
                // Extract structured links for context
                var links = [];
                var linkElements = document.querySelectorAll('article a[href], main a[href], .content a[href], .post-content a[href]');
                for (var i = 0; i < Math.min(linkElements.length, 15); i++) {
                    var link = linkElements[i];
                    if (link.textContent && link.textContent.trim() && link.href && 
                        !link.href.startsWith('javascript:') && !link.href.startsWith('#')) {
                        var linkText = link.textContent.trim();
                        if (linkText.length > 5 && linkText.length < 100) {
                            links.push(linkText + ' (' + link.href + ')');
                        }
                    }
                }
                
                // ENHANCED: Better word count calculation
                var wordCount = finalText.trim().split(/\\s+/).filter(function(word) {
                    return word.length > 0 && word.match(/[a-zA-Z0-9]/);
                }).length;
                
                // QUALITY CHECK: Ensure we have substantial content
                if (finalText.length < 100) {
                    // Emergency extraction - get all visible text
                    var walker = document.createTreeWalker(
                        document.body,
                        NodeFilter.SHOW_TEXT,
                        function(node) {
                            var parent = node.parentElement;
                            if (parent && (parent.tagName === 'SCRIPT' || parent.tagName === 'STYLE' || 
                                          parent.style.display === 'none' || parent.hidden)) {
                                return NodeFilter.FILTER_REJECT;
                            }
                            return node.textContent.trim().length > 10 ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
                        }
                    );
                    
                    var textNodes = [];
                    var node;
                    while (node = walker.nextNode()) {
                        textNodes.push(node.textContent.trim());
                    }
                    
                    if (textNodes.length > 0) {
                        finalText = textNodes.join(' ').replace(/\\s+/g, ' ').trim();
                    }
                }
                
                return {
                    success: true,
                    text: finalText,
                    title: title,
                    url: url,
                    headings: headings.slice(0, 25), // More headings for better structure
                    links: links.slice(0, 15), // More links for context
                    wordCount: wordCount,
                    extractionTime: new Date().toISOString(),
                    contentLength: finalText.length,
                    extractionMethod: contentFound ? (postCount > 1 ? 'multi-post' : 'structured') : 'fallback',
                    postCount: postCount, // NEW: Track how many posts were extracted
                    isMultiPost: postCount > 1 // NEW: Flag for multi-post content
                };
                
            } catch (error) {
                return {
                    success: false,
                    error: error.toString(),
                    text: document.body.textContent || "Unable to extract content",
                    title: document.title || "Unknown",
                    url: window.location.href,
                    headings: [],
                    links: [],
                    wordCount: 0,
                    contentLength: 0,
                    extractionMethod: 'error'
                };
            }
        })();
        """
    }
}

// MARK: - Supporting Types

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

