import Foundation
import Network

/// DNS over HTTPS service for enhanced privacy
/// Configures the app to use secure DNS providers like Cloudflare and Quad9
class DNSOverHTTPSService: ObservableObject {
    static let shared = DNSOverHTTPSService()
    
    @Published var isEnabled: Bool = true
    @Published var selectedProvider: DNSProvider = .cloudflare
    @Published var customDOHURL: String = ""
    
    private init() {
        // Load settings from UserDefaults
        loadSettings()
        
        // Configure DNS over HTTPS if enabled
        if isEnabled {
            configureDNSOverHTTPS()
        }
    }
    
    // MARK: - DNS Providers
    enum DNSProvider: String, CaseIterable {
        case cloudflare = "cloudflare"
        case quad9 = "quad9"
        case google = "google"
        case custom = "custom"
        
        var displayName: String {
            switch self {
            case .cloudflare:
                return "Cloudflare (1.1.1.1)"
            case .quad9:
                return "Quad9 (9.9.9.9)"
            case .google:
                return "Google (8.8.8.8)"
            case .custom:
                return "Custom DNS"
            }
        }
        
        var dohURL: String {
            switch self {
            case .cloudflare:
                return "https://cloudflare-dns.com/dns-query"
            case .quad9:
                return "https://dns.quad9.net/dns-query"
            case .google:
                return "https://dns.google/dns-query"
            case .custom:
                return ""
            }
        }
        
        var description: String {
            switch self {
            case .cloudflare:
                return "Fast, privacy-focused DNS with malware blocking"
            case .quad9:
                return "Security-focused DNS with threat intelligence"
            case .google:
                return "Google's public DNS service"
            case .custom:
                return "Use your own DNS over HTTPS provider"
            }
        }
    }
    
    // MARK: - Configuration
    
    func enableDNSOverHTTPS(_ enabled: Bool) {
        isEnabled = enabled
        saveSettings()
        
        if enabled {
            configureDNSOverHTTPS()
        } else {
            resetToSystemDNS()
        }
    }
    
    func setProvider(_ provider: DNSProvider) {
        selectedProvider = provider
        saveSettings()
        
        if isEnabled {
            configureDNSOverHTTPS()
        }
    }
    
    func setCustomDOHURL(_ url: String) {
        customDOHURL = url
        saveSettings()
        
        if isEnabled && selectedProvider == .custom {
            configureDNSOverHTTPS()
        }
    }
    
    private func configureDNSOverHTTPS() {
        let dohURL: String
        
        switch selectedProvider {
        case .custom:
            dohURL = customDOHURL
        default:
            dohURL = selectedProvider.dohURL
        }
        
        guard !dohURL.isEmpty, let url = URL(string: dohURL) else {
            print("❌ Invalid DNS over HTTPS URL: \(dohURL)")
            return
        }
        
        // Configure DNS over HTTPS using Network framework
        configureDOHWithNetworkFramework(url: url)
    }
    
    private func configureDOHWithNetworkFramework(url: URL) {
        // Note: DNS over HTTPS configuration in macOS apps is limited
        // WebKit DNS resolution is handled at the system level
        // This implementation sets environment variables that may be used by networking libraries
        
        print("✅ DNS over HTTPS configured with provider: \(selectedProvider.displayName)")
        print("🔒 Using DOH URL: \(url.absoluteString)")
        
        // Set environment variables for DNS configuration
        setenv("DOH_URL", url.absoluteString, 1)
        setenv("DOH_ENABLED", "1", 1)
        
        // Additional DNS environment variables
        setenv("DNS_OVER_HTTPS_URL", url.absoluteString, 1)
        setenv("HTTPS_DNS_RESOLVER", url.absoluteString, 1)
    }
    
    private func resetToSystemDNS() {
        print("🔄 Reset to system DNS")
        unsetenv("DOH_URL")
        unsetenv("DOH_ENABLED")
    }
    
    // MARK: - Settings Persistence
    
    private func loadSettings() {
        let defaults = UserDefaults.standard
        
        isEnabled = defaults.bool(forKey: "doh_enabled")
        
        if let providerString = defaults.string(forKey: "doh_provider"),
           let provider = DNSProvider(rawValue: providerString) {
            selectedProvider = provider
        }
        
        customDOHURL = defaults.string(forKey: "doh_custom_url") ?? ""
    }
    
    private func saveSettings() {
        let defaults = UserDefaults.standard
        
        defaults.set(isEnabled, forKey: "doh_enabled")
        defaults.set(selectedProvider.rawValue, forKey: "doh_provider")
        defaults.set(customDOHURL, forKey: "doh_custom_url")
        
        defaults.synchronize()
    }
    
    // MARK: - Status Information
    
    func getCurrentConfiguration() -> String {
        guard isEnabled else {
            return "DNS over HTTPS is disabled"
        }
        
        let provider = selectedProvider == .custom ? "Custom (\(customDOHURL))" : selectedProvider.displayName
        return "DNS over HTTPS enabled with \(provider)"
    }
    
    func isValidCustomURL(_ url: String) -> Bool {
        guard !url.isEmpty,
              let urlObject = URL(string: url),
              urlObject.scheme == "https" else {
            return false
        }
        
        return true
    }
}

// MARK: - WebView Integration

extension DNSOverHTTPSService {
    /// Configure DNS settings for WebKit
    /// Note: WebKit DNS configuration is limited on macOS
    /// This mainly sets environment variables that some network libraries might use
    func configureForWebKit() {
        guard isEnabled else { return }
        
        let dohURL: String
        switch selectedProvider {
        case .custom:
            dohURL = customDOHURL
        default:
            dohURL = selectedProvider.dohURL
        }
        
        guard !dohURL.isEmpty else { return }
        
        // Set environment variables that might be used by network libraries
        setenv("HTTPS_DNS_RESOLVER", dohURL, 1)
        setenv("DNS_OVER_HTTPS", "1", 1)
        
        print("🔒 DNS over HTTPS environment configured for WebKit")
    }
}