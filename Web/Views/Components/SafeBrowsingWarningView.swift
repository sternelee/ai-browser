import SwiftUI
import WebKit

/**
 * SafeBrowsingWarningView
 * 
 * Comprehensive threat warning interface for Safe Browsing detections.
 * Provides clear, educational warnings for malware, phishing, and other threats
 * detected by Google Safe Browsing API with user override capabilities.
 * 
 * Design Principles:
 * - Clear threat communication without technical jargon
 * - Educational content about security risks
 * - Strong emphasis on the safe option (going back)
 * - Progressive disclosure for advanced options
 * - Consistent visual design with existing SecurityWarningView
 */
struct SafeBrowsingWarningView: View {
    let threat: SafeBrowsingManager.ThreatMatch
    let url: URL
    
    @State private var showTechnicalDetails = false
    @State private var userUnderstandsRisk = false
    @State private var isShowingAdvancedOptions = false
    @Environment(\.dismiss) private var dismiss
    
    // Completion handlers
    let onGoBack: () -> Void
    let onProceedWithRisk: () -> Void
    let onAddException: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with threat-specific icon and primary message
            headerSection
            
            // Main warning content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    threatDetailsSection
                    riskExplanationSection
                    technicalDetailsSection
                    
                    if isShowingAdvancedOptions {
                        advancedOptionsSection
                    }
                }
                .padding(24)
            }
            
            // Action buttons
            actionButtonsSection
        }
        .frame(width: 520, height: isShowingAdvancedOptions ? 700 : 600)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(threat.severity.color).opacity(0.3), lineWidth: 2)
        )
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.3), radius: 20)
    }
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            // Threat-specific warning icon
            Image(systemName: threatIconName)
                .font(.system(size: 56, weight: .regular))
                .foregroundColor(Color(threat.severity.color))
            
            // Primary threat message
            VStack(spacing: 8) {
                Text("Dangerous Website Blocked")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("This website contains \(threat.threatType.userFriendlyName.lowercased()) and has been blocked for your safety")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            
            // URL information with truncation
            VStack(spacing: 4) {
                Text(displayURL)
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                
                Text("Blocked by Safe Browsing")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color(threat.severity.color).opacity(0.2))
                    .cornerRadius(12)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .padding(.top, 32)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .background(
            LinearGradient(
                colors: [
                    Color(threat.severity.color).opacity(0.15),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    private var threatDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("What is \(threat.threatType.userFriendlyName)?", systemImage: threatTypeIcon)
                .font(.headline)
                .foregroundColor(Color(threat.severity.color))
            
            Text(threatDescription)
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            
            // Severity indicator
            HStack {
                Text("Threat Level:")
                    .font(.callout)
                    .foregroundColor(.secondary)
                
                Text(severityDescription)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundColor(Color(threat.severity.color))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color(threat.severity.color).opacity(0.2))
                    .cornerRadius(4)
                
                Spacer()
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }
    
    private var riskExplanationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Why This is Dangerous", systemImage: "exclamationmark.shield.fill")
                .font(.headline)
                .foregroundColor(.red)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(riskDescriptions, id: \.text) { risk in
                    riskItem(risk.text, risk.icon)
                }
            }
            
            // Additional context for threat type
            if !additionalWarning.isEmpty {
                Divider()
                    .padding(.vertical, 8)
                
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.orange)
                        .frame(width: 16)
                    
                    Text(additionalWarning)
                        .font(.callout)
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(16)
        .background(Color.red.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.2), lineWidth: 1)
        )
    }
    
    private var technicalDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { showTechnicalDetails.toggle() }) {
                HStack {
                    Label("Technical Details", systemImage: "info.circle")
                        .font(.headline)
                    
                    Spacer()
                    
                    Image(systemName: showTechnicalDetails ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            
            if showTechnicalDetails {
                VStack(alignment: .leading, spacing: 8) {
                    technicalDetailRow("URL", url.absoluteString)
                    technicalDetailRow("Threat Type", threat.threatType.rawValue)
                    technicalDetailRow("Severity", threat.severity.rawValue.description)
                    technicalDetailRow("Detected At", formatDate(threat.detectedAt))
                    technicalDetailRow("Detection Source", "Google Safe Browsing")
                    
                    if let host = url.host {
                        technicalDetailRow("Host", host)
                    }
                    
                    if url.port != nil {
                        technicalDetailRow("Port", "\(url.port!)")
                    }
                }
                .font(.system(size: 12, design: .monospaced))
                .padding(12)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            }
        }
    }
    
    private var advancedOptionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Advanced Options", systemImage: "gearshape.fill")
                .font(.headline)
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 12) {
                Toggle("I understand this website is dangerous and want to proceed anyway", isOn: $userUnderstandsRisk)
                    .toggleStyle(.checkbox)
                
                if userUnderstandsRisk {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("⚠️ Proceeding to this website may:")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("• Install malware on your computer")
                            Text("• Steal your passwords and personal information")
                            Text("• Track your browsing activity")
                            Text("• Inject malicious content into web pages")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 8)
                        
                        Text("Only proceed if you absolutely trust this website.")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.red)
                            .padding(.top, 4)
                    }
                    .padding(.leading, 24)
                }
            }
            
            Divider()
            
            // Exception options
            VStack(alignment: .leading, spacing: 8) {
                Text("Exception Options")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("You can add an exception to always allow this website, but this will bypass future security checks and may put you at risk.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color.orange.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }
    
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            Divider()
            
            HStack(spacing: 12) {
                // Primary action: Go back (safe option)
                Button(action: onGoBack) {
                    HStack {
                        Image(systemName: "arrow.left.circle.fill")
                        Text("Go Back to Safety")
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .cornerRadius(8)
                }
                .keyboardShortcut(.escape)
                .keyboardShortcut(.return)
                
                // Advanced button
                Button(action: { isShowingAdvancedOptions.toggle() }) {
                    Text(isShowingAdvancedOptions ? "Hide Advanced" : "Advanced...")
                        .font(.system(size: 16))
                        .frame(minWidth: 120)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderless)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            
            // Risky actions (only shown in advanced mode)
            if isShowingAdvancedOptions {
                HStack(spacing: 12) {
                    // Temporary proceed
                    Button(action: onProceedWithRisk) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("Proceed Anyway")
                        }
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.orange)
                        .cornerRadius(8)
                    }
                    .disabled(!userUnderstandsRisk)
                    
                    // Always allow exception
                    Button(action: onAddException) {
                        HStack {
                            Image(systemName: "checkmark.shield.fill")
                            Text("Always Allow")
                        }
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red)
                        .cornerRadius(8)
                    }
                    .disabled(!userUnderstandsRisk)
                }
            }
        }
        .padding(16)
    }
    
    // MARK: - Helper Views
    
    private func technicalDetailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text("\(label):")
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .foregroundColor(.primary)
                .textSelection(.enabled)
            Spacer()
        }
    }
    
    private func riskItem(_ text: String, _ icon: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.red)
                .frame(width: 16)
            Text(text)
                .font(.callout)
                .foregroundColor(.primary)
        }
    }
    
    // MARK: - Computed Properties
    
    private var displayURL: String {
        let urlString = url.absoluteString
        if urlString.count > 60 {
            return String(urlString.prefix(60)) + "..."
        }
        return urlString
    }
    
    private var threatIconName: String {
        switch threat.threatType {
        case .malware, .potentiallyHarmfulApplication:
            return "shield.slash.fill"
        case .socialEngineering:
            return "person.crop.rectangle.badge.xmark"
        case .unwantedSoftware:
            return "doc.badge.gearshape.fill"
        }
    }
    
    private var threatTypeIcon: String {
        switch threat.threatType {
        case .malware:
            return "ant.fill"
        case .socialEngineering:
            return "person.crop.rectangle.badge.xmark"
        case .unwantedSoftware:
            return "trash.fill"
        case .potentiallyHarmfulApplication:
            return "app.badge.checkmark"
        }
    }
    
    private var threatDescription: String {
        switch threat.threatType {
        case .malware:
            return "Malware is malicious software designed to damage your computer, steal your data, or gain unauthorized access to your system. This website is known to distribute or host malware that could infect your device."
            
        case .socialEngineering:
            return "Phishing websites trick you into revealing sensitive information like passwords, credit card numbers, or personal details by impersonating legitimate sites. This website has been identified as attempting to steal your personal information."
            
        case .unwantedSoftware:
            return "Unwanted software includes programs that may track your activity, display unwanted ads, or change your browser settings without permission. This website is known to distribute such software."
            
        case .potentiallyHarmfulApplication:
            return "This website hosts applications that may be harmful to your device or privacy. These applications might perform unwanted actions or compromise your system's security."
        }
    }
    
    private var severityDescription: String {
        switch threat.severity {
        case .low:
            return "Low Risk"
        case .medium:
            return "Medium Risk"
        case .high:
            return "High Risk"
        case .critical:
            return "Critical Risk"
        }
    }
    
    private var riskDescriptions: [(text: String, icon: String)] {
        switch threat.threatType {
        case .malware, .potentiallyHarmfulApplication:
            return [
                ("Malware could be installed on your computer", "ant.fill"),
                ("Your files and personal data could be corrupted or stolen", "folder.badge.minus"),
                ("Your computer could become part of a botnet", "network.badge.shield.half.filled"),
                ("Ransomware could encrypt your files", "lock.fill")
            ]
            
        case .socialEngineering:
            return [
                ("Your passwords and login credentials could be stolen", "key.slash"),
                ("Your credit card and banking information could be compromised", "creditcard.trianglebadge.exclamationmark"),
                ("Your personal identity could be stolen", "person.crop.rectangle.badge.xmark"),
                ("You could be tricked into making fraudulent payments", "dollarsign.circle.fill")
            ]
            
        case .unwantedSoftware:
            return [
                ("Unwanted ads and pop-ups could appear frequently", "rectangle.badge.plus"),
                ("Your browser settings could be changed without permission", "gearshape.fill"),
                ("Your browsing activity could be tracked", "eye.slash"),
                ("Your computer performance could be degraded", "speedometer")
            ]
        }
    }
    
    private var additionalWarning: String {
        switch threat.threatType {
        case .socialEngineering:
            return "Phishing sites often look identical to legitimate websites. Even if this site appears trustworthy, it has been confirmed as malicious by Google Safe Browsing."
            
        case .malware, .potentiallyHarmfulApplication:
            return "Malware infections can happen just by visiting a website, even without downloading anything. Your device could be compromised immediately."
            
        case .unwantedSoftware:
            return "Unwanted software often bundles with legitimate downloads and can be difficult to remove once installed."
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Container View for Sheet Presentation

struct SafeBrowsingWarningSheet: View {
    @State private var isPresented = false
    @State private var currentThreat: SafeBrowsingManager.ThreatMatch?
    @State private var currentURL: URL?
    
    var body: some View {
        Color.clear
            .sheet(isPresented: $isPresented) {
                if let threat = currentThreat,
                   let url = currentURL {
                    SafeBrowsingWarningView(
                        threat: threat,
                        url: url,
                        onGoBack: {
                            // Handle go back (safe option)
                            isPresented = false
                        },
                        onProceedWithRisk: {
                            // Handle proceed with risk
                            NotificationCenter.default.post(
                                name: .safeBrowsingUserOverride,
                                object: nil,
                                userInfo: [
                                    "action": "proceed",
                                    "url": url,
                                    "threat": threat
                                ]
                            )
                            isPresented = false
                        },
                        onAddException: {
                            // Handle always allow
                            SafeBrowsingManager.shared.addUserOverride(for: url)
                            NotificationCenter.default.post(
                                name: .safeBrowsingUserOverride,
                                object: nil,
                                userInfo: [
                                    "action": "exception",
                                    "url": url,
                                    "threat": threat
                                ]
                            )
                            isPresented = false
                        }
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .safeBrowsingThreatDetected)) { notification in
                if let threat = notification.userInfo?["threat"] as? SafeBrowsingManager.ThreatMatch,
                   let url = notification.userInfo?["url"] as? URL {
                    
                    currentThreat = threat
                    currentURL = url
                    isPresented = true
                }
            }
    }
}

// MARK: - Preview

#Preview {
    let mockThreat = SafeBrowsingManager.ThreatMatch(
        threatType: .socialEngineering,
        url: URL(string: "https://evil-phishing-site.com/fake-bank-login")!,
        detectedAt: Date(),
        severity: .critical,
        isUserOverridden: false
    )
    
    SafeBrowsingWarningView(
        threat: mockThreat,
        url: URL(string: "https://evil-phishing-site.com/fake-bank-login")!,
        onGoBack: {},
        onProceedWithRisk: {},
        onAddException: {}
    )
    .padding()
}