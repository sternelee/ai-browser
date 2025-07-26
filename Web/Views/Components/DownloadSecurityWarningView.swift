import SwiftUI
import os.log

/**
 * DownloadSecurityWarningView
 * 
 * Comprehensive security warning interface for dangerous downloads.
 * 
 * Key Features:
 * - Risk-based warning UI with appropriate severity indicators
 * - Detailed threat information and security recommendations
 * - User confirmation flow with informed consent
 * - Integration with FileSecurityValidator and MalwareScanner
 * - Beautiful glass morphism design matching browser aesthetic
 * - Accessibility support with VoiceOver descriptions
 * 
 * Security Design:
 * - Clear security messaging with appropriate visual cues
 * - Progressive disclosure of technical details
 * - Secure default actions (cancel/block)
 * - Comprehensive logging of user security decisions
 * - Integration with system security frameworks
 */
struct DownloadSecurityWarningView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var logger = SecurityLogger()
    
    // MARK: - Warning Configuration
    
    let securityAnalysis: FileSecurityValidator.FileSecurityAnalysis
    let scanResult: MalwareScanner.ScanResult?
    let onProceed: () -> Void
    let onCancel: () -> Void
    
    // MARK: - UI State
    
    @State private var showTechnicalDetails = false
    @State private var userAcknowledgedRisks = false
    @State private var isProcessing = false
    
    // MARK: - Computed Properties
    
    private var warningTitle: String {
        if securityAnalysis.isBlocked {
            return "Download Blocked"
        } else {
            switch securityAnalysis.riskLevel {
            case .critical:
                return "Critical Security Warning"
            case .high:
                return "High Risk Download"
            case .medium:
                return "Security Warning"
            case .low:
                return "Low Risk Notice"
            case .safe:
                return "Download Confirmation"
            }
        }
    }
    
    private var warningIcon: String {
        if securityAnalysis.isBlocked {
            return "xmark.shield.fill"
        } else {
            switch securityAnalysis.riskLevel {
            case .critical:
                return "exclamationmark.triangle.fill"
            case .high:
                return "exclamationmark.triangle.fill"
            case .medium:
                return "exclamationmark.circle.fill"
            case .low:
                return "info.circle.fill"
            case .safe:
                return "checkmark.shield.fill"
            }
        }
    }
    
    private var warningColor: Color {
        Color(securityAnalysis.riskLevel.color)
    }
    
    private var canProceed: Bool {
        return !securityAnalysis.isBlocked && (securityAnalysis.riskLevel <= .medium || userAcknowledgedRisks)
    }
    
    var body: some View {
        ZStack {
            // Glass morphism background
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with warning icon and title
                headerView
                
                // Main content area
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // File information
                        fileInfoSection
                        
                        // Security analysis
                        securityAnalysisSection
                        
                        // Malware scan results (if available)
                        if let scanResult = scanResult {
                            malwareScanSection(scanResult)
                        }
                        
                        // Risk acknowledgment (for high-risk files)
                        if securityAnalysis.riskLevel >= .high && !securityAnalysis.isBlocked {
                            riskAcknowledgmentSection
                        }
                        
                        // Technical details (expandable)
                        technicalDetailsSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                }
                
                // Bottom action buttons
                actionButtonsView
            }
        }
        .frame(width: 500, height: securityAnalysis.isBlocked ? 400 : 550)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .onAppear {
            logSecurityWarningShown()
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        VStack(spacing: 12) {
            // Warning icon
            Image(systemName: warningIcon)
                .font(.system(size: 48, weight: .medium))
                .foregroundColor(warningColor)
                .symbolRenderingMode(.hierarchical)
            
            // Title
            Text(warningTitle)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
            
            // Subtitle with filename
            Text(securityAnalysis.filename)
                .font(.headline)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }
    
    // MARK: - File Information Section
    
    private var fileInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("File Information", systemImage: "doc.fill")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "File Type", value: securityAnalysis.fileExtension.uppercased())
                
                if let uti = securityAnalysis.detectedUTI {
                    InfoRow(label: "System Type", value: uti.localizedDescription ?? uti.identifier)
                }
                
                if let mimeType = securityAnalysis.mimeType {
                    InfoRow(label: "MIME Type", value: mimeType)
                }
                
                if securityAnalysis.fileSize > 0 {
                    InfoRow(label: "File Size", value: ByteCountFormatter().string(fromByteCount: securityAnalysis.fileSize))
                }
                
                InfoRow(label: "Source", value: securityAnalysis.url.host ?? "Unknown")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .cornerRadius(12)
    }
    
    // MARK: - Security Analysis Section
    
    private var securityAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Security Analysis", systemImage: "shield.fill")
                .font(.headline)
                .foregroundColor(.primary)
            
            // Risk level indicator
            HStack {
                RiskLevelIndicator(riskLevel: securityAnalysis.riskLevel)
                Spacer()
                Text(securityAnalysis.riskLevel.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(warningColor)
            }
            
            // Risk reasons
            if !securityAnalysis.riskReasons.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Security Concerns:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    ForEach(securityAnalysis.riskReasons, id: \.self) { reason in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                                .padding(.top, 2)
                            Text(reason)
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 8)
            }
            
            // Recommendations
            if !securityAnalysis.recommendations.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recommendations:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.top, 8)
                    
                    ForEach(securityAnalysis.recommendations, id: \.self) { recommendation in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .font(.caption)
                                .foregroundColor(.blue)
                                .padding(.top, 2)
                            Text(recommendation)
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .cornerRadius(12)
    }
    
    // MARK: - Malware Scan Section
    
    private func malwareScanSection(_ scanResult: MalwareScanner.ScanResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Malware Scan Results", systemImage: "checkmark.shield.fill")
                .font(.headline)
                .foregroundColor(.primary)
            
            switch scanResult {
            case .clean:
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("No malware detected")
                        .font(.subheadline)
                }
                
            case .suspicious(let threat), .malicious(let threat):
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(Color(threat.severity.color))
                        Text("\(threat.threatType.displayName) Detected")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    
                    Text(threat.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Detection Method: \(threat.detectionMethod.displayName)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("Confidence: \(Int(threat.confidence * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
            case .error(let reason):
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text("Scan Error: \(reason)")
                        .font(.caption)
                }
                
            case .timeout:
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.orange)
                    Text("Scan timed out - file may be too large")
                        .font(.caption)
                }
                
            case .skipped(let reason):
                HStack {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.secondary)
                    Text("Scan skipped: \(reason)")
                        .font(.caption)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .cornerRadius(12)
    }
    
    // MARK: - Risk Acknowledgment Section
    
    private var riskAcknowledgmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Risk Acknowledgment", systemImage: "hand.raised.fill")
                .font(.headline)
                .foregroundColor(.red)
            
            Toggle(isOn: $userAcknowledgedRisks) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("I understand the security risks")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("This file may be dangerous and could harm your system")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(CheckboxToggleStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Technical Details Section
    
    private var technicalDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { showTechnicalDetails.toggle() }) {
                HStack {
                    Label("Technical Details", systemImage: "info.circle.fill")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(showTechnicalDetails ? 90 : 0))
                        .animation(.easeInOut(duration: 0.2), value: showTechnicalDetails)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            if showTechnicalDetails {
                VStack(alignment: .leading, spacing: 8) {
                    InfoRow(label: "Scan Timestamp", value: DateFormatter.localizedString(from: securityAnalysis.scanTimestamp, dateStyle: .medium, timeStyle: .medium))
                    InfoRow(label: "Is Executable", value: securityAnalysis.isExecutable ? "Yes" : "No")
                    InfoRow(label: "Is Archive", value: securityAnalysis.isArchive ? "Yes" : "No")
                    InfoRow(label: "Is Spoofed", value: securityAnalysis.isSpoofed ? "Yes" : "No")
                    InfoRow(label: "Digital Signature", value: securityAnalysis.digitalSignatureStatus.displayName)
                    InfoRow(label: "Full URL", value: securityAnalysis.url.absoluteString)
                    
                    if let uti = securityAnalysis.detectedUTI {
                        InfoRow(label: "UTI Identifier", value: uti.identifier)
                    }
                }
                .transition(.opacity.combined(with: .slide))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .cornerRadius(12)
    }
    
    // MARK: - Action Buttons
    
    private var actionButtonsView: some View {
        HStack(spacing: 16) {
            // Cancel/Block button
            Button(action: handleCancel) {
                HStack {
                    Image(systemName: securityAnalysis.isBlocked ? "xmark.shield" : "xmark")
                    Text(securityAnalysis.isBlocked ? "Close" : "Cancel Download")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.regularMaterial)
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Proceed button (if allowed)
            if !securityAnalysis.isBlocked {
                Button(action: handleProceed) {
                    HStack {
                        if isProcessing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.down.circle")
                        }
                        Text("Download Anyway")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(canProceed ? Color.blue : Color.gray.opacity(0.3))
                    .foregroundColor(canProceed ? .white : .secondary)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!canProceed || isProcessing)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }
    
    // MARK: - Actions
    
    private func handleCancel() {
        logSecurityDecision(action: "cancelled")
        onCancel()
        dismiss()
    }
    
    private func handleProceed() {
        guard canProceed else { return }
        
        isProcessing = true
        logSecurityDecision(action: "proceeded")
        
        // Add small delay for user feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            onProceed()
            dismiss()
        }
    }
    
    // MARK: - Logging
    
    private func logSecurityWarningShown() {
        logger.logSecurityEvent(
            event: "security_warning_shown",
            details: [
                "filename": securityAnalysis.filename,
                "riskLevel": securityAnalysis.riskLevel.displayName,
                "isBlocked": securityAnalysis.isBlocked,
                "riskReasons": securityAnalysis.riskReasons,
                "isExecutable": securityAnalysis.isExecutable,
                "scanResult": scanResult?.severity.displayName ?? "none"
            ]
        )
    }
    
    private func logSecurityDecision(action: String) {
        logger.logSecurityEvent(
            event: "security_decision",
            details: [
                "action": action,
                "filename": securityAnalysis.filename,
                "riskLevel": securityAnalysis.riskLevel.displayName,
                "userAcknowledgedRisks": userAcknowledgedRisks,
                "showedTechnicalDetails": showTechnicalDetails
            ]
        )
    }
}

// MARK: - Supporting Views

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.caption)
                .lineLimit(nil)
                .textSelection(.enabled)
        }
    }
}

