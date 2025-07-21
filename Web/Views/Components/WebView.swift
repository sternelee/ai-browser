import SwiftUI
import WebKit
import Combine
import Foundation
import AppKit

extension NSColor {
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        
        self.init(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            alpha: Double(a) / 255
        )
    }
}

extension NSImage {
    var isValid: Bool {
        return self.size.width > 0 && self.size.height > 0 && self.representations.count > 0
    }
}

struct WebView: NSViewRepresentable {
    @Binding var url: URL?
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var isLoading: Bool
    @Binding var estimatedProgress: Double
    @Binding var title: String?
    @Binding var favicon: NSImage?
    @Binding var hoveredLink: String?
    
    let tab: Tab?
    let onNavigationAction: ((WKNavigationAction) -> WKNavigationActionPolicy)?
    let onDownloadRequest: ((URL, String?) -> Void)?
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        
        // Enable advanced WebKit features with safety checks
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.isElementFullscreenEnabled = true
        config.preferences.isSiteSpecificQuirksModeEnabled = true
        
        // Network and security settings
        config.websiteDataStore = WKWebsiteDataStore.default()
        
        // Safely set developer extras
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        
        // Suppress verbose WebKit logging
        config.preferences.setValue(false, forKey: "logsPageMessagesToSystemConsoleEnabled")
        config.preferences.setValue(false, forKey: "diagnosticLoggingEnabled")
        
        // User agent customization - Use modern Safari user agent to ensure proper Google homepage rendering
        config.applicationNameForUserAgent = "Web/1.0 Safari/605.1.15"
        
        // Content blocking for ad blocker preparation
        let contentController = WKUserContentController()
        
