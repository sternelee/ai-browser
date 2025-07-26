import SwiftUI

/**
 * SecuritySettingsView - Comprehensive Security Configuration Interface
 * 
 * Provides centralized access to all browser security settings including:
 * - Mixed Content Protection
 * - Content Security Policy (CSP)
 * - Certificate Management
 * - Runtime Security Monitoring
 * - Privacy Controls
 */
struct SecuritySettingsView: View {
    @StateObject private var mixedContentManager = MixedContentManager.shared
    @StateObject private var cspManager = CSPManager.shared
    @StateObject private var certificateManager = CertificateManager.shared
    @StateObject private var runtimeMonitor = RuntimeSecurityMonitor.shared
    
    @State private var selectedSecuritySection: SecuritySection = .mixedContent
    @State private var showingAdvancedOptions = false
    
    enum SecuritySection: String, CaseIterable {
        case mixedContent = "Mixed Content"
        case certificates = "Certificates"
        case contentSecurity = "Content Security"
        case runtimeProtection = "Runtime Protection"
        
        var icon: String {
            switch self {
            case .mixedContent: return "exclamationmark.shield"
            case .certificates: return "lock.shield"
            case .contentSecurity: return "shield.checkered"
            case .runtimeProtection: return "cpu.fill"
            }
        }
        
        var description: String {
            switch self {
            case .mixedContent: return "HTTP/HTTPS content mixing protection"
            case .certificates: return "TLS certificate validation and management"
            case .contentSecurity: return "Script injection and XSS protection"
            case .runtimeProtection: return "Memory and process integrity monitoring"
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            securityHeader
            
            Divider()
                .padding(.horizontal, 24)
            
            // Content area
            HStack(spacing: 0) {
                // Security sections sidebar
                securitySidebar
                
                Divider()
                
                // Main content
                securityContent
            }
        }
        .onAppear {
            // Check if we should navigate to a specific section
            handleNotificationNavigation()
        }
    }
    
    // MARK: - Header Section
    
