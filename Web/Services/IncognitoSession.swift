// IncognitoSession.swift - Enhanced private browsing implementation
import WebKit
import Network
import SwiftUI

class IncognitoSession: ObservableObject {
    static let shared = IncognitoSession()
    
    @Published var isActive: Bool = false
    @Published var incognitoTabs: [Tab] = []
    
    private var incognitoWebViewConfiguration: WKWebViewConfiguration?
    private var privateDataStore: WKWebsiteDataStore?
    
    init() {
        setupIncognitoConfiguration()
    }
    
    private func setupIncognitoConfiguration() {
        // Create non-persistent data store
        privateDataStore = WKWebsiteDataStore.nonPersistent()
        
        // Configure incognito WebView
        let config = WKWebViewConfiguration()
        config.websiteDataStore = privateDataStore!
        
        // Disable various tracking and storage mechanisms
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.allowsAirPlayForMediaPlayback = false
        
        // Enhanced privacy settings
        if #available(macOS 14.0, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
            config.defaultWebpagePreferences.preferredContentMode = .desktop
        }
        
        // Disable persistence
        config.processPool = WKProcessPool() // Isolated process pool
        
        incognitoWebViewConfiguration = config
    }
    
    func createIncognitoTab(url: URL? = nil) -> Tab {
        let tab = Tab(url: url, isIncognito: true)
        incognitoTabs.append(tab)
        
        if !isActive {
            isActive = true
        }
        
        return tab
    }
    
    func closeIncognitoTab(_ tab: Tab) {
        incognitoTabs.removeAll { $0.id == tab.id }
        
        if incognitoTabs.isEmpty {
            endIncognitoSession()
        }
    }
    
    func endIncognitoSession() {
        // Clear all incognito tabs
        incognitoTabs.removeAll()
        
        // Clear private data store
        if let dataStore = privateDataStore {
            let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
            dataStore.removeData(ofTypes: dataTypes, modifiedSince: Date.distantPast) { }
        }
        
        isActive = false
        
        // Recreate configuration for next session
        setupIncognitoConfiguration()
        
        print("Incognito session ended - all private data cleared")
    }
    
    func getIncognitoConfiguration() -> WKWebViewConfiguration? {
        return incognitoWebViewConfiguration
    }
    
    // MARK: - Privacy Features
    func configurePrivateWebView(_ webView: WKWebView) {
        guard let config = incognitoWebViewConfiguration else { return }
        
        // Enhanced privacy JavaScript injection
        let privacyScript = generatePrivacyScript()
        let script = WKUserScript(source: privacyScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(script)
        
        // Disable referrer
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        
        // Additional privacy configurations
        if #available(macOS 14.0, *) {
            config.preferences.isElementFullscreenEnabled = false
            config.preferences.isFraudulentWebsiteWarningEnabled = true
        }
    }
    
    private func generatePrivacyScript() -> String {
        return """
        (function() {
            'use strict';
            
            // Disable various tracking APIs
            const originalAddEventListener = EventTarget.prototype.addEventListener;
            const originalSetItem = Storage.prototype.setItem;
            const originalGetItem = Storage.prototype.getItem;
            
            // Block storage APIs
            Storage.prototype.setItem = function(key, value) {
                // Block in incognito
                return;
            };
            
            Storage.prototype.getItem = function(key) {
                // Return null in incognito
                return null;
            };
            
            // Override geolocation
            if (navigator.geolocation) {
                navigator.geolocation.getCurrentPosition = function(success, error) {
                    if (error) {
                        error({
                            code: 1,
                            message: "Location access denied in private browsing"
                        });
                    }
                };
                
                navigator.geolocation.watchPosition = function(success, error) {
                    if (error) {
                        error({
                            code: 1,
                            message: "Location access denied in private browsing"
                        });
                    }
                };
            }
            
            // Block device APIs
            if (navigator.mediaDevices) {
                navigator.mediaDevices.getUserMedia = function() {
                    return Promise.reject(new Error("Media access denied in private browsing"));
                };
                
                navigator.mediaDevices.enumerateDevices = function() {
                    return Promise.resolve([]);
                };
            }
            
            // Block notifications
            if (window.Notification) {
                window.Notification.requestPermission = function() {
                    return Promise.resolve("denied");
                };
                
                window.Notification.permission = "denied";
            }
            
            // Block push notifications
            if (navigator.serviceWorker) {
                navigator.serviceWorker.register = function() {
                    return Promise.reject(new Error("Service Workers disabled in private browsing"));
                };
            }
            
            // Override screen properties to reduce fingerprinting
            Object.defineProperty(screen, 'width', {
                get: function() { return 1920; }
            });
            
            Object.defineProperty(screen, 'height', {
                get: function() { return 1080; }
            });
            
            Object.defineProperty(screen, 'availWidth', {
                get: function() { return 1920; }
            });
            
            Object.defineProperty(screen, 'availHeight', {
                get: function() { return 1040; }
            });
            
            // Block WebRTC
            if (window.RTCPeerConnection) {
                window.RTCPeerConnection = undefined;
            }
            if (window.webkitRTCPeerConnection) {
                window.webkitRTCPeerConnection = undefined;
            }
            if (window.mozRTCPeerConnection) {
                window.mozRTCPeerConnection = undefined;
            }
            
            // Block Battery API
            if (navigator.getBattery) {
                navigator.getBattery = function() {
                    return Promise.reject(new Error("Battery API disabled in private browsing"));
                };
            }
            
            // Override timezone to UTC
            if (Intl && Intl.DateTimeFormat) {
                const originalResolvedOptions = Intl.DateTimeFormat.prototype.resolvedOptions;
                Intl.DateTimeFormat.prototype.resolvedOptions = function() {
                    const options = originalResolvedOptions.call(this);
                    options.timeZone = 'UTC';
                    return options;
                };
            }
            
            // Override language to reduce fingerprinting
            Object.defineProperty(navigator, 'language', {
                get: function() { return 'en-US'; }
            });
            
            Object.defineProperty(navigator, 'languages', {
                get: function() { return ['en-US', 'en']; }
            });
            
            // Block canvas fingerprinting
            const originalToDataURL = HTMLCanvasElement.prototype.toDataURL;
            const originalGetImageData = CanvasRenderingContext2D.prototype.getImageData;
            
            HTMLCanvasElement.prototype.toDataURL = function() {
                // Return blank canvas data
                const canvas = document.createElement('canvas');
                canvas.width = this.width;
                canvas.height = this.height;
                return originalToDataURL.call(canvas);
            };
            
            CanvasRenderingContext2D.prototype.getImageData = function() {
                // Return blank image data
                const canvas = document.createElement('canvas');
                const ctx = canvas.getContext('2d');
                return originalGetImageData.call(ctx, 0, 0, canvas.width, canvas.height);
            };
            
            // Block WebGL fingerprinting
            const originalGetParameter = WebGLRenderingContext.prototype.getParameter;
            WebGLRenderingContext.prototype.getParameter = function(parameter) {
                // Return generic values for fingerprinting parameters
                if (parameter === 0x1F00) return "Generic Renderer"; // GL_RENDERER
                if (parameter === 0x1F01) return "Generic Vendor";   // GL_VENDOR
                return originalGetParameter.call(this, parameter);
            };
            
            console.log('Private browsing privacy protections enabled');
            
        })();
        """
    }
    
    // MARK: - Session Management
    func clearAllPrivateData() {
        guard let dataStore = privateDataStore else { return }
        
        let dataTypes: Set<String> = [
            WKWebsiteDataTypeCookies,
            WKWebsiteDataTypeSessionStorage,
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeWebSQLDatabases,
            WKWebsiteDataTypeIndexedDBDatabases,
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeOfflineWebApplicationCache,
            WKWebsiteDataTypeFetchCache,
            WKWebsiteDataTypeServiceWorkerRegistrations
        ]
        
        dataStore.removeData(ofTypes: dataTypes, modifiedSince: Date.distantPast) {
            print("All private browsing data cleared")
        }
    }
    
    func getPrivateBrowsingStats() -> PrivateBrowsingStats {
        return PrivateBrowsingStats(
            activeTabsCount: incognitoTabs.count,
            isSessionActive: isActive,
            sessionStartTime: isActive ? Date() : nil
        )
    }
    
    struct PrivateBrowsingStats {
        let activeTabsCount: Int
        let isSessionActive: Bool
        let sessionStartTime: Date?
    }
}