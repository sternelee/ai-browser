import SwiftUI

/// Main settings view with comprehensive browser configuration options
/// Follows next-gen glass morphism design with category tabs
struct SettingsView: View {
    @State private var selectedCategory: SettingsCategory = .general
    @State private var contentOpacity = 0.0
    @State private var hoveredCategory: SettingsCategory?
    
    enum SettingsCategory: String, CaseIterable {
        case general = "General"
        case privacy = "Privacy"
        case security = "Security"
        case appearance = "Appearance"
        case advanced = "Advanced"
        
        var icon: String {
            switch self {
            case .general: return "gear"
            case .privacy: return "hand.raised"
            case .security: return "lock.shield"
            case .appearance: return "paintbrush"
            case .advanced: return "terminal"
            }
        }
    }
    
    var body: some View {
        ZStack {
            // Glass background with enhanced visual effect
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.15), lineWidth: 0.5)
                )
            
            VStack(spacing: 0) {
                // Header with close button
                settingsHeader
                
                Divider()
                    .opacity(0.3)
                    .padding(.horizontal, 24)
                
                // Main content area
                HStack(spacing: 0) {
                    // Category sidebar
                    categorysidebar
                    
                    // Vertical divider
                    Rectangle()
                        .fill(.white.opacity(0.1))
                        .frame(width: 0.5)
                    
                    // Settings content area
                    settingsContent
                }
            }
            .opacity(contentOpacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                contentOpacity = 1.0
            }
        }
    }
    
    private var settingsHeader: some View {
        HStack {
            Text("Settings")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Spacer()
            
            Button(action: {
                KeyboardShortcutHandler.shared.showSettingsPanel = false
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }
    
    private var categorysidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SettingsCategory.allCases, id: \.self) { category in
                categoryButton(category)
            }
            
            Spacer()
        }
        .padding(.vertical, 20)
        .padding(.leading, 24)
        .frame(width: 180)
    }
    
    private func categoryButton(_ category: SettingsCategory) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                selectedCategory = category
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: category.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(selectedCategory == category ? .blue : .secondary)
                    .frame(width: 16)
                
                Text(category.rawValue)
                    .font(.system(size: 14, weight: selectedCategory == category ? .semibold : .medium))
                    .foregroundColor(selectedCategory == category ? .primary : .secondary)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColorForCategory(category))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                hoveredCategory = hovering ? category : nil
            }
        }
    }
    
    private func backgroundColorForCategory(_ category: SettingsCategory) -> Color {
        if selectedCategory == category {
            return .blue.opacity(0.15)
        } else if hoveredCategory == category {
            return .white.opacity(0.05)
        } else {
            return .clear
        }
    }
    
    private var settingsContent: some View {
        Group {
            switch selectedCategory {
            case .general:
                GeneralSettingsView()
            case .privacy:
                PrivacySettingsView()
            case .security:
                SecuritySettingsView()
            case .appearance:
                AppearanceSettingsView()
            case .advanced:
                AdvancedSettingsView()
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Settings Category Views

struct GeneralSettingsView: View {
    @AppStorage("defaultSearchEngine") private var defaultSearchEngine = "Google"
    @AppStorage("startupBehavior") private var startupBehavior = "new_tab"
    @AppStorage("enableDownloadNotifications") private var enableDownloadNotifications = true
    @AppStorage("autoCheckForUpdates") private var autoCheckForUpdates = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("General")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 16) {
                // Search Engine
                settingsGroup("Search Engine") {
                    Picker("Default Search Engine", selection: $defaultSearchEngine) {
                        Text("Google").tag("Google")
                        Text("DuckDuckGo").tag("DuckDuckGo")
                        Text("Bing").tag("Bing")
                        Text("Yahoo").tag("Yahoo")
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(maxWidth: 200)
                }
                
                // Startup Behavior
                settingsGroup("Startup") {
                    Picker("When Web starts", selection: $startupBehavior) {
                        Text("Open a new tab").tag("new_tab")
                        Text("Restore previous session").tag("restore_session")
                        Text("Open homepage").tag("homepage")
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(maxWidth: 250)
                }
                
                // Notifications
                settingsGroup("Notifications") {
                    Toggle("Show download notifications", isOn: $enableDownloadNotifications)
                }
                
                // Updates
                settingsGroup("Updates") {
                    Toggle("Automatically check for updates", isOn: $autoCheckForUpdates)
                }
            }
            
            Spacer()
        }
    }
}

struct SecuritySettingsView: View {
    @AppStorage("enablePasswordManager") private var enablePasswordManager = true
    @AppStorage("enableAdBlocker") private var enableAdBlocker = true
    @AppStorage("enableDNSOverHTTPS") private var enableDNSOverHTTPS = true
    @AppStorage("dnsProvider") private var dnsProvider = "Cloudflare"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Security")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 16) {
                // Password Manager
                settingsGroup("Password Manager") {
                    Toggle("Enable built-in password manager", isOn: $enablePasswordManager)
                    
                    if enablePasswordManager {
                        Text("Passwords are securely stored in your Keychain with biometric authentication.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 20)
                    }
                }
                
                // Ad Blocker
                settingsGroup("Content Blocking") {
                    Toggle("Enable ad blocker", isOn: $enableAdBlocker)
                    
                    if enableAdBlocker {
                        Text("Blocks ads and trackers using optimized filter lists for better performance.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 20)
                    }
                }
                
                // DNS over HTTPS
                settingsGroup("DNS Security") {
                    Toggle("Enable DNS over HTTPS", isOn: $enableDNSOverHTTPS)
                    
                    if enableDNSOverHTTPS {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("DNS Provider:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                Picker("DNS Provider", selection: $dnsProvider) {
                                    Text("Cloudflare").tag("Cloudflare")
                                    Text("Quad9").tag("Quad9")
                                    Text("Google").tag("Google")
                                }
                                .pickerStyle(MenuPickerStyle())
                                .frame(maxWidth: 120)
                            }
                            .padding(.leading, 20)
                            
                            Text("Encrypts DNS queries to protect your browsing from eavesdropping.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 20)
                        }
                    }
                }
            }
            
            Spacer()
        }
    }
}