    private var securityHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "lock.shield")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Security Settings")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("Configure browser security features and policies")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Security status indicator
                securityStatusIndicator
            }
            
            // Security overview stats
            securityOverviewStats
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
    
    private var securityStatusIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(overallSecurityStatus.color)
                .frame(width: 8, height: 8)
            
            Text(overallSecurityStatus.description)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(overallSecurityStatus.color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(overallSecurityStatus.color.opacity(0.1))
        )
    }
    
    private var securityOverviewStats: some View {
        HStack(spacing: 20) {
            securityStat(
                title: "Mixed Content",
                value: "\(mixedContentManager.totalMixedContentBlocked) blocked",
                color: mixedContentManager.mixedContentPolicy == .block ? .green : .orange
            )
            
            securityStat(
                title: "CSP Violations",
                value: "\(cspManager.cspViolations.count) detected",
                color: cspManager.cspViolations.isEmpty ? .green : .red
            )
            
            securityStat(
                title: "Security Level",
                value: certificateManager.securityLevel.rawValue,
                color: certificateManager.securityLevel.color
            )
            
            securityStat(
                title: "Runtime Status",
                value: runtimeMonitor.securityStatus.description,
                color: runtimeMonitor.securityStatus == .secure ? .green : .red
            )
            
            Spacer()
        }
    }
    
    private func securityStat(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
    }
    
    // MARK: - Security Sidebar
    
    private var securitySidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SecuritySection.allCases, id: \.self) { section in
                securitySectionButton(section)
            }
            
            Spacer()
            
            // Advanced options toggle
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingAdvancedOptions.toggle()
                }
            }) {
                HStack {
                    Image(systemName: showingAdvancedOptions ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Advanced")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            
            if showingAdvancedOptions {
                VStack(spacing: 2) {
                    advancedOptionButton("Export Security Logs", icon: "square.and.arrow.up")
                    advancedOptionButton("Reset Security Settings", icon: "arrow.clockwise")
                    advancedOptionButton("Security Diagnostics", icon: "stethoscope")
                }
                .transition(.opacity.combined(with: .slide))
            }
        }
        .padding(.vertical, 16)
        .padding(.leading, 24)
        .frame(minWidth: 180, idealWidth: 200, maxWidth: 240)
    }
    
    private func securitySectionButton(_ section: SecuritySection) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedSecuritySection = section
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(selectedSecuritySection == section ? .blue : .secondary)
                    .frame(width: 16)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(section.rawValue)
                        .font(.system(size: 13, weight: selectedSecuritySection == section ? .semibold : .medium))
                        .foregroundColor(selectedSecuritySection == section ? .primary : .secondary)
                    
                    Text(section.description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selectedSecuritySection == section ? Color.blue.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func advancedOptionButton(_ title: String, icon: String) -> some View {
        Button(action: {
            handleAdvancedOption(title)
        }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 12)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Security Content
    
    private var securityContent: some View {
        ScrollView {
            Group {
                switch selectedSecuritySection {
                case .mixedContent:
                    MixedContentSettingsView()
                case .certificates:
                    CertificateSettingsView()
                case .contentSecurity:
                    CSPSecuritySettingsView()
                case .runtimeProtection:
                    RuntimeSecuritySettingsView()
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 400, maxWidth: .infinity)
    }
    
    // MARK: - Mixed Content Settings View
    
    private struct MixedContentSettingsView: View {
        @StateObject private var mixedContentManager = MixedContentManager.shared
        @State private var showingPolicyExplanation = false
        
        var body: some View {
            VStack(alignment: .leading, spacing: 20) {
                // Section header
                HStack {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundColor(.orange)
                        .font(.title2)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mixed Content Protection")
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Text("Control how HTTP resources are handled on HTTPS pages")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Learn More") {
                        showingPolicyExplanation.toggle()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.blue)
                }
                
                Divider()
                
                // Mixed content policy selection
                VStack(alignment: .leading, spacing: 16) {
                    Text("Mixed Content Policy")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    VStack(spacing: 12) {
                        ForEach(MixedContentManager.MixedContentPolicy.allCases, id: \.self) { policy in
                            mixedContentPolicyOption(policy)
                        }
                    }
                }
                
                Divider()
                
                // Mixed content statistics
                mixedContentStatistics
                
                Divider()
                
                // Advanced mixed content options
                advancedMixedContentOptions
            }
            .sheet(isPresented: $showingPolicyExplanation) {
                MixedContentPolicyExplanationView()
            }
        }
        
        private func mixedContentPolicyOption(_ policy: MixedContentManager.MixedContentPolicy) -> some View {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    mixedContentManager.mixedContentPolicy = policy
                    mixedContentManager.saveConfiguration()
                }
            }) {
                HStack(spacing: 12) {
                    // Radio button
                    Circle()
                        .fill(mixedContentManager.mixedContentPolicy == policy ? Color.blue : Color.clear)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Circle()
                                .stroke(Color.blue, lineWidth: 2)
                        )
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(policy.rawValue)
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            // Security level indicator
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(policy.securityLevel.color)
                                    .frame(width: 6, height: 6)
                                
                                Text(policy.securityLevel == .high ? "High Security" : policy.securityLevel == .medium ? "Medium Security" : "Low Security")
                                    .font(.caption)
                                    .foregroundColor(policy.securityLevel.color)
                            }
                        }
                        
                        Text(policy.description)
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(mixedContentManager.mixedContentPolicy == policy ? Color.blue.opacity(0.1) : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(
                                    mixedContentManager.mixedContentPolicy == policy ? Color.blue.opacity(0.3) : Color.clear,
                                    lineWidth: 1
                                )
                        )
                )
            }
            .buttonStyle(.plain)
        }
        
        private var mixedContentStatistics: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Mixed Content Statistics")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                let stats = mixedContentManager.getSecurityStatistics()
                
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    statisticCard(
                        title: "Total Violations",
                        value: "\(stats.totalViolations)",
                        icon: "exclamationmark.triangle",
                        color: stats.totalViolations > 0 ? .orange : .green
                    )
                    
                    statisticCard(
                        title: "Recent Violations",
                        value: "\(stats.recentViolations)",
                        icon: "clock",
                        color: stats.recentViolations > 0 ? .red : .green
                    )
                    
                    statisticCard(
                        title: "Content Blocked",
                        value: "\(stats.totalBlocked)",
                        icon: "shield.slash",
                        color: .blue
                    )
                }
            }
        }
        
        private func statisticCard(title: String, value: String, icon: String, color: Color) -> some View {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(color.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        
        private var advancedMixedContentOptions: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Advanced Options")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                VStack(spacing: 12) {
                    Toggle("Show mixed content warnings", isOn: $mixedContentManager.showMixedContentWarnings)
                        .onChange(of: mixedContentManager.showMixedContentWarnings) { _, _ in
                            mixedContentManager.saveConfiguration()
                        }
                    
                    Toggle("Log mixed content events", isOn: $mixedContentManager.logMixedContentEvents)
                        .onChange(of: mixedContentManager.logMixedContentEvents) { _, _ in
                            mixedContentManager.saveConfiguration()
                        }
                    
                    Toggle("Block active mixed content (scripts, stylesheets)", isOn: $mixedContentManager.blockActiveContent)
                        .onChange(of: mixedContentManager.blockActiveContent) { _, _ in
                            mixedContentManager.saveConfiguration()
                        }
                    
                    Toggle("Allow passive mixed content (images, media)", isOn: $mixedContentManager.allowPassiveContent)
                        .onChange(of: mixedContentManager.allowPassiveContent) { _, _ in
                            mixedContentManager.saveConfiguration()
                        }
                }
                
                // Reset button
                HStack {
                    Spacer()
                    
                    Button("Reset to Defaults") {
                        resetMixedContentSettings()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }
            }
        }
        
        private func resetMixedContentSettings() {
            withAnimation(.easeInOut(duration: 0.3)) {
                mixedContentManager.mixedContentPolicy = .warn
                mixedContentManager.showMixedContentWarnings = true
                mixedContentManager.logMixedContentEvents = true
                mixedContentManager.blockActiveContent = true
                mixedContentManager.allowPassiveContent = false
                mixedContentManager.saveConfiguration()
            }
        }
    }
    
    // MARK: - Placeholder Views for Other Security Sections
    
    private struct CertificateSettingsView: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 20) {
                Text("Certificate Settings")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text("Certificate management settings will be implemented here")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private struct RuntimeSecuritySettingsView: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 20) {
                Text("Runtime Security Settings")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text("Runtime security monitoring settings will be implemented here")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private var overallSecurityStatus: (color: Color, description: String) {
        let mixedContentSecure = mixedContentManager.mixedContentPolicy == .block
        let cspSecure = cspManager.isCSPEnabled && cspManager.strictModeEnabled
        let runtimeSecure = runtimeMonitor.securityStatus == .secure
        
        let secureCount = [mixedContentSecure, cspSecure, runtimeSecure].filter { $0 }.count
        
        switch secureCount {
        case 3:
            return (.green, "Secure")
        case 2:
            return (.orange, "Good")
        case 1:
            return (.red, "Needs Attention")
        default:
            return (.red, "Vulnerable")
        }
    }
    
    private func handleNotificationNavigation() {
        // Handle navigation from notifications (e.g., from mixed content warnings)
        NotificationCenter.default.addObserver(
            forName: .showSettingsRequested,
            object: nil,
            queue: .main
        ) { notification in
            if let section = notification.object as? String {
                switch section {
                case "mixedContent":
                    selectedSecuritySection = .mixedContent
                case "certificates":
                    selectedSecuritySection = .certificates
                case "csp", "contentSecurity":
                    selectedSecuritySection = .contentSecurity
                case "runtime":
                    selectedSecuritySection = .runtimeProtection
                default:
                    break
                }
            }
        }
    }
    
    private func handleAdvancedOption(_ option: String) {
        switch option {
        case "Export Security Logs":
            exportSecurityLogs()
        case "Reset Security Settings":
            resetAllSecuritySettings()
        case "Security Diagnostics":
            runSecurityDiagnostics()
        default:
            break
        }
    }
    
    private func exportSecurityLogs() {
        // Implementation for exporting security logs
        NSLog("🔒 Security logs export requested")
    }
    
    private func resetAllSecuritySettings() {
        // Implementation for resetting all security settings
        NSLog("🔒 All security settings reset requested")
    }
    
    private func runSecurityDiagnostics() {
        // Implementation for running security diagnostics
        NSLog("🔒 Security diagnostics requested")
    }
}

