import SwiftUI
import AppKit

/**
 * MixedContentWarningView - Educational Security Warning for Mixed Content
 * 
 * This view provides comprehensive user education about mixed content security risks
 * and allows users to make informed decisions about allowing potentially insecure content.
 * 
 * Security Features:
 * - Clear explanation of mixed content risks
 * - Visual representation of security context degradation
 * - User education about MITM attacks and data interception
 * - Policy-aware warning system
 * - Progressive disclosure of technical details
 * - Integration with mixed content policy management
 */
struct MixedContentWarningView: View {
    let warningType: WarningType
    let url: URL
    let tabID: UUID
    let onUserDecision: (UserDecision) -> Void
    
    @State private var showTechnicalDetails = false
    @State private var userAcknowledgedRisk = false
    @ObservedObject private var mixedContentManager = MixedContentManager.shared
    
    enum WarningType {
        case blocked
        case warning
        case allowWithRisk
        
        var title: String {
            switch self {
            case .blocked:
                return "Mixed Content Blocked"
            case .warning:
                return "Mixed Content Detected"
            case .allowWithRisk:
                return "Insecure Content Warning"
            }
        }
        
        var icon: String {
            switch self {
            case .blocked:
                return "shield.slash.fill"
            case .warning:
                return "exclamationmark.shield.fill"
            case .allowWithRisk:
                return "exclamationmark.triangle.fill"
            }
        }
        
        var iconColor: Color {
            switch self {
            case .blocked:
                return .blue
            case .warning:
                return .orange
            case .allowWithRisk:
                return .red
            }
        }
    }
    
    enum UserDecision {
        case block
        case allowOnce
        case allowAlways
        case cancel
        case openSettings
        