struct AppearanceSettingsView: View {
    @AppStorage("enableGlassEffects") private var enableGlassEffects = true
    @AppStorage("enableSmoothAnimations") private var enableSmoothAnimations = true
    @AppStorage("enableFaviconColors") private var enableFaviconColors = true
    @AppStorage("sidebarWidth") private var sidebarWidth = 60.0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Appearance")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 16) {
                // Visual Effects
                settingsGroup("Visual Effects") {
                    Toggle("Enable glass morphism effects", isOn: $enableGlassEffects)
                    Toggle("Enable smooth 120fps animations", isOn: $enableSmoothAnimations)
                    Toggle("Extract colors from favicons", isOn: $enableFaviconColors)
                }
                
                // Sidebar
                settingsGroup("Sidebar") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sidebar width: \(Int(sidebarWidth))px")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Slider(value: $sidebarWidth, in: 50...120, step: 10)
                            .frame(maxWidth: 200)
                    }
                }
            }
            
            Spacer()
        }
    }
}

struct AdvancedSettingsView: View {
    @AppStorage("enableTabHibernation") private var enableTabHibernation = true
    @AppStorage("hibernationTimeout") private var hibernationTimeout = 300.0
    @AppStorage("enableDeveloperTools") private var enableDeveloperTools = true
    @AppStorage("enableExperimentalFeatures") private var enableExperimentalFeatures = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Advanced")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 16) {
                // Performance
                settingsGroup("Performance") {
                    Toggle("Enable tab hibernation", isOn: $enableTabHibernation)
                    
                    if enableTabHibernation {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Hibernation timeout: \(Int(hibernationTimeout / 60)) minutes")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.leading, 20)
                            
                            Slider(value: $hibernationTimeout, in: 60...1800, step: 60)
                                .frame(maxWidth: 200)
                                .padding(.leading, 20)
                        }
                    }
                }
                
                // Developer Features
                settingsGroup("Developer") {
                    Toggle("Enable developer tools", isOn: $enableDeveloperTools)
                    Toggle("Enable experimental features", isOn: $enableExperimentalFeatures)
                    
                    if enableExperimentalFeatures {
                        Text("⚠️ Experimental features may be unstable and could cause crashes.")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.leading, 20)
                    }
                }
                
                // Reset Options
                settingsGroup("Reset") {
                    Button("Reset All Settings") {
                        // Reset settings functionality would go here
                    }
                    .foregroundColor(.red)
                    
                    Button("Clear All Data") {
                        // Clear data functionality would go here
                    }
                    .foregroundColor(.red)
                }
            }
            
            Spacer()
        }
    }
}

// MARK: - Helper Views

extension View {
    func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            content()
                .padding(.leading, 8)
        }
    }
}

#Preview {
    SettingsView()
        .frame(width: 800, height: 600)
        .background(.black.opacity(0.3))
}