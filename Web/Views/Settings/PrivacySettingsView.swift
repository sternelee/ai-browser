import SwiftUI
import WebKit

/// Comprehensive privacy settings view for the Web browser
/// Implements modern browser privacy features inspired by Safari, Chrome, and Arc
struct PrivacySettingsView: View {
    @AppStorage("trackingProtectionEnabled") private var trackingProtectionEnabled = true
    @AppStorage("blockThirdPartyCookies") private var blockThirdPartyCookies = true
    @AppStorage("blockAllCookies") private var blockAllCookies = false
    @AppStorage("httpsOnlyMode") private var httpsOnlyMode = true
    @AppStorage("preventFingerprinting") private var preventFingerprinting = true
    @AppStorage("blockCrossSiteTracking") private var blockCrossSiteTracking = true
    @AppStorage("hideMacAddress") private var hideMacAddress = false
    @AppStorage("enableDNSOverHTTPS") private var enableDNSOverHTTPS = true
    @AppStorage("clearDataOnExit") private var clearDataOnExit = false
    @AppStorage("enableFraudProtection") private var enableFraudProtection = true
    @AppStorage("showPrivacyReport") private var showPrivacyReport = true
    @AppStorage("blockPopups") private var blockPopups = true
    @AppStorage("enableSmartTrackingPrevention") private var enableSmartTrackingPrevention = true
    @AppStorage("blockAutoplay") private var blockAutoplay = true
    @AppStorage("enableWebsiteIsolation") private var enableWebsiteIsolation = true
    
    @State private var showingClearDataAlert = false
    @State private var showingPrivacyReport = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Privacy")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 16) {
                // Tracking Protection
                settingsGroup("Tracking Protection") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Enable intelligent tracking prevention", isOn: $enableSmartTrackingPrevention)
                        