        var description: String {
            switch self {
            case .block: return "Block and stay secure"
            case .allowOnce: return "Allow for this page only"
            case .allowAlways: return "Allow for this site (not recommended)"
            case .cancel: return "Cancel"
            case .openSettings: return "Open security settings"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with security warning
            headerSection
            
            // Main content with explanation
            contentSection
            
            // Technical details (expandable)
            if showTechnicalDetails {
                technicalDetailsSection
                    .transition(.opacity.combined(with: .slide))
            }
            
            // Action buttons
            actionButtonsSection
        }
        .frame(width: 480, height: showTechnicalDetails ? 600 : 420)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(radius: 20)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.separator.opacity(0.3), lineWidth: 1)
        )
        .onAppear {
            logWarningShown()
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            // Warning icon and title
            HStack(spacing: 12) {
                Image(systemName: warningType.icon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(warningType.iconColor)
                    .symbolEffect(.bounce, value: warningType)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(warningType.title)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text(url.host ?? "Unknown site")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fontDesign(.monospaced)
                }
                
                Spacer()
            }
            
            // Security context visualization
            securityContextVisualization
        }
        .padding(.top, 24)
        .padding(.horizontal, 24)
    }
    
    // MARK: - Security Context Visualization
    
    private var securityContextVisualization: some View {
        HStack(spacing: 12) {
            // HTTPS Page (secure)
            VStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.title3)
                    .foregroundColor(.green)
                
                Text("HTTPS Page")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.green)
            }
            
            // Arrow showing connection
            Image(systemName: "arrow.right")
                .foregroundColor(.secondary)
            
            // Mixed content warning
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundColor(.orange)
                
                Text("HTTP Resources")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.orange)
            }
            
            // Equals degraded security
            Image(systemName: "equal")
                .foregroundColor(.secondary)
            
            // Final result
            VStack(spacing: 8) {
                Image(systemName: "lock.open.fill")
                    .font(.title3)
                    .foregroundColor(.red)
                
                Text("Degraded Security")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.1))
        )
    }
    
    // MARK: - Content Section
    
    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Main warning text
            Text(warningMessage)
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            
            // Risk explanation
            VStack(alignment: .leading, spacing: 12) {
                Label("Security Risks", systemImage: "exclamationmark.shield")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.red)
                
                VStack(alignment: .leading, spacing: 8) {
                    riskItem(
                        icon: "network",
                        title: "Man-in-the-Middle Attacks",
                        description: "HTTP resources can be intercepted and modified by attackers"
                    )
                    
                    riskItem(
                        icon: "eye.slash",
                        title: "Data Interception",
                        description: "Information sent to HTTP resources is not encrypted"
                    )
                    
                    riskItem(
                        icon: "lock.open",
                        title: "False Security Indicator",
                        description: "The page appears secure but contains insecure elements"
                    )
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.red.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.red.opacity(0.2), lineWidth: 1)
                    )
            )
            
            // Technical details toggle
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showTechnicalDetails.toggle()
                }
            }) {
                HStack {
                    Text("Technical Details")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Image(systemName: showTechnicalDetails ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .rotationEffect(.degrees(showTechnicalDetails ? 180 : 0))
                }
                .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
    
    // MARK: - Technical Details Section
    
    private var technicalDetailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Technical Information")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                VStack(alignment: .leading, spacing: 8) {
                    technicalDetailRow("URL Scheme", value: url.scheme?.uppercased() ?? "Unknown")
                    technicalDetailRow("Host", value: url.host ?? "Unknown")
                    if let port = url.port {
                        technicalDetailRow("Port", value: String(port))
                    }
                    technicalDetailRow("Current Policy", value: mixedContentManager.mixedContentPolicy.rawValue)
                    
                    if let mixedStatus = mixedContentManager.getMixedContentStatus(for: tabID) {
                        technicalDetailRow("Mixed Content Status", value: mixedStatus.mixedContentDetected ? "Detected" : "None")
                        technicalDetailRow("Only Secure Content", value: mixedStatus.hasOnlySecureContent ? "Yes" : "No")
                        if mixedStatus.violationCount > 0 {
                            technicalDetailRow("Violations", value: String(mixedStatus.violationCount))
                        }
                    }
                }
                
                // What happens next explanation
                VStack(alignment: .leading, spacing: 8) {
                    Text("What This Means:")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text(technicalExplanation)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }
    
    // MARK: - Action Buttons Section
    
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            Divider()
            
            // Risk acknowledgment checkbox (for allow actions)
            if warningType != .blocked {
                HStack {
                    Button(action: {
                        userAcknowledgedRisk.toggle()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: userAcknowledgedRisk ? "checkmark.square.fill" : "square")
                                .foregroundColor(userAcknowledgedRisk ? .blue : .secondary)
                            
                            Text("I understand the security risks")
                                .font(.callout)
                                .foregroundColor(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
            }
            
            // Primary action buttons
            HStack(spacing: 12) {
                // Cancel/Back button
                Button("Cancel") {
                    onUserDecision(.cancel)
                }
                .buttonStyle(.bordered)
                .foregroundColor(.secondary)
                
                Spacer()
                
                // Settings button
                Button("Security Settings") {
                    onUserDecision(.openSettings)
                }
                .buttonStyle(.bordered)
                .foregroundColor(.blue)
                
                // Primary action button
                primaryActionButton
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }
    
    private var primaryActionButton: some View {
        Group {
            switch warningType {
            case .blocked:
                Button("Keep Blocked") {
                    onUserDecision(.block)
                }
                .buttonStyle(.borderedProminent)
                .foregroundColor(.white)
                
            case .warning:
                HStack(spacing: 8) {
                    Button("Block Content") {
                        onUserDecision(.block)
                    }
                    .buttonStyle(.borderedProminent)
                    .foregroundColor(.white)
                    
                    Button("Allow Once") {
                        onUserDecision(.allowOnce)
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.orange)
                    .disabled(!userAcknowledgedRisk)
                }
                
            case .allowWithRisk:
                Button("Allow (Risky)") {
                    onUserDecision(.allowOnce)
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
                .disabled(!userAcknowledgedRisk)
            }
        }
    }
    
    // MARK: - Helper Views
    
    private func riskItem(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundColor(.red)
                .frame(width: 16, height: 16)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
    }
    
    private func technicalDetailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label + ":")
                .font(.callout)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.callout)
                .fontDesign(.monospaced)
                .foregroundColor(.primary)
        }
    }
    
    // MARK: - Computed Properties
    
    private var warningMessage: String {
        switch warningType {
        case .blocked:
            return "This website tried to load insecure HTTP content on a secure HTTPS page. The browser has automatically blocked this content to protect your security."
        case .warning:
            return "This secure HTTPS website is trying to load content over insecure HTTP connections. This creates a security vulnerability that could allow attackers to intercept or modify the content."
        case .allowWithRisk:
            return "You are about to allow insecure content on a secure page. This significantly reduces the security of this website and could expose you to security risks."
        }
    }
    
    private var technicalExplanation: String {
        switch warningType {
        case .blocked:
            return "The browser's mixed content policy automatically blocked HTTP resources from loading on this HTTPS page. This prevents potential security vulnerabilities while maintaining the page's secure context."
        case .warning:
            return "Mixed content occurs when a secure HTTPS page attempts to load resources (images, scripts, stylesheets) over insecure HTTP. This breaks the security guarantee that HTTPS provides."
        case .allowWithRisk:
            return "Allowing mixed content will downgrade the security of this page. Any data transmitted to HTTP resources will not be encrypted and could be intercepted by attackers on the network."
        }
    }
    
    // MARK: - Logging
    
    private func logWarningShown() {
        NSLog("🔒 Mixed content warning shown: \(warningType) for \(url.host ?? "unknown")")
        
        // Log to MixedContentManager for security monitoring
        // This would integrate with the existing logging system
    }
}