// MARK: - Mixed Content Policy Explanation View

private struct MixedContentPolicyExplanationView: View {
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Text("Mixed Content Protection")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    explanationSection(
                        title: "What is Mixed Content?",
                        content: "Mixed content occurs when a secure HTTPS page attempts to load resources (images, scripts, stylesheets) over insecure HTTP connections. This creates a security vulnerability that undermines the protection that HTTPS provides."
                    )
                    
                    explanationSection(
                        title: "Security Risks",
                        content: "HTTP resources on HTTPS pages can be intercepted, modified, or replaced by attackers. This allows for man-in-the-middle attacks, data theft, and injection of malicious content."
                    )
                    
                    explanationSection(
                        title: "Policy Options",
                        content: """
                        • Block All: Maximum security - prevents all HTTP resources from loading
                        • Warn User: Shows warnings but allows user choice
                        • Allow All: Permits mixed content but shows security indicators (not recommended)
                        """
                    )
                    
                    explanationSection(
                        title: "Recommended Setting",
                        content: "For maximum security, use 'Block All Mixed Content'. For compatibility with older websites, use 'Warn About Mixed Content' and make decisions on a case-by-case basis."
                    )
                }
                .padding(.vertical)
            }
        }
        .padding(24)
        .frame(width: 500, height: 600)
    }
    
    private func explanationSection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            
            Text(content)
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Preview

#Preview {
    SecuritySettingsView()
        .frame(width: 800, height: 600)
}