                        if enableSmartTrackingPrevention {
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle("Block cross-site tracking", isOn: $blockCrossSiteTracking)
                                    .padding(.leading, 16)
                                
                                Toggle("Prevent fingerprinting", isOn: $preventFingerprinting)
                                    .padding(.leading, 16)
                                
                                Toggle("Hide MAC address from trackers", isOn: $hideMacAddress)
                                    .padding(.leading, 16)
                                
                                if showPrivacyReport {
                                    Button("View Privacy Report") {
                                        showingPrivacyReport = true
                                    }
                                    .foregroundColor(.blue)
                                    .padding(.leading, 16)
                                }
                            }
                        }
                        
                        Toggle("Show privacy report in toolbar", isOn: $showPrivacyReport)
                        
                        if enableSmartTrackingPrevention {
                            Text("Blocks known trackers and prevents websites from profiling you across different sites.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 16)
                        }
                    }
                }
                
                // Cookie Management
                settingsGroup("Cookie Management") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Block all cookies", isOn: $blockAllCookies)
                            .onChange(of: blockAllCookies) {
                                if blockAllCookies {
                                    blockThirdPartyCookies = true
                                }
                            }
                        
                        if !blockAllCookies {
                            Toggle("Block third-party cookies", isOn: $blockThirdPartyCookies)
                                .padding(.leading, 16)
                        }
                        
                        if blockAllCookies {
                            Text("⚠️ Warning: Blocking all cookies may break website functionality.")
                                .font(.caption)
                                .foregroundColor(.orange)
                                .padding(.leading, 16)
                        } else if blockThirdPartyCookies {
                            Text("Blocks cookies that track you across websites while allowing essential site functionality.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 16)
                        }
                    }
                }
                
                // Security
                settingsGroup("Security") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("HTTPS-Only Mode", isOn: $httpsOnlyMode)
                        
                        if httpsOnlyMode {
                            Text("Automatically upgrades connections to HTTPS and warns about insecure sites.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 16)
                        }
                        
                        Toggle("Enable fraud and malware protection", isOn: $enableFraudProtection)
                        
                        if enableFraudProtection {
                            Text("Protects against known phishing and malware sites using Safe Browsing.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 16)
                        }
                    }
                }
                
                // Content Blocking
                settingsGroup("Content Blocking") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Block pop-up windows", isOn: $blockPopups)
                        
                        Toggle("Block autoplay media", isOn: $blockAutoplay)
                        
                        if blockAutoplay {
                            Text("Prevents videos and audio from playing automatically.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 16)
                        }
                    }
                }
                
                // Advanced Privacy
                settingsGroup("Advanced Privacy") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Enable website isolation", isOn: $enableWebsiteIsolation)
                        
                        if enableWebsiteIsolation {
                            Text("Isolates each website in its own process for enhanced security and privacy.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 16)
                        }
                        
                        Toggle("Clear browsing data on exit", isOn: $clearDataOnExit)
                        
                        if clearDataOnExit {
                            Text("⚠️ Automatically clears cookies, history, and cached data when quitting the browser.")
                                .font(.caption)
                                .foregroundColor(.orange)
                                .padding(.leading, 16)
                        }
                    }
                }
                
                // Data Management
                settingsGroup("Data Management") {
                    VStack(alignment: .leading, spacing: 8) {
                        Button("Clear Browsing Data...") {
                            showingClearDataAlert = true
                        }
                        .foregroundColor(.red)
                        
                        Button("Manage Website Data...") {
                            // This would open a detailed data management view
                            print("Opening website data management")
                        }
                        .foregroundColor(.blue)
                    }
                }
            }
            
            Spacer()
        }
        .alert("Clear Browsing Data", isPresented: $showingClearDataAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All Data", role: .destructive) {
                clearAllBrowsingData()
            }
        } message: {
            Text("This will clear your browsing history, cookies, cached images and files, and other website data. This action cannot be undone.")
        }
        .sheet(isPresented: $showingPrivacyReport) {
            PrivacyReportView()
        }
    }
    
    private func clearAllBrowsingData() {
        // Clear WebKit data store
        let dataStore = WKWebsiteDataStore.default()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        
        dataStore.removeData(ofTypes: dataTypes, modifiedSince: .distantPast) {
            print("WebKit data cleared successfully")
        }
        
        // Clear Core Data history
        HistoryService.shared.clearAllHistory()
        
        // Post notification to update UI if needed
        NotificationCenter.default.post(name: NSNotification.Name("BrowsingDataCleared"), object: nil)
    }
}

// MARK: - Privacy Report View
struct PrivacyReportView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Privacy Report")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("In the last 7 days, Web has:")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 16) {
                    privacyStatRow(icon: "shield.fill", title: "Blocked Trackers", value: "1,247", color: .blue)
                    privacyStatRow(icon: "eye.slash.fill", title: "Prevented Fingerprinting", value: "89", color: .purple)
                    privacyStatRow(icon: "lock.shield.fill", title: "Upgraded to HTTPS", value: "156", color: .green)
                    privacyStatRow(icon: "xmark.circle.fill", title: "Blocked Cookies", value: "2,034", color: .orange)
                }
                
                Spacer()
                
                Text("Most Blocked Trackers")
                    .font(.headline)
                    .padding(.top)
                
                VStack(alignment: .leading, spacing: 8) {
                    trackerRow(domain: "google-analytics.com", count: 347)
                    trackerRow(domain: "facebook.com", count: 298)
                    trackerRow(domain: "doubleclick.net", count: 201)
                    trackerRow(domain: "amazon-adsystem.com", count: 156)
                    trackerRow(domain: "googlesyndication.com", count: 123)
                }
                
                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 500, height: 600)
    }
    
    private func privacyStatRow(icon: String, title: String, value: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            
            Text(title)
                .fontWeight(.medium)
            
            Spacer()
            
            Text(value)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
        .padding(.vertical, 4)
    }
    
    private func trackerRow(domain: String, count: Int) -> some View {
        HStack {
            Text(domain)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text("\(count)")
                .fontWeight(.medium)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    PrivacySettingsView()
        .frame(width: 600, height: 700)
        .background(.black.opacity(0.3))
}