        // Add link hover detection script
        let linkHoverScript = WKUserScript(
            source: linkHoverJavaScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        contentController.addUserScript(linkHoverScript)
        contentController.add(context.coordinator, name: "linkHover")
        
        config.userContentController = contentController
        
        // Create WebView with safe frame to prevent frame calculation issues
        let safeFrame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let webView = WKWebView(frame: safeFrame, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        
        // Configure for optimal web content including WebGL
        // Note: WebGL is enabled by default in WKWebView on macOS
        // These settings optimize the viewing experience
        webView.configuration.preferences.isElementFullscreenEnabled = true
        
        // Enable modern web features (JavaScript is enabled by default)
        // WebGL support is built into WebKit and doesn't require special configuration
        
        // Set up observers with error handling
        context.coordinator.setupObservers(for: webView)
        
        // Store webView reference for coordinator and tab
        context.coordinator.webView = webView
        if let tab = tab {
            tab.webView = webView
        }
        
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        // Only load if URL has actually changed from what we last attempted to load
        if let url = url {
            let lastLoadedURL = context.coordinator.lastLoadedURL
            let hasNeverLoaded = lastLoadedURL == nil
            let isDifferentURL = lastLoadedURL?.absoluteString != url.absoluteString
            
            // Only load if this is a genuinely new URL that we haven't attempted to load
            if hasNeverLoaded || isDifferentURL {
                let request = URLRequest(url: url)
                webView.load(request)
                
                // Store the URL in coordinator to track what we last attempted to load
                context.coordinator.lastLoadedURL = url
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // JavaScript for link hover detection
    private var linkHoverJavaScript: String {
        """
        (function() {
            let statusTimeout;
            
            // Add event listeners for link hover
            document.addEventListener('mouseover', function(e) {
                if (e.target.tagName === 'A' && e.target.href) {
                    clearTimeout(statusTimeout);
                    window.webkit.messageHandlers.linkHover.postMessage({
                        type: 'hover',
                        url: e.target.href
                    });
                }
            });
            
            document.addEventListener('mouseout', function(e) {
                if (e.target.tagName === 'A' && e.target.href) {
                    statusTimeout = setTimeout(() => {
                        window.webkit.messageHandlers.linkHover.postMessage({
                            type: 'clear'
                        });
                    }, 100);
                }
            });
        })();
        """
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let parent: WebView
        weak var webView: WKWebView?
        private var progressObserver: NSKeyValueObservation?
        private var titleObserver: NSKeyValueObservation?
        private var urlObserver: NSKeyValueObservation?
        var lastLoadedURL: URL?
        
        // Static shared cache to prevent duplicate downloads across all tabs
        private static var faviconCache: [String: NSImage] = [:]
        private static var faviconDownloadTasks: Set<String> = []
        private static let cacheQueue = DispatchQueue(label: "favicon.cache", attributes: .concurrent)
        
        init(_ parent: WebView) {
            self.parent = parent
        }
        
        func setupObservers(for webView: WKWebView) {
            progressObserver = webView.observe(\.estimatedProgress, options: .new) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    let progress = webView.estimatedProgress
                    
                    // Use safe progress conversion to prevent crashes
                    self?.parent.estimatedProgress = SafeNumericConversions.safeProgress(progress)
                }
            }
            
            titleObserver = webView.observe(\.title, options: .new) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.parent.title = webView.title
                }
            }
            
            urlObserver = webView.observe(\.url, options: .new) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    if let url = webView.url {
                        self?.parent.url = url
                        if let tab = self?.parent.tab {
                            tab.url = url
                        }
                    }
                }
            }
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
            parent.tab?.notifyLoadingStateChanged()
        }
        
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            // Update URL immediately when navigation commits (before page finishes loading)
            if let url = webView.url {
                DispatchQueue.main.async {
                    self.parent.url = url
                    if let tab = self.parent.tab {
                        tab.url = url
                    }
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            parent.title = webView.title
            parent.canGoBack = webView.canGoBack
            parent.canGoForward = webView.canGoForward
            parent.tab?.notifyLoadingStateChanged()
            
            // Only extract favicon if we don't have one for this domain
            if let currentURL = webView.url, let host = currentURL.host {
                Self.cacheQueue.sync {
                    
                    let hasCachedFavicon = Self.faviconCache[host] != nil
                    let isDownloading = Self.faviconDownloadTasks.contains(host)
                    
                    if !hasCachedFavicon && !isDownloading {
                        Self.faviconDownloadTasks.insert(host) // Mark as downloading immediately
                        
                        // Extract favicon with delay to ensure page is fully loaded
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.extractFavicon(from: webView, websiteHost: host)
                        }
                    } else if let cachedFavicon = Self.faviconCache[host] {
                        // Use cached favicon
                        DispatchQueue.main.async {
                            self.parent.favicon = cachedFavicon
                            if let tab = self.parent.tab {
                                tab.favicon = cachedFavicon
                            }
                        }
                    }
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            parent.tab?.notifyLoadingStateChanged()
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            parent.tab?.notifyLoadingStateChanged()
        }
        
        private func extractFavicon(from webView: WKWebView, websiteHost: String) {
            let script = """
            function getFaviconAndThemeColor() {
                try {
                    // Get theme color from meta tag
                    var themeColorMeta = document.querySelector('meta[name="theme-color"]');
                    var themeColor = themeColorMeta ? themeColorMeta.getAttribute('content') : null;
                    
                    // Get favicon with comprehensive preference order - improved selectors
                    var faviconSelectors = [
                        'link[rel="icon"][sizes="32x32"]',
                        'link[rel="icon"][sizes="16x16"]',
                        'link[rel="shortcut icon"]',
                        'link[rel="icon"]',
                        'link[rel="apple-touch-icon"][sizes="180x180"]',
                        'link[rel="apple-touch-icon"][sizes="152x152"]',
                        'link[rel="apple-touch-icon"]',
                        'link[rel="apple-touch-icon-precomposed"]',
                        'link[rel="mask-icon"]'
                    ];
                    
                    var faviconURL = null;
                    var foundElements = [];
                    
                    // Debug: collect all found elements
                    for (var i = 0; i < faviconSelectors.length; i++) {
                        var favicon = document.querySelector(faviconSelectors[i]);
                        if (favicon && favicon.href) {
                            foundElements.push({
                                selector: faviconSelectors[i],
                                href: favicon.href,
                                sizes: favicon.getAttribute('sizes')
                            });
                            if (!faviconURL) {
                                faviconURL = favicon.href;
                            }
                        }
                    }
                    
                    // Convert relative URLs to absolute
                    if (faviconURL && !faviconURL.startsWith('http')) {
                        if (faviconURL.startsWith('//')) {
                            faviconURL = window.location.protocol + faviconURL;
                        } else if (faviconURL.startsWith('/')) {
                            faviconURL = window.location.origin + faviconURL;
                        } else {
                            faviconURL = window.location.origin + '/' + faviconURL;
                        }
                    }
                    
                    // If no favicon found, try default locations
                    if (!faviconURL) {
                        faviconURL = window.location.origin + '/favicon.ico';
                    }
                    
                    return {
                        favicon: faviconURL,
                        themeColor: themeColor,
                        success: true,
                        debug: {
                            foundElements: foundElements,
                            finalURL: faviconURL,
                            origin: window.location.origin
                        }
                    };
                } catch (e) {
                    return {
                        favicon: window.location.origin + '/favicon.ico',
                        themeColor: null,
                        success: false,
                        error: e.toString()
                    };
                }
            }
            getFaviconAndThemeColor();
            """
            
            webView.evaluateJavaScript(script) { [weak self] result, error in
                if let error = error {
                    print("Favicon extraction error: \(error)")
                    // Try fallback immediately
                    let fallbackURL = URL(string: "https://\(websiteHost)/favicon.ico")
                    if let fallback = fallbackURL {
                        self?.downloadFavicon(from: fallback, websiteHost: websiteHost)
                    }
                    return
                }
                
                if let data = result as? [String: Any] {
                    if let faviconURL = data["favicon"] as? String, let url = URL(string: faviconURL) {
                        self?.downloadFavicon(from: url, websiteHost: websiteHost)
                    } else {
                        // Fallback: try to get favicon from website domain
                        let fallbackURL = URL(string: "https://\(websiteHost)/favicon.ico")
                        if let fallback = fallbackURL {
                            self?.downloadFavicon(from: fallback, websiteHost: websiteHost)
                        }
                    }
                    
                    if let themeColor = data["themeColor"] as? String {
                        self?.updateThemeColor(themeColor)
                    }
                }
            }
        }
        
        private func downloadFavicon(from url: URL, websiteHost: String) {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
            
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                defer {
                    // Always remove from download tasks when done using website host
                    Self.cacheQueue.async(flags: .barrier) {
                        Self.faviconDownloadTasks.remove(websiteHost)
                    }
                }
                
                if let error = error {
                    print("Favicon download error: \(error.localizedDescription)")
                    // If favicon download fails, try alternative fallbacks
                    self?.tryFaviconFallbacks(websiteHost: websiteHost)
                    return
                }
                
                guard let data = data else {
                    self?.tryFaviconFallbacks(websiteHost: websiteHost)
                    return
                }
                
                // Validate that we got a proper image
                if let image = NSImage(data: data), image.isValid {
                    // Cache the favicon using website host as key (not favicon URL host)
                    Self.cacheQueue.async(flags: .barrier) {
                        Self.faviconCache[websiteHost] = image
                    }
                    
                    DispatchQueue.main.async {
                        self?.parent.favicon = image
                        // Also update the tab model
                        if let tab = self?.parent.tab {
                            tab.favicon = image
                        }
                    }
                } else {
                    // Data was not a valid image, try fallbacks
                    self?.tryFaviconFallbacks(websiteHost: websiteHost)
                }
            }.resume()
        }
        
        private func tryFaviconFallbacks(websiteHost: String) {
            let fallbackURLs = [
                "https://\(websiteHost)/apple-touch-icon.png",
                "https://\(websiteHost)/favicon.png",
                "https://\(websiteHost)/favicon.gif",
                "https://www.google.com/s2/favicons?domain=\(websiteHost)&sz=32" // Google favicon service as last resort
            ]
            tryFaviconURL(from: fallbackURLs, index: 0, websiteHost: websiteHost)
        }
        
        private func tryFaviconURL(from urls: [String], index: Int, websiteHost: String) {
            guard index < urls.count, let url = URL(string: urls[index]) else { 
                return 
            }
            
            var request = URLRequest(url: url)
            request.timeoutInterval = 5
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
            
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                
                defer {
                    // Remove from download tasks when fallback completes using website host
                    Self.cacheQueue.async(flags: .barrier) {
                        Self.faviconDownloadTasks.remove(websiteHost)
                    }
                }
                
                if let error = error {
                    print("Fallback URL \(index + 1) failed: \(error.localizedDescription)")
                } else if let data = data, 
                          let image = NSImage(data: data),
                          image.isValid {
                    // Cache the favicon using website host as key
                    Self.cacheQueue.async(flags: .barrier) {
                        Self.faviconCache[websiteHost] = image
                    }
                    
                    DispatchQueue.main.async {
                        self?.parent.favicon = image
                        if let tab = self?.parent.tab {
                            tab.favicon = image
                        }
                    }
                    return // Success, don't try more fallbacks
                }
                
                // Try next fallback
                if index + 1 < urls.count {
                    self?.tryFaviconURL(from: urls, index: index + 1, websiteHost: websiteHost)
                }
            }.resume()
        }
        
        private func updateThemeColor(_ themeColorString: String) {
            DispatchQueue.main.async { [weak self] in
                if let color = self?.parseColor(from: themeColorString) {
                    // Update the tab's theme color
                    if let tab = self?.parent.tab {
                        tab.themeColor = color
                    }
                }
            }
        }
        
        private func parseColor(from colorString: String) -> NSColor? {
            let trimmed = colorString.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Handle hex colors
            if trimmed.hasPrefix("#") {
                let hex = String(trimmed.dropFirst())
                return NSColor(hex: hex)
            }
            
            // Handle rgb() colors
            if trimmed.hasPrefix("rgb(") && trimmed.hasSuffix(")") {
                let values = String(trimmed.dropFirst(4).dropLast())
                let components = values.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                if components.count == 3 {
                    return NSColor(red: components[0]/255.0, green: components[1]/255.0, blue: components[2]/255.0, alpha: 1.0)
                }
            }
            
            // Handle named colors (basic support)
            switch trimmed.lowercased() {
            case "blue": return .blue
            case "red": return .red
            case "green": return .green
            case "black": return .black
            case "white": return .white
            default: return nil
            }
        }
        
        // MARK: - Navigation policy handling
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let customAction = parent.onNavigationAction {
                let policy = customAction(navigationAction)
                decisionHandler(policy)
            } else {
                decisionHandler(.allow)
            }
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            // Check for downloads
            if let mimeType = navigationResponse.response.mimeType,
               !["text/html", "text/plain", "application/javascript", "text/css"].contains(mimeType) {
                // This is a download
                if let url = navigationResponse.response.url {
                    let filename = navigationResponse.response.suggestedFilename
                    parent.onDownloadRequest?(url, filename)
                }
                decisionHandler(.cancel)
                return
            }
            
            decisionHandler(.allow)
        }
        
        // MARK: - WKScriptMessageHandler
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "linkHover" {
                guard let body = message.body as? [String: Any] else { return }
                
                DispatchQueue.main.async {
                    if let type = body["type"] as? String {
                        switch type {
                        case "hover":
                            if let url = body["url"] as? String {
                                self.parent.hoveredLink = url
                            }
                        case "clear":
                            self.parent.hoveredLink = nil
                        default:
                            break
                        }
                    }
                }
            }
        }
        
        deinit {
            progressObserver?.invalidate()
            titleObserver?.invalidate()
            urlObserver?.invalidate()
        }
    }
}