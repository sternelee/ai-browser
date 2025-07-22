import Foundation
import WebKit
import SwiftUI

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
    
    private let maxContentLength = 8000 // Reasonable token limit for context
    private let contentExtractionTimeout = 10.0 // seconds
    private var lastExtractionTime: Date?
    private let minExtractionInterval: TimeInterval = 2.0 // Prevent spam extraction
    
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
    
    /// Get a formatted context string for AI processing
    func getFormattedContext(from context: WebpageContext?) -> String? {
        guard let context = context else { return nil }
        
        let formattedContext = """
        Current webpage context:
        
        Title: \(context.title)
        URL: \(context.url)
        
        Content:
        \(context.text)
        """
        
        return formattedContext
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
    
    // MARK: - Private Methods
    
    private func performContentExtraction(from webView: WKWebView, tab: Tab) async throws -> WebpageContext {
        return try await withCheckedThrowingContinuation { continuation in
            
            let script = contentExtractionJavaScript
            
            // Set timeout for JavaScript execution
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: UInt64(contentExtractionTimeout * 1_000_000_000))
                continuation.resume(throwing: ContextError.extractionTimeout)
            }
            
            webView.evaluateJavaScript(script) { result, error in
                timeoutTask.cancel()
                
                if let error = error {
                    continuation.resume(throwing: ContextError.javascriptError(error.localizedDescription))
                    return
                }
                
                guard let data = result as? [String: Any] else {
                    continuation.resume(throwing: ContextError.invalidResponse)
                    return
                }
                
                do {
                    let context = try self.parseExtractionResult(data, from: webView, tab: tab)
                    continuation.resume(returning: context)
                } catch {
                    continuation.resume(throwing: error)
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
        let wordCount = data["wordCount"] as? Int ?? 0
        
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
    
    private func cleanExtractedContent(_ text: String) -> String {
        // Remove excessive whitespace and clean up content
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n+", with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleaned
    }
    
    private func truncateContent(_ text: String) -> String {
        if text.count <= maxContentLength {
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
                // Extract main text content
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
                
                // Extract key links for context
                var links = [];
                var linkElements = document.querySelectorAll('a[href]');
                for (var i = 0; i < Math.min(linkElements.length, 10); i++) {
                    var link = linkElements[i];
                    if (link.textContent && link.textContent.trim() && link.href) {
                        links.push(link.textContent.trim() + ' (' + link.href + ')');
                    }
                }
                
                // Get word count approximation
                var wordCount = bodyText.trim().split(/\\s+/).filter(function(word) {
                    return word.length > 0;
                }).length;
                
                // Remove navigation and sidebar elements for cleaner content
                var contentSelectors = [
                    'main', 'article', '[role="main"]', '.main-content', 
                    '#main', '#content', '.content', '.post-content',
                    '.article-content', '.entry-content'
                ];
                
                var mainContent = "";
                for (var i = 0; i < contentSelectors.length; i++) {
                    var element = document.querySelector(contentSelectors[i]);
                    if (element && element.textContent) {
                        mainContent = element.textContent;
                        break;
                    }
                }
                
                // Use main content if found, otherwise fall back to body
                var finalText = mainContent || bodyText;
                
                // Clean up the text
                finalText = finalText
                    .replace(/\\s+/g, ' ')
                    .replace(/\\n+/g, '\\n')
                    .trim();
                
                return {
                    success: true,
                    text: finalText,
                    title: title,
                    url: url,
                    headings: headings.slice(0, 20), // Limit headings
                    links: links.slice(0, 10), // Limit links
                    wordCount: wordCount,
                    extractionTime: new Date().toISOString()
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
                    wordCount: 0
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