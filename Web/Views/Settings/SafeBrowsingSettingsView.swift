import SwiftUI

/**
 * SafeBrowsingSettingsView
 * 
 * Comprehensive settings interface for Google Safe Browsing integration.
 * Provides user control over threat protection, privacy settings, and API configuration.
 * 
 * Features:
 * - Enable/disable Safe Browsing protection
 * - API key management
 * - Threat statistics and monitoring
 * - User override management
 * - Privacy controls and explanations
 * - Cache management and updates
 */
struct SafeBrowsingSettingsView: View {
    @StateObject private var safeBrowsingManager = SafeBrowsingManager.shared
    @StateObject private var keyManager = SafeBrowsingKeyManager.shared
    @State private var showingAPIKeySheet = false
    @State private var showingUserOverrides = false
    @State private var showingPrivacyInfo = false
    @State private var isUpdatingThreatLists = false
    @State private var showingClearCacheConfirmation = false
    @State private var apiKeyInput = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            headerSection
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Protection Status
                    protectionStatusSection
                    
                    // Configuration
                    configurationSection
                    
                    // Statistics
                    statisticsSection
                    
                    // User Overrides Management
                    userOverridesSection
                    
                    // Privacy Information
                    privacySection
                    
                    // Advanced Settings
                    advancedSection
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            loadAPIKey()
        }
        .sheet(isPresented: $showingAPIKeySheet) {
            apiKeyConfigurationSheet
        }
        .sheet(isPresented: $showingUserOverrides) {
            userOverridesSheet
        }
        .sheet(isPresented: $showingPrivacyInfo) {
            privacyInformationSheet
        }
        .alert("Clear Safe Browsing Cache", isPresented: $showingClearCacheConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear Cache", role: .destructive) {
                Task {
                    await safeBrowsingManager.clearThreatCache()
                }
            }
        } message: {
            Text("This will clear all cached threat data. New threats will need to be downloaded from Google's servers, which may temporarily reduce protection until the cache rebuilds.")
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "shield.checkered")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                Text("Safe Browsing")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                // Status indicator
                statusIndicator
            }
            
            Text("Protect yourself from malware, phishing, and other dangerous websites using Google Safe Browsing.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }
    
    private var statusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(safeBrowsingManager.isEnabled ? (safeBrowsingManager.isOnline ? Color.green : Color.orange) : Color.red)
                .frame(width: 8, height: 8)
            
            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var statusText: String {
        if !safeBrowsingManager.isEnabled {
            return "Disabled"
        } else if safeBrowsingManager.isOnline {
            return "Active"
        } else {
            return "Offline"
        }
    }
    
    private var protectionStatusSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Protection Status")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable Safe Browsing Protection", isOn: $safeBrowsingManager.isEnabled)
                    .toggleStyle(.switch)
                
                if !safeBrowsingManager.isEnabled {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("Your browsing is not protected from malware and phishing websites.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 8)
                }
                
                if safeBrowsingManager.isEnabled && !safeBrowsingManager.isOnline {
                    HStack {
                        Image(systemName: "wifi.slash")
                            .foregroundColor(.orange)
                        Text("Safe Browsing is using cached data only. Connect to the internet for full protection.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 8)
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }
    
    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configuration")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                Button(action: { showingAPIKeySheet = true }) {
                    HStack {
                        Image(systemName: keyManager.hasValidAPIKey ? "key.fill" : "key.slash.fill")
                            .foregroundColor(keyManager.hasValidAPIKey ? .green : .red)
                        Text("Configure API Key")
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(keyManager.keyValidationStatus.description)
                                .font(.caption)
                                .foregroundColor(keyManager.hasValidAPIKey ? .green : .secondary)
                            
                            if let lastValidation = keyManager.lastValidationDate {
                                Text("Last checked: \(formatDate(lastValidation))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                
                if let lastUpdate = safeBrowsingManager.lastUpdateDate {
                    HStack {
                        Image(systemName: "clock.fill")
                            .foregroundColor(.secondary)
                        Text("Last updated: \(formatDate(lastUpdate))")
                            .font(.callout)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button("Update Now") {
                            updateThreatLists()
                        }
                        .disabled(isUpdatingThreatLists || !safeBrowsingManager.isEnabled)
                        .font(.callout)
                    }
                    .padding(.horizontal, 12)
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Threat lists have not been updated yet")
                            .font(.callout)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button("Update Now") {
                            updateThreatLists()
                        }
                        .disabled(isUpdatingThreatLists || !safeBrowsingManager.isEnabled)
                        .font(.callout)
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }
    
    private var statisticsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Protection Statistics")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                statisticCard(
                    title: "Threats Blocked",
                    value: "\(safeBrowsingManager.totalThreatsBlocked)",
                    icon: "shield.checkered",
                    color: .green
                )
                
                statisticCard(
                    title: "API Quota Remaining",
                    value: "\(safeBrowsingManager.apiQuotaRemaining)",
                    icon: "speedometer",
                    color: .blue
                )
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }
    
    private var userOverridesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("User Overrides")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Websites you've chosen to allow despite security warnings")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button("Manage") {
                        showingUserOverrides = true
                    }
                    .font(.callout)
                }
                
                let overrideCount = safeBrowsingManager.getUserOverrides().count
                HStack {
                    Image(systemName: overrideCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundColor(overrideCount > 0 ? .orange : .green)
                    
                    Text(overrideCount > 0 ? "\(overrideCount) website\(overrideCount == 1 ? "" : "s") bypassing protection" : "No security overrides")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }
    
    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Privacy & Data")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                Button(action: { showingPrivacyInfo = true }) {
                    HStack {
                        Image(systemName: "hand.raised.fill")
                        Text("Privacy Information")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("URLs are never sent in full to Google")
                            .font(.callout)
                    }
                    
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Only SHA256 hashes are transmitted for privacy")
                            .font(.callout)
                    }
                    
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Threat data is cached locally for offline protection")
                            .font(.callout)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }
    
    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Advanced")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                Button("Clear Threat Cache") {
                    showingClearCacheConfirmation = true
                }
                .buttonStyle(.plain)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                
                Text("Clearing the cache will remove all locally stored threat data and may temporarily reduce protection until the cache rebuilds.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }
    
    // MARK: - Helper Views
    
    private func statisticCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var apiKeyConfigurationSheet: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Google Safe Browsing API Key")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("To enable Safe Browsing protection, you need a Google Safe Browsing API key.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                Text("How to get an API key:")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Go to the Google Cloud Console")
                    Text("2. Create a new project or select an existing one")
                    Text("3. Enable the Safe Browsing API")
                    Text("4. Create credentials and copy your API key")
                    Text("5. Paste the key below")
                }
                .font(.callout)
                .foregroundColor(.secondary)
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(12)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("API Key")
                    .font(.headline)
                
                SecureField("Enter your Google Safe Browsing API key", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                
                Text("Your API key is stored securely and only used to check website safety.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Button("Cancel") {
                    showingAPIKeySheet = false
                    apiKeyInput = ""
                }
                .buttonStyle(.borderless)
                
                Spacer()
                
                Button("Save") {
                    saveAPIKey()
                }
                .buttonStyle(.borderedProminent)
                .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 500, height: 500)
    }
    
    private var userOverridesSheet: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("User Overrides")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Websites you've chosen to allow despite security warnings.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            List {
                ForEach(safeBrowsingManager.getUserOverrides(), id: \.self) { override in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(override)
                                .font(.body)
                            Text("This website will bypass Safe Browsing checks")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("Remove") {
                            if let url = URL(string: override) {
                                safeBrowsingManager.removeUserOverride(for: url)
                            }
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.red)
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(height: 300)
            
            HStack {
                Spacer()
                Button("Done") {
                    showingUserOverrides = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 600, height: 450)
    }
    
    private var privacyInformationSheet: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Privacy Information")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("How Safe Browsing protects your privacy while keeping you safe.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    privacySection("What data is sent to Google?", """
                    • Only SHA256 hashes of URLs, never the full URLs
                    • No personal information or browsing history
                    • No cookies or session data
                    • Client information (browser type and version)
                    """)
                    
                    privacySection("What data is stored locally?", """
                    • Cached threat data for offline protection
                    • Your user overrides for false positives
                    • API configuration and statistics
                    • No browsing history or personal data
                    """)
                    
                    privacySection("How does hashing protect privacy?", """
                    • URLs are converted to SHA256 hashes before transmission
                    • Hashes cannot be reversed to reveal the original URL
                    • Google can only confirm if a hash matches known threats
                    • Your browsing patterns remain completely private
                    """)
                    
                    privacySection("Data retention", """
                    • Local threat cache expires after 1 hour
                    • No permanent storage of website data
                    • User overrides are stored until manually removed
                    • All data is encrypted and stored securely
                    """)
                }
            }
            .frame(height: 400)
            
            HStack {
                Spacer()
                Button("Close") {
                    showingPrivacyInfo = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 600, height: 550)
    }
    
    private func privacySection(_ title: String, _ content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            
            Text(content)
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }
    
    // MARK: - Private Methods
    
    private func loadAPIKey() {
        // Load existing API key for display (not the actual key for security)
        if UserDefaults.standard.string(forKey: "SafeBrowsing.APIKey") != nil {
            apiKeyInput = "••••••••••••••••••••••••••••••••••••••••"
        }
    }
    
    private func saveAPIKey() {
        let trimmedKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Only save if it's not the masked display
        if !trimmedKey.contains("•") && !trimmedKey.isEmpty {
            Task {
                do {
                    try await keyManager.storeAPIKey(trimmedKey)
                    await MainActor.run {
                        showingAPIKeySheet = false
                        apiKeyInput = ""
                    }
                } catch {
                    // Handle error (could show an alert here)
                    print("Failed to store API key: \(error.localizedDescription)")
                }
            }
        } else {
            showingAPIKeySheet = false
            apiKeyInput = ""
        }
    }
    
    private func updateThreatLists() {
        isUpdatingThreatLists = true
        
        Task {
            await safeBrowsingManager.updateThreatLists()
            
            await MainActor.run {
                isUpdatingThreatLists = false
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    SafeBrowsingSettingsView()
        .frame(width: 800, height: 600)
}