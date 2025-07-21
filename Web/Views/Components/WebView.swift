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
        
        // User agent customization
        config.applicationNameForUserAgent = "Web/1.0"
        
        // Content blocking for ad blocker preparation
        let contentController = WKUserContentController()
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
        // Only load if URL is different and not currently loading
        if let url = url, webView.url != url, !webView.isLoading {
            let request = URLRequest(url: url)
            webView.load(request)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let parent: WebView
        weak var webView: WKWebView?
        private var progressObserver: NSKeyValueObservation?
        private var titleObserver: NSKeyValueObservation?
        
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
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            parent.title = webView.title
            parent.canGoBack = webView.canGoBack
            parent.canGoForward = webView.canGoForward
            
            // Extract favicon
            extractFavicon(from: webView)
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }
        
        private func extractFavicon(from webView: WKWebView) {
            let script = """
            function getFaviconAndThemeColor() {
                try {
                    // Get theme color from meta tag
                    var themeColorMeta = document.querySelector('meta[name="theme-color"]');
                    var themeColor = themeColorMeta ? themeColorMeta.getAttribute('content') : null;
                    
                    // Get favicon with comprehensive preference order
                    var faviconSelectors = [
                        'link[rel*="icon"][sizes="32x32"]',
                        'link[rel*="icon"][sizes="16x16"]', 
                        'link[rel="shortcut icon"]',
                        'link[rel="icon"]',
                        'link[rel="apple-touch-icon"]',
                        'link[rel="apple-touch-icon-precomposed"]',
                        'link[rel="mask-icon"]'
                    ];
                    
                    var faviconURL = null;
                    for (var i = 0; i < faviconSelectors.length; i++) {
                        var favicon = document.querySelector(faviconSelectors[i]);
                        if (favicon && favicon.href) {
                            faviconURL = favicon.href;
                            break;
                        }
                    }
                    
                    // If no favicon found, try default locations
                    if (!faviconURL) {
                        var defaultLocations = [
                            '/favicon.ico',
                            '/favicon.png', 
                            '/apple-touch-icon.png'
                        ];
                        faviconURL = window.location.origin + defaultLocations[0];
                    }
                    
                    return {
                        favicon: faviconURL,
                        themeColor: themeColor,
                        success: true
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
                if let data = result as? [String: Any] {
                    if let faviconURL = data["favicon"] as? String, let url = URL(string: faviconURL) {
                        self?.downloadFavicon(from: url)
                    } else {
                        // Fallback: try to get favicon from current URL's domain
                        if let currentURL = webView.url {
                            let fallbackURL = URL(string: "\(currentURL.scheme!)://\(currentURL.host!)/favicon.ico")
                            if let fallback = fallbackURL {
                                self?.downloadFavicon(from: fallback)
                            }
                        }
                    }
                    
                    if let themeColor = data["themeColor"] as? String {
                        self?.updateThemeColor(themeColor)
                    }
                }
            }
        }
        
        private func downloadFavicon(from url: URL) {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
            
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                guard let data = data, error == nil else {
                    // If favicon download fails, try alternative fallbacks
                    self?.tryFaviconFallbacks(originalURL: url)
                    return
                }
                
                // Validate that we got a proper image
                if let image = NSImage(data: data), image.isValid {
                    DispatchQueue.main.async {
                        self?.parent.favicon = image
                        // Also update the tab model
                        if let tab = self?.parent.tab {
                            tab.favicon = image
                        }
                    }
                } else {
                    // Data was not a valid image, try fallbacks
                    self?.tryFaviconFallbacks(originalURL: url)
                }
            }.resume()
        }
        
        private func tryFaviconFallbacks(originalURL: URL) {
            guard let host = originalURL.host else { return }
            
            let fallbackURLs = [
                "https://\(host)/apple-touch-icon.png",
                "https://\(host)/favicon.png",
                "https://\(host)/favicon.gif",
                "https://www.google.com/s2/favicons?domain=\(host)&sz=32" // Google favicon service as last resort
            ]
            
            tryFaviconURL(from: fallbackURLs, index: 0)
        }
        
        private func tryFaviconURL(from urls: [String], index: Int) {
            guard index < urls.count, let url = URL(string: urls[index]) else { return }
            
            var request = URLRequest(url: url)
            request.timeoutInterval = 5
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
            
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                if let data = data, 
                   let image = NSImage(data: data),
                   image.isValid {
                    DispatchQueue.main.async {
                        self?.parent.favicon = image
                        if let tab = self?.parent.tab {
                            tab.favicon = image
                        }
                    }
                } else if index + 1 < urls.count {
                    // Try next fallback
                    self?.tryFaviconURL(from: urls, index: index + 1)
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
        
        deinit {
            progressObserver?.invalidate()
            titleObserver?.invalidate()
        }
    }
}