// MARK: - Mixed Content Warning Manager

/**
 * Handles the display and coordination of mixed content warnings
 */
class MixedContentWarningManager: ObservableObject {
    static let shared = MixedContentWarningManager()
    
    @Published var currentWarning: MixedContentWarningInfo?
    @Published var isShowingWarning = false
    
    private init() {
        setupNotificationObservers()
    }
    
    struct MixedContentWarningInfo {
        let warningType: MixedContentWarningView.WarningType
        let url: URL
        let tabID: UUID
        let onUserDecision: (MixedContentWarningView.UserDecision) -> Void
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .showMixedContentWarning,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleShowWarningNotification(notification)
        }
    }
    
    private func handleShowWarningNotification(_ notification: Notification) {
        guard let tabID = notification.object as? UUID,
              let userInfo = notification.userInfo,
              let typeString = userInfo["type"] as? String,
              let urlString = userInfo["url"] as? String,
              let url = URL(string: urlString) else {
            return
        }
        
        let warningType: MixedContentWarningView.WarningType
        switch typeString {
        case "blocked":
            warningType = .blocked
        case "warning":
            warningType = .warning
        case "allowWithRisk":
            warningType = .allowWithRisk
        default:
            warningType = .warning
        }
        
        showWarning(
            type: warningType,
            url: url,
            tabID: tabID
        ) { [weak self] decision in
            self?.handleUserDecision(decision, for: tabID, url: url)
        }
    }
    
    func showWarning(
        type: MixedContentWarningView.WarningType,
        url: URL,
        tabID: UUID,
        onDecision: @escaping (MixedContentWarningView.UserDecision) -> Void
    ) {
        let warningInfo = MixedContentWarningInfo(
            warningType: type,
            url: url,
            tabID: tabID,
            onUserDecision: onDecision
        )
        
        DispatchQueue.main.async {
            self.currentWarning = warningInfo
            self.isShowingWarning = true
        }
    }
    
    private func handleUserDecision(
        _ decision: MixedContentWarningView.UserDecision,
        for tabID: UUID,
        url: URL
    ) {
        switch decision {
        case .block:
            // Content remains blocked
            MixedContentManager.shared.mixedContentPolicy = .block
            
        case .allowOnce:
            // Allow mixed content for this specific tab/session
            MixedContentManager.shared.allowMixedContentForTab(tabID)
            
        case .allowAlways:
            // Change global policy (not recommended)
            MixedContentManager.shared.mixedContentPolicy = .allow
            
        case .cancel:
            // Do nothing, keep current policy
            break
            
        case .openSettings:
            // Open mixed content settings
            NotificationCenter.default.post(
                name: .showSettingsRequested,
                object: "mixedContent"
            )
        }
        
        // Hide the warning
        DispatchQueue.main.async {
            self.isShowingWarning = false
            self.currentWarning = nil
        }
        
        NSLog("🔒 User decision for mixed content: \(decision) on \(url.host ?? "unknown")")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Preview

#Preview {
    MixedContentWarningView(
        warningType: .warning,
        url: URL(string: "https://example.com")!,
        tabID: UUID(),
        onUserDecision: { decision in
            print("User decision: \(decision)")
        }
    )
    .frame(width: 600, height: 700)
    .background(Color.gray.opacity(0.1))
}