struct RiskLevelIndicator: View {
    let riskLevel: FileSecurityValidator.SecurityRisk
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                Rectangle()
                    .fill(index < riskLevel.rawValue ? Color(riskLevel.color) : Color.gray.opacity(0.3))
                    .frame(width: 4, height: 16)
                    .cornerRadius(2)
            }
        }
    }
}

struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            Button(action: { configuration.isOn.toggle() }) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .foregroundColor(configuration.isOn ? .blue : .secondary)
                    .font(.title3)
            }
            .buttonStyle(PlainButtonStyle())
            
            configuration.label
        }
    }
}

// MARK: - Security Logger

@MainActor
class SecurityLogger: ObservableObject {
    private let logger = Logger(subsystem: "com.example.Web", category: "DownloadSecurity")
    
    func logSecurityEvent(event: String, details: [String: Any]) {
        logger.info("Security Event: \(event) - \(details)")
        
        // Post notification for security monitoring
        NotificationCenter.default.post(
            name: .downloadSecurityEvent,
            object: nil,
            userInfo: [
                "event": event,
                "details": details,
                "timestamp": Date()
            ]
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let downloadSecurityEvent = Notification.Name("downloadSecurityEvent")
}

// MARK: - Preview

#Preview {
    let analysis = FileSecurityValidator.FileSecurityAnalysis(
        url: URL(string: "https://example.com/suspicious-file.exe")!,
        filename: "suspicious-file.exe",
        fileExtension: "exe",
        detectedUTI: nil,
        mimeType: "application/octet-stream",
        fileSize: 1024000,
        riskLevel: .high,
        riskReasons: ["Executable file from unknown source", "Suspicious filename pattern"],
        recommendations: ["Verify file source", "Scan with additional tools"],
        isExecutable: true,
        isArchive: false,
        isSpoofed: false,
        digitalSignatureStatus: .unsigned,
        scanTimestamp: Date()
    )
    
    let threat = MalwareScanner.ThreatDetails(
        threatType: .suspicious,
        severity: .medium,
        description: "Suspicious behavioral patterns detected",
        detectionMethod: .heuristic,
        confidence: 0.75,
        recommendations: ["Verify source"],
        technicalDetails: [:],
        detectionTime: Date()
    )
    
    DownloadSecurityWarningView(
        securityAnalysis: analysis,
        scanResult: .suspicious(threat: threat),
        onProceed: {},
        onCancel: {}
    )
}