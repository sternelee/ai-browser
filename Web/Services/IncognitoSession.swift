import WebKit
import Network
import Foundation

class IncognitoSession: NSObject, ObservableObject {
    static let shared = IncognitoSession()
    
    @Published var isActive: Bool = false
    @Published var incognitoTabs: [Tab] = []
    @Published var totalBlockedTrackers: Int = 0
    
    private var incognitoWebViewConfiguration: WKWebViewConfiguration?
    private var privateDataStore: WKWebsiteDataStore?
    private var sessionStartTime: Date?
    
    override init() {
        super.init()
        setupIncognitoConfiguration()
        setupNotificationObservers()
    }
    
    // MARK: - Configuration Setup
    private func setupIncognitoConfiguration() {
        privateDataStore = WKWebsiteDataStore.nonPersistent()
        
        let config = WKWebViewConfiguration()
        config.websiteDataStore = privateDataStore!
        
        // Enhanced privacy settings for incognito mode
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.allowsAirPlayForMediaPlayback = false
        config.preferences.isFraudulentWebsiteWarningEnabled = true
        
        // Disable various storage mechanisms - using only valid WKPreferences keys
        // Note: WebRTC blocking is handled in JavaScript injection instead of invalid preference key
        
        // Enhanced tracking prevention
        if #available(macOS 14.0, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
            config.defaultWebpagePreferences.preferredContentMode = .desktop
        }
        
        // SECURITY: Add CSP-protected privacy JavaScript
        let privacyScript = generatePrivacyEnhancementScript()
        if let secureScript = CSPManager.shared.secureScriptInjection(
            script: privacyScript,
            type: .incognito,
            webView: WKWebView(frame: .zero, configuration: config)
        ) {
            config.userContentController.addUserScript(secureScript)
        }
        
        incognitoWebViewConfiguration = config
    }
    
    private func generatePrivacyEnhancementScript() -> String {
        return """
        (function() {
            'use strict';
            
            // Enhanced tracking prevention for incognito mode
            let blockedRequests = 0;
            
            // Override navigator properties that could be used for fingerprinting
            Object.defineProperty(navigator, 'webdriver', {
                get: () => undefined
            });
            
            // Block common tracking APIs
            const trackingAPIs = [
                'sendBeacon',
                'requestIdleCallback'
            ];
            
            trackingAPIs.forEach(api => {
                if (navigator[api]) {
                    navigator[api] = function() {
                        console.log(`Blocked tracking API: ${api}`);
                        blockedRequests++;
                        return false;
                    };
                }
            });
            
            // Override geolocation to prevent location tracking
            if (navigator.geolocation) {
                navigator.geolocation.getCurrentPosition = function(success, error) {
                    if (error) {
                        error({
                            code: 1,
                            message: "User denied geolocation request"
                        });
                    }
                };
                
                navigator.geolocation.watchPosition = function(success, error) {
                    if (error) {
                        error({
                            code: 1,
                            message: "User denied geolocation request"
                        });
                    }
                    return -1;
                };
            }
            
            // Block canvas fingerprinting
            const originalGetContext = HTMLCanvasElement.prototype.getContext;
            HTMLCanvasElement.prototype.getContext = function(type, ...args) {
                if (type === '2d' || type === 'webgl' || type === 'webgl2') {
                    const context = originalGetContext.apply(this, [type, ...args]);
                    if (context) {
                        // Add noise to prevent fingerprinting
                        const originalGetImageData = context.getImageData;
                        if (originalGetImageData) {
                            context.getImageData = function(...args) {
                                const imageData = originalGetImageData.apply(this, args);
                                // Add minimal noise to prevent fingerprinting
                                for (let i = 0; i < imageData.data.length; i += 4) {
                                    imageData.data[i] += Math.floor(Math.random() * 3) - 1;
                                    imageData.data[i + 1] += Math.floor(Math.random() * 3) - 1;
                                    imageData.data[i + 2] += Math.floor(Math.random() * 3) - 1;
                                }
                                return imageData;
                            };
                        }
                    }
                    return context;
                }
                return originalGetContext.apply(this, [type, ...args]);
            };
            
            // Block WebRTC IP leaks
            if (window.RTCPeerConnection) {
                window.RTCPeerConnection = function() {
                    throw new Error('WebRTC is disabled in incognito mode');
                };
            }
            
            if (window.webkitRTCPeerConnection) {
                window.webkitRTCPeerConnection = function() {
                    throw new Error('WebRTC is disabled in incognito mode');
                };
            }
            
            // Enhanced cookie blocking
            Object.defineProperty(document, 'cookie', {
                get: function() {
                    return '';
                },
                set: function() {
                    return false;
                }
            });
            
            // Block localStorage and sessionStorage
            const storageHandler = {
                get: function() {
                    throw new Error('Storage is disabled in incognito mode');
                },
                set: function() {
                    throw new Error('Storage is disabled in incognito mode');
                }
            };
            
            try {
                Object.defineProperty(window, 'localStorage', storageHandler);
                Object.defineProperty(window, 'sessionStorage', storageHandler);
            } catch (e) {
                // Properties might already be defined
            }
            
            // Use shared timer for incognito tracking stats to reduce CPU usage
            // CRITICAL: Increased interval to prevent Google CPU issues in incognito mode
            window.incognitoStatsTimer = window.incognitoStatsTimer || setInterval(() => {
                // Skip if page is hidden to save CPU (especially important for Google in incognito)
                if (document.hidden) return;
                
                if (blockedRequests > 0 && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.incognitoHandler) {
                    window.webkit.messageHandlers.incognitoHandler.postMessage({
                        type: 'trackingBlocked',
                        count: blockedRequests
                    });
                    blockedRequests = 0;
                }
            }, 30000); // Increased from 15s to 30s to prevent Google search CPU spikes in incognito
            
            // Cleanup timer on page unload
            window.addEventListener('beforeunload', () => {
                if (window.incognitoStatsTimer) {
                    clearInterval(window.incognitoStatsTimer);
                    window.incognitoStatsTimer = null;
                }
            });
            
        })();
        """
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNewIncognitoTab),
            name: .newIncognitoTabRequested,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCloseIncognitoTab),
            name: .closeIncognitoTabRequested,
            object: nil
        )
    }
    
    // MARK: - Session Management
    func createIncognitoTab(url: URL? = nil) -> Tab {
        let tab = Tab(url: url, isIncognito: true)
        incognitoTabs.append(tab)
        
        if !isActive {
            startIncognitoSession()
        }
        
        return tab
    }
    
    func closeIncognitoTab(_ tab: Tab) {
        incognitoTabs.removeAll { $0.id == tab.id }
        
        // Clear tab's web view if it exists
        if let webView = tab.webView {
            clearWebViewData(webView)
        }
        
        if incognitoTabs.isEmpty {
            endIncognitoSession()
        }
    }
    
    private func startIncognitoSession() {
        isActive = true
        sessionStartTime = Date()
        totalBlockedTrackers = 0
        
        print("🥷 Incognito session started with enhanced privacy protection")
    }
    
    func endIncognitoSession() {
        incognitoTabs.removeAll()
        
        if let dataStore = privateDataStore {
            let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
            dataStore.removeData(ofTypes: dataTypes, modifiedSince: Date.distantPast) { }
        }
        
        isActive = false
        
        if let startTime = sessionStartTime {
            let duration = Date().timeIntervalSince(startTime)
            print("🥷 Incognito session ended - Duration: \(Int(duration))s, Blocked trackers: \(totalBlockedTrackers)")
        }
        
        sessionStartTime = nil
        totalBlockedTrackers = 0
        
        setupIncognitoConfiguration()
    }
    
    private func clearWebViewData(_ webView: WKWebView) {
        let dataStore = webView.configuration.websiteDataStore
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        dataStore.removeData(ofTypes: dataTypes, modifiedSince: Date.distantPast) { }
    }
    
    // MARK: - Configuration Access
    func getIncognitoConfiguration() -> WKWebViewConfiguration? {
        return incognitoWebViewConfiguration
    }
    
    func configureWebViewForIncognito(_ webView: WKWebView) {
        // SECURITY: CSP protection is already applied during configuration setup
        webView.configuration.userContentController.add(self, name: "incognitoHandler")
        
        // Additional incognito-specific configuration
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Version/18.0 Safari/537.36"
        
        // Disable caching for incognito tabs
        webView.configuration.websiteDataStore.removeData(
            ofTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache],
            modifiedSince: Date.distantPast
        ) { }
    }
    
    // MARK: - Statistics
    func getSessionStatistics() -> IncognitoSessionStats {
        let duration = sessionStartTime?.timeIntervalSinceNow.magnitude ?? 0
        
        return IncognitoSessionStats(
            isActive: isActive,
            duration: duration,
            tabCount: incognitoTabs.count,
            blockedTrackers: totalBlockedTrackers,
            dataStoreType: "Non-Persistent"
        )
    }
    
    struct IncognitoSessionStats {
        let isActive: Bool
        let duration: TimeInterval
        let tabCount: Int
        let blockedTrackers: Int
        let dataStoreType: String
    }
    
    // MARK: - Notification Handlers
    @objc private func handleNewIncognitoTab(_ notification: Notification) {
        if let url = notification.object as? URL {
            _ = createIncognitoTab(url: url)
        } else {
            _ = createIncognitoTab()
        }
    }
    
    @objc private func handleCloseIncognitoTab(_ notification: Notification) {
        if let tab = notification.object as? Tab {
            closeIncognitoTab(tab)
        }
    }
}

// MARK: - Script Message Handler (CSP-Protected)
extension IncognitoSession: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let validationResult = CSPManager.shared.validateMessageInput(message, expectedHandler: "incognitoHandler")
        
        switch validationResult {
        case .valid(let sanitizedBody):
            guard let type = sanitizedBody["type"] as? String else { return }
            
            DispatchQueue.main.async {
                switch type {
                case "trackingBlocked":
                    if let count = sanitizedBody["count"] as? Int {
                        self.totalBlockedTrackers += count
                    }
                    
                default:
                    break
                }
            }
            
        case .invalid(let error):
            NSLog("🔒 CSP: Incognito message validation failed: \(error.description)")
        }
    }
}

// MARK: - Notification Extensions
extension Notification.Name {
    static let newIncognitoTabRequested = Notification.Name("newIncognitoTabRequested")
    static let closeIncognitoTabRequested = Notification.Name("closeIncognitoTabRequested")
}