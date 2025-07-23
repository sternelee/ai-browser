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
        // Use shared WebKitManager for optimized memory usage and shared process pool
        let isIncognito = tab?.isIncognito ?? false
        let config = WebKitManager.shared.createConfiguration(isIncognito: isIncognito)
        
        // Enhanced privacy settings specific to this app
        config.preferences.isFraudulentWebsiteWarningEnabled = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        
        // Safely set developer extras
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        
        // Enhanced WebKit privacy settings
        config.preferences.setValue(false, forKey: "logsPageMessagesToSystemConsoleEnabled")
        config.preferences.setValue(false, forKey: "diagnosticLoggingEnabled")
        config.preferences.setValue(true, forKey: "storageBlockingPolicy")
        
        // Configure enhanced tracking prevention
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        
        // User agent customization - Use standard Safari user agent to prevent Google's embedded browser detection
        config.applicationNameForUserAgent = ""
        
        // Add link hover detection and context menu script to existing user content controller
        let linkHoverScript = WKUserScript(
            source: linkHoverJavaScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(linkHoverScript)
        config.userContentController.add(context.coordinator, name: "linkHover")
        config.userContentController.add(context.coordinator, name: "linkContextMenu")
        
        // Add timer cleanup script to prevent memory leaks and CPU issues
        let timerCleanupScript = WKUserScript(
            source: timerCleanupJavaScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(timerCleanupScript)
        config.userContentController.add(context.coordinator, name: "timerCleanup")
        
        // Create WebView using WebKitManager for optimal memory usage
        let safeFrame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let webView = CustomWebView(frame: safeFrame, configuration: config, coordinator: context.coordinator)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        
        // Apply standard Safari user agent to prevent Google's embedded browser detection
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        
        // Configure security services after webview creation
        AdBlockService.shared.configureWebView(webView)
        DNSOverHTTPSService.shared.configureForWebKit()
        
        // Configure incognito-specific settings if needed
        if let tab = tab, tab.isIncognito {
            IncognitoSession.shared.configureWebViewForIncognito(webView)
            // Do NOT configure autofill for incognito tabs to maintain privacy
        } else {
            // Only configure autofill for regular (non-incognito) tabs
            PasswordManager.shared.configureAutofill(for: webView)
        }
        
        // Configure for optimal web content including WebGL
        // Note: WebGL is enabled by default in WKWebView on macOS
        // These settings optimize the viewing experience
        webView.configuration.preferences.isElementFullscreenEnabled = true
        
        // Enable modern web features (JavaScript is enabled by default)
        // WebGL support is built into WebKit and doesn't require special configuration
        
        // Set up observers with error handling
        context.coordinator.setupObservers(for: webView)
        
        // Store webView reference for coordinator and tab with ownership validation
        context.coordinator.webView = webView
        if let tab = tab {
            // CRITICAL: Ensure exclusive WebView ownership per tab
            if let existingWebView = tab.webView, existingWebView !== webView {
                print("⚠️ WARNING: Tab \(tab.id) already has a different WebView instance. This could cause content bleeding.")
            }
            tab.webView = webView
        }
        
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        // Smart navigation logic - only prevent rapid duplicate requests to same URL
        if let url = url {
            // Validate URL before proceeding
            guard !url.absoluteString.isEmpty else {
                print("⚠️ Attempted to load empty URL")
                return
            }
            
            let isCurrentlyDifferent = webView.url?.absoluteString != url.absoluteString
            let isNotCurrentlyLoading = !webView.isLoading
            
            // Only apply minimal debouncing for duplicate requests to the exact same URL
            let isDuplicateRequest = context.coordinator.lastLoadedURL?.absoluteString == url.absoluteString
            let now = Date()
            let timeSinceLastLoad = context.coordinator.lastLoadTime.map { now.timeIntervalSince($0) } ?? 1.0
            
            // Load if:
            // 1. URL is different (always allow new URLs)
            // 2. OR not currently loading
            // 3. OR if it's a duplicate request, only block if it happened very recently (< 100ms)
            let shouldLoad = isCurrentlyDifferent || 
                           isNotCurrentlyLoading || 
                           !isDuplicateRequest || 
                           timeSinceLastLoad > 0.1
            
            if shouldLoad {
                let request = URLRequest(url: url)
                webView.load(request)
                
                // Store the URL and timestamp in coordinator
                context.coordinator.lastLoadedURL = url
                context.coordinator.lastLoadTime = now
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // JavaScript for comprehensive timer cleanup to prevent CPU issues
    private var timerCleanupJavaScript: String {
        """
        (function() {
            'use strict';
            
            // Global timer registry to track all timers for cleanup
            window.webBrowserTimerRegistry = window.webBrowserTimerRegistry || {
                intervals: new Set(),
                timeouts: new Set(),
                originalSetInterval: window.setInterval,
                originalSetTimeout: window.setTimeout,
                originalClearInterval: window.clearInterval,
                originalClearTimeout: window.clearTimeout
            };
            
            const registry = window.webBrowserTimerRegistry;
            
            // Override setInterval to track all intervals
            window.setInterval = function(callback, delay, ...args) {
                const id = registry.originalSetInterval.call(this, callback, delay, ...args);
                registry.intervals.add(id);
                return id;
            };
            
            // Override setTimeout to track all timeouts
            window.setTimeout = function(callback, delay, ...args) {
                const id = registry.originalSetTimeout.call(this, callback, delay, ...args);
                registry.timeouts.add(id);
                return id;
            };
            
            // Override clearInterval to remove from tracking
            window.clearInterval = function(id) {
                registry.intervals.delete(id);
                return registry.originalClearInterval.call(this, id);
            };
            
            // Override clearTimeout to remove from tracking
            window.clearTimeout = function(id) {
                registry.timeouts.delete(id);
                return registry.originalClearTimeout.call(this, id);
            };
            
            // Global cleanup function
            window.cleanupAllTimers = function() {
                // Clear all tracked intervals
                registry.intervals.forEach(id => {
                    try {
                        registry.originalClearInterval.call(window, id);
                    } catch (e) {
                        console.warn('Failed to clear interval:', id, e);
                    }
                });
                registry.intervals.clear();
                
                // Clear all tracked timeouts
                registry.timeouts.forEach(id => {
                    try {
                        registry.originalClearTimeout.call(window, id);
                    } catch (e) {
                        console.warn('Failed to clear timeout:', id, e);
                    }
                });
                registry.timeouts.clear();
                
                // Clean up specific timers that might not be tracked
                if (window.adBlockStatsTimer) {
                    registry.originalClearInterval.call(window, window.adBlockStatsTimer);
                    window.adBlockStatsTimer = null;
                }
                
                if (window.passwordFormTimer) {
                    registry.originalClearInterval.call(window, window.passwordFormTimer);
                    window.passwordFormTimer = null;
                }
                
                if (window.incognitoStatsTimer) {
                    registry.originalClearInterval.call(window, window.incognitoStatsTimer);
                    window.incognitoStatsTimer = null;
                }
                
                if (window.formCheckTimeout) {
                    registry.originalClearTimeout.call(window, window.formCheckTimeout);
                    window.formCheckTimeout = null;
                }
                
                // Notify native code that cleanup is complete
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.timerCleanup) {
                    window.webkit.messageHandlers.timerCleanup.postMessage({
                        type: 'cleanupComplete',
                        intervalsCleared: registry.intervals.size,
                        timeoutsCleared: registry.timeouts.size
                    });
                }
            };
            
            // Only cleanup on actual navigation away from page, not visibility changes
            window.addEventListener('beforeunload', window.cleanupAllTimers);
            // Removed 'pagehide' event - too aggressive and interferes with focus management
            
        })();
        """
    }
    
    // JavaScript for link hover detection and right-click context menu
    private var linkHoverJavaScript: String {
        """
        (function() {
            let statusTimeout;
            let currentContextLink = null;
            
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
            
            // Handle right-click context menu on links
            document.addEventListener('contextmenu', function(e) {
                // Find if the clicked element or any parent is a link
                let target = e.target;
                let linkElement = null;
                
                // Traverse up the DOM to find a link element
                while (target && target !== document) {
                    if (target.tagName === 'A' && target.href) {
                        linkElement = target;
                        break;
                    }
                    target = target.parentElement;
                }
                
                if (linkElement) {
                    // Store current context link for potential actions
                    currentContextLink = linkElement.href;
                    
                    // Send link context to native code
                    window.webkit.messageHandlers.linkContextMenu.postMessage({
                        type: 'rightClick',
                        url: linkElement.href,
                        text: linkElement.textContent || linkElement.innerText || '',
                        x: e.clientX,
                        y: e.clientY
                    });
                } else {
                    // Clear context if not right-clicking on a link
                    currentContextLink = null;
                }
            });
            
            // Clear status bar when clicking on links
            document.addEventListener('click', function(e) {
                if (e.target.tagName === 'A' && e.target.href) {
                    clearTimeout(statusTimeout);
                    window.webkit.messageHandlers.linkHover.postMessage({
                        type: 'clear'
                    });
                }
            });
            
            // Also clear status bar on navigation start
            document.addEventListener('beforeunload', function() {
                window.webkit.messageHandlers.linkHover.postMessage({
                    type: 'clear'
                });
            });
            
            // Expose function for native code to get current context link
            window.getCurrentContextLink = function() {
                return currentContextLink;
            };
            
            // PERFORMANCE: Pause/resume expensive operations based on page visibility
            document.addEventListener('visibilitychange', function() {
                if (document.hidden) {
                    // Page is hidden - pause expensive operations
                    console.log('Page hidden - pausing expensive operations');
                } else {
                    // Page is visible - resume operations
                    console.log('Page visible - resuming operations');
                }
            });
        })();
        """
    }
    
    // MARK: - Custom WKWebView for Context Menu Support
    class CustomWebView: WKWebView {
        weak var coordinator: Coordinator?
        
        init(frame: CGRect, configuration: WKWebViewConfiguration, coordinator: Coordinator?) {
            self.coordinator = coordinator
            super.init(frame: frame, configuration: configuration)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
            super.willOpenMenu(menu, with: event)
            
            // Check if we have a right-clicked link URL from JavaScript
            guard let linkURL = coordinator?.rightClickedLinkURL,
                  let url = URL(string: linkURL) else {
                return // No link context, use default menu
            }
            
            // Find the "Open Link" menu item and add our custom item after it
            var insertIndex = 0
            for (index, menuItem) in menu.items.enumerated() {
                if menuItem.identifier?.rawValue == "WKMenuItemIdentifierOpenLink" {
                    insertIndex = index + 1
                    break
                }
            }
            
            // Create "Open in New Tab" menu item
            let openInNewTabItem = NSMenuItem(
                title: "Open in New Tab",
                action: #selector(openInNewTab(_:)),
                keyEquivalent: ""
            )
            openInNewTabItem.target = self
            openInNewTabItem.representedObject = url
            
            // Insert our custom menu item
            menu.insertItem(openInNewTabItem, at: insertIndex)
        }
        
        @objc private func openInNewTab(_ sender: NSMenuItem) {
            guard let url = sender.representedObject as? URL else { return }
            
            // Use the existing notification system to open in new background tab
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Notification.Name("newTabInBackgroundRequested"),
                    object: nil,
                    userInfo: ["url": url]
                )
            }
        }
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let parent: WebView
        weak var webView: WKWebView?
        private var progressObserver: NSKeyValueObservation?
        private var titleObserver: NSKeyValueObservation?
        private var urlObserver: NSKeyValueObservation?
        var lastLoadedURL: URL?
        var lastLoadTime: Date?
        
        // Context menu state
        var rightClickedLinkURL: String?
        
        // Network error handling and circuit breaker
        private let circuitBreaker = NetworkConnectivityMonitor.CircuitBreakerState()
        private var currentNetworkError: Error?
        private var isShowingNoInternetPage = false
        
        // Static shared cache to prevent duplicate downloads across all tabs
        private static var faviconCache: [String: NSImage] = [:]
        private static var faviconDownloadTasks: Set<String> = []
        private static let cacheQueue = DispatchQueue(label: "favicon.cache", attributes: .concurrent)
        private static let maxCacheSize = 50 // Reduced cache size to prevent memory issues
        private static var cacheAccessOrder: [String] = [] // LRU tracking
        
        init(_ parent: WebView) {
            self.parent = parent
        }
        
        func setupObservers(for webView: WKWebView) {
            progressObserver = webView.observe(\.estimatedProgress, options: .new) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    let progress = webView.estimatedProgress
                    
                    // Use safe progress conversion to prevent crashes
                    self?.parent.estimatedProgress = SafeNumericConversions.safeProgress(progress)
                    
                    // Update URLSynchronizer with progress changes for consistent state
                    if let tab = self?.parent.tab {
                        URLSynchronizer.shared.updateFromWebViewNavigation(
                            url: webView.url,
                            title: webView.title,
                            isLoading: webView.isLoading,
                            progress: progress,
                            tabID: tab.id
                        )
                    }
                }
            }
            
            titleObserver = webView.observe(\.title, options: .new) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.parent.title = webView.title
                    
                    // Update URLSynchronizer when title changes for better URL bar display
                    if let tab = self?.parent.tab {
                        URLSynchronizer.shared.updateFromWebViewNavigation(
                            url: webView.url,
                            title: webView.title,
                            isLoading: webView.isLoading,
                            progress: webView.estimatedProgress,
                            tabID: tab.id
                        )
                    }
                }
            }
            
            urlObserver = webView.observe(\.url, options: .new) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    if let url = webView.url {
                        self?.parent.url = url
                        if let tab = self?.parent.tab {
                            tab.url = url
                            // Update URLSynchronizer immediately for consistent URL display
                            URLSynchronizer.shared.updateFromWebViewNavigation(
                                url: url,
                                title: webView.title,
                                isLoading: webView.isLoading,
                                progress: webView.estimatedProgress,
                                tabID: tab.id
                            )
                        }
                    }
                }
            }
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
            parent.tab?.notifyLoadingStateChanged()
            
            // Update URLSynchronizer with loading state
            if let tab = parent.tab {
                URLSynchronizer.shared.updateFromWebViewNavigation(
                    url: webView.url,
                    title: webView.title,
                    isLoading: true,
                    progress: webView.estimatedProgress,
                    tabID: tab.id
                )
            }
        }
        
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            // CRITICAL: Update URL immediately when navigation commits (highest priority for URL bar updates)
            if let url = webView.url {
                DispatchQueue.main.async {
                    self.parent.url = url
                    if let tab = self.parent.tab {
                        tab.url = url
                        // Immediate URLSynchronizer update for instant URL bar display
                        URLSynchronizer.shared.updateFromWebViewNavigation(
                            url: url,
                            title: webView.title,
                            isLoading: webView.isLoading,
                            progress: webView.estimatedProgress,
                            tabID: tab.id
                        )
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
            
            // Reset network error state on successful navigation
            currentNetworkError = nil
            isShowingNoInternetPage = false
            circuitBreaker.recordSuccess()
            
            // Final URLSynchronizer update with completed navigation state
            if let tab = parent.tab {
                URLSynchronizer.shared.updateFromWebViewNavigation(
                    url: webView.url,
                    title: webView.title,
                    isLoading: false,
                    progress: 1.0,
                    tabID: tab.id
                )
            }
            
            // Record visit for Autofill history and browser history (only for non-incognito tabs)
            if let url = webView.url, parent.tab?.isIncognito != true {
                let title = webView.title ?? url.absoluteString
                AutofillService.shared.recordVisit(url: url.absoluteString, title: title)
                HistoryService.shared.recordVisit(url: url.absoluteString, title: webView.title)
            }
            
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
                        // Update LRU access order
                        Self.cacheAccessOrder.removeAll { $0 == host }
                        Self.cacheAccessOrder.append(host)
                        
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
            
            // AUTO-READ: Automatically extract page content for AI context
            // This provides comprehensive page content without user intervention
            if let currentURL = webView.url, 
               let scheme = currentURL.scheme?.lowercased(),
               (scheme == "http" || scheme == "https") {
                
                // Delay extraction to ensure page content is fully rendered
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    Task {
                        if let tab = self.parent.tab {
                            let context = await ContextManager.shared.extractPageContext(from: webView, tab: tab)
                            if let context = context {
                                NSLog("📖 Auto-read completed: \(context.text.count) characters from \(context.title)")
                            }
                            
                            // Notify that page navigation and context extraction has completed
                            await MainActor.run {
                                NotificationCenter.default.post(
                                    name: .pageNavigationCompleted,
                                    object: tab.id
                                )
                            }
                        }
                    }
                }
            } else {
                // For non-HTTP/HTTPS pages, still notify navigation completion
                NotificationCenter.default.post(
                    name: .pageNavigationCompleted,
                    object: parent.tab?.id
                )
            }
        }

        // CRITICAL FIX: Enhanced WebContent process termination handler with network awareness
        // and circuit breaker pattern to prevent infinite reload loops when offline.
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            NSLog("⚠️ WebContent process terminated")
            
            // Check if we have a URL to reload
            guard webView.url != nil else {
                NSLog("⚠️ WebContent process terminated but no URL to reload")
                return
            }
            
            // CRITICAL: Check network connectivity before attempting reload
            let networkMonitor = NetworkConnectivityMonitor.shared
            guard networkMonitor.hasInternetConnection else {
                NSLog("🔴 WebContent process terminated but no internet connection - showing no internet page instead of reloading")
                showNoInternetConnectionPage()
                return
            }
            
            // Check circuit breaker to prevent infinite reload loops
            guard circuitBreaker.canAttemptRequest() else {
                NSLog("🚫 Circuit breaker open - not attempting reload after process termination")
                showNoInternetConnectionPage()
                return
            }
            
            // Only reload if we have connectivity and circuit breaker allows it
            NSLog("🔄 WebContent process terminated – reloading tab (network available, circuit breaker closed)")
            
            // Add slight delay to prevent immediate re-termination
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                webView.reload()
                
                // Monitor the reload attempt
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                    // If still loading after 5 seconds and we have network issues, consider it a failure
                    if webView.isLoading && !NetworkConnectivityMonitor.shared.hasInternetConnection {
                        self?.circuitBreaker.recordFailure()
                        self?.showNoInternetConnectionPage()
                    }
                }
            }
        }
        
        // Show the no internet connection page when network issues are detected
        private func showNoInternetConnectionPage() {
            guard !isShowingNoInternetPage else { return }
            
            isShowingNoInternetPage = true
            circuitBreaker.recordFailure()
            
            DispatchQueue.main.async { [weak self] in
                // Create and show the no internet page
                NotificationCenter.default.post(
                    name: .showNoInternetConnection,
                    object: self?.parent.tab?.id,
                    userInfo: [
                        "error": self?.currentNetworkError as Any,
                        "url": self?.parent.url as Any
                    ]
                )
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            let networkMonitor = NetworkConnectivityMonitor.shared
            
            // Classify the error type for appropriate handling
            let errorType = networkMonitor.classifyError(error)
            let isNetworkError = networkMonitor.isNetworkError(error)
            
            NSLog("❌ WebView navigation failed: \(error.localizedDescription) (code: \(nsError.code), type: \(errorType))")
            
            parent.isLoading = false
            parent.tab?.notifyLoadingStateChanged()
            currentNetworkError = error
            
            // Update URLSynchronizer with error state
            if let tab = parent.tab {
                URLSynchronizer.shared.updateFromWebViewNavigation(
                    url: webView.url,
                    title: webView.title,
                    isLoading: false,
                    progress: 0.0,
                    tabID: tab.id
                )
            }
            
            // Handle network errors specifically
            if isNetworkError {
                circuitBreaker.recordFailure()
                
                // Show no internet page for network connectivity issues
                if errorType == .networkUnavailable || !networkMonitor.hasInternetConnection {
                    showNoInternetConnectionPage()
                }
            } else {
                // For non-network errors, reset circuit breaker on successful connectivity
                if networkMonitor.hasInternetConnection {
                    circuitBreaker.recordSuccess()
                    isShowingNoInternetPage = false
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            let errorCode = nsError.code
            let networkMonitor = NetworkConnectivityMonitor.shared
            
            // Don't process NSURLErrorCancelled (-999) as it's expected behavior
            guard errorCode != NSURLErrorCancelled else {
                parent.isLoading = false
                parent.tab?.notifyLoadingStateChanged()
                return
            }
            
            // Classify the error type for appropriate handling
            let errorType = networkMonitor.classifyError(error)
            let isNetworkError = networkMonitor.isNetworkError(error)
            
            NSLog("❌ WebView provisional navigation failed: \(error.localizedDescription) (code: \(errorCode), type: \(errorType))")
            
            parent.isLoading = false
            parent.tab?.notifyLoadingStateChanged()
            currentNetworkError = error
            
            // Update URLSynchronizer with error state
            if let tab = parent.tab {
                URLSynchronizer.shared.updateFromWebViewNavigation(
                    url: webView.url,
                    title: webView.title,
                    isLoading: false,
                    progress: 0.0,
                    tabID: tab.id
                )
            }
            
            // Handle network errors specifically - provisional navigation failures are often network-related
            if isNetworkError {
                circuitBreaker.recordFailure()
                
                // Show no internet page for network connectivity issues
                if errorType == .networkUnavailable || !networkMonitor.hasInternetConnection {
                    showNoInternetConnectionPage()
                } else if errorType == .timeout || errorType == .dnsFailure {
                    // For timeouts and DNS failures, show no internet page if we detect no connectivity
                    if !networkMonitor.hasInternetConnection {
                        showNoInternetConnectionPage()
                    }
                }
            } else {
                // For non-network errors, reset circuit breaker if we have good connectivity
                if networkMonitor.hasInternetConnection {
                    circuitBreaker.recordSuccess()
                    isShowingNoInternetPage = false
                }
            }
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
                    // Cache the favicon using website host as key with LRU eviction
                    Self.cacheQueue.async(flags: .barrier) {
                        // Clean cache using LRU if it gets too large
                        if Self.faviconCache.count >= Self.maxCacheSize {
                            let removeCount = Self.faviconCache.count - Self.maxCacheSize + 10
                            let keysToRemove = Array(Self.cacheAccessOrder.prefix(removeCount))
                            for key in keysToRemove {
                                Self.faviconCache.removeValue(forKey: key)
                                Self.cacheAccessOrder.removeAll { $0 == key }
                            }
                        }
                        
                        // Update cache and access order
                        Self.faviconCache[websiteHost] = image
                        Self.cacheAccessOrder.removeAll { $0 == websiteHost }
                        Self.cacheAccessOrder.append(websiteHost)
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
                    // Cache the favicon using website host as key with LRU eviction
                    Self.cacheQueue.async(flags: .barrier) {
                        // Clean cache using LRU if it gets too large
                        if Self.faviconCache.count >= Self.maxCacheSize {
                            let removeCount = Self.faviconCache.count - Self.maxCacheSize + 10
                            let keysToRemove = Array(Self.cacheAccessOrder.prefix(removeCount))
                            for key in keysToRemove {
                                Self.faviconCache.removeValue(forKey: key)
                                Self.cacheAccessOrder.removeAll { $0 == key }
                            }
                        }
                        
                        // Update cache and access order
                        Self.faviconCache[websiteHost] = image
                        Self.cacheAccessOrder.removeAll { $0 == websiteHost }
                        Self.cacheAccessOrder.append(websiteHost)
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
            // Check for CMD + click to open links in new background tabs
            if navigationAction.navigationType == .linkActivated,
               navigationAction.modifierFlags.contains(.command),
               let targetURL = navigationAction.request.url {
                
                // Create new tab in background using NotificationCenter
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: Notification.Name("newTabInBackgroundRequested"),
                        object: nil,
                        userInfo: ["url": targetURL]
                    )
                }
                
                // Cancel navigation in current tab
                decisionHandler(.cancel)
                return
            }
            
            if let customAction = parent.onNavigationAction {
                let policy = customAction(navigationAction)
                decisionHandler(policy)
            } else {
                decisionHandler(.allow)
            }
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            // Check for downloads using enhanced DownloadManager
            if DownloadManager.shared.shouldDownloadResponse(navigationResponse.response) {
                if let url = navigationResponse.response.url {
                    let filename = navigationResponse.response.suggestedFilename ?? url.lastPathComponent
                    
                    // Start download using DownloadManager
                    DownloadManager.shared.startDownload(from: url, suggestedFilename: filename)
                    
                    // Also call legacy callback if present
                    parent.onDownloadRequest?(url, filename)
                }
                decisionHandler(.cancel)
                return
            }
            
            decisionHandler(.allow)
        }
        
        // MARK: - WKScriptMessageHandler
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "linkHover":
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
                
            case "linkContextMenu":
                guard let body = message.body as? [String: Any] else { return }
                
                DispatchQueue.main.async {
                    if let type = body["type"] as? String {
                        switch type {
                        case "rightClick":
                            if let url = body["url"] as? String {
                                self.rightClickedLinkURL = url
                                // The context menu will be shown by WKUIDelegate method
                            }
                        default:
                            break
                        }
                    }
                }
                
            case "timerCleanup":
                guard let body = message.body as? [String: Any],
                      let type = body["type"] as? String else { return }
                
                if type == "cleanupComplete" {
                    let intervalsCleared = body["intervalsCleared"] as? Int ?? 0
                    let timeoutsCleared = body["timeoutsCleared"] as? Int ?? 0
                    print("✅ Timer cleanup completed - Intervals: \(intervalsCleared), Timeouts: \(timeoutsCleared)")
                }
                
            default:
                break
            }
        }
        
        // MARK: - WKUIDelegate
        // Note: Context menu customization is handled in CustomWebView subclass
        
        // MARK: - Public Methods for Timer Management
        func cleanupWebViewTimers() {
            guard let webView = webView else { return }
            
            // Execute JavaScript timer cleanup
            webView.evaluateJavaScript("if (window.cleanupAllTimers) { window.cleanupAllTimers(); }") { result, error in
                if let error = error {
                    print("⚠️ Timer cleanup error: \(error.localizedDescription)")
                } else {
                    print("🧹 WebView timer cleanup executed successfully")
                }
            }
        }
        
        deinit {
            // Comprehensive cleanup to prevent memory leaks
            progressObserver?.invalidate()
            titleObserver?.invalidate()
            urlObserver?.invalidate()
            progressObserver = nil
            titleObserver = nil
            urlObserver = nil
            
            // Clean up WebView references
            if let webView = webView {
                webView.navigationDelegate = nil
                webView.uiDelegate = nil
                webView.configuration.userContentController.removeAllUserScripts()
                
                // Clean up JavaScript timers before removing handlers
                webView.evaluateJavaScript("if (window.cleanupAllTimers) { window.cleanupAllTimers(); }")
                
                // Remove script message handlers
                webView.configuration.userContentController.removeScriptMessageHandler(forName: "linkHover")
                webView.configuration.userContentController.removeScriptMessageHandler(forName: "linkContextMenu")
                webView.configuration.userContentController.removeScriptMessageHandler(forName: "timerCleanup")
                webView.configuration.userContentController.removeScriptMessageHandler(forName: "adBlockHandler")
                webView.configuration.userContentController.removeScriptMessageHandler(forName: "autofillHandler")
                webView.configuration.userContentController.removeScriptMessageHandler(forName: "incognitoHandler")
                
                self.webView = nil
            }
        }
    }
}