import SwiftUI
import WebKit
import Combine

struct WebView: NSViewRepresentable {
    @Binding var url: URL?
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var isLoading: Bool
    @Binding var estimatedProgress: Double
    @Binding var title: String?
    @Binding var favicon: NSImage?
    
    let onNavigationAction: ((WKNavigationAction) -> WKNavigationActionPolicy)?
    let onDownloadRequest: ((URL, String?) -> Void)?
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        
        // Enable advanced WebKit features
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.isElementFullscreenEnabled = true
        config.preferences.isSiteSpecificQuirksModeEnabled = true
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        
        // User agent customization
        config.applicationNameForUserAgent = "Web/1.0"
        
        // Content blocking for ad blocker preparation
        let contentController = WKUserContentController()
        config.userContentController = contentController
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        
        // Enable GPU acceleration
        webView.configuration.preferences.setValue(true, forKey: "webgl2Enabled")
        webView.configuration.preferences.setValue(true, forKey: "webglEnabled")
        
        // Observe progress
        context.coordinator.setupObservers(for: webView)
        
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        if let url = url, webView.url != url {
            let request = URLRequest(url: url)
            webView.load(request)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let parent: WebView
        private var progressObserver: NSKeyValueObservation?
        private var titleObserver: NSKeyValueObservation?
        
        init(_ parent: WebView) {
            self.parent = parent
        }
        
        func setupObservers(for webView: WKWebView) {
            progressObserver = webView.observe(\.estimatedProgress, options: .new) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    let progress = webView.estimatedProgress
                    guard progress.isFinite else {
                        self?.parent.estimatedProgress = 0.0
                        return
                    }
                    self?.parent.estimatedProgress = min(max(progress, 0.0), 1.0)
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
            function getFavicon() {
                var favicon = document.querySelector('link[rel="shortcut icon"]') ||
                             document.querySelector('link[rel="icon"]') ||
                             document.querySelector('link[rel="apple-touch-icon"]');
                return favicon ? favicon.href : null;
            }
            getFavicon();
            """
            
            webView.evaluateJavaScript(script) { [weak self] result, error in
                if let faviconURL = result as? String, let url = URL(string: faviconURL) {
                    self?.downloadFavicon(from: url)
                }
            }
        }
        
        private func downloadFavicon(from url: URL) {
            URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
                if let data = data, let image = NSImage(data: data) {
                    DispatchQueue.main.async {
                        self?.parent.favicon = image
                    }
                }
            }.resume()
        }
        
        // MARK: - Download handling
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