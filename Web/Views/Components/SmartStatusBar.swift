import SwiftUI
import AppKit

// Enhanced smart status bar for next-gen macOS UX with contextual actions
struct SmartStatusBar: View {
    @ObservedObject var tab: Tab
    let hoveredLink: String?
    @State private var statusMessage: String = ""
    @State private var statusType: StatusType = .hidden
    @State private var progress: Double = 0
    @State private var contextualActions: [ContextualAction] = []
    @State private var currentHoveredURL: URL?
    
    enum StatusType {
        case hidden, loading, linkHover, download, security, success, error
    }
    
    struct ContextualAction {
        let id = UUID()
        let icon: String
        let title: String
        let action: () -> Void
    }
    
    var body: some View {
        Group {
            if statusType != .hidden {
                HStack(spacing: 12) {
                    // Status icon with enhanced animations
                    statusIcon
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(statusColor)
                        .scaleEffect(statusType == .loading ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: statusType)
                    
                    // Status text with better styling
                    Text(statusMessage)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .textSelection(.enabled) // Allow text selection
                    
                    Spacer()
                    
                    // Contextual actions
                    if !contextualActions.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(contextualActions, id: \.id) { action in
                                Button(action: action.action) {
                                    Image(systemName: action.icon)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(ContextualActionButtonStyle())
                                .help(action.title)
                            }
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                    
                    // Progress indicator for loading with enhanced styling
                    if statusType == .loading || statusType == .download {
                        ProgressView(value: progress)
                            .progressViewStyle(EnhancedLinearProgressStyle())
                            .frame(width: 60)
                            .scaleEffect(0.8)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(statusBarBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                .fixedSize(horizontal: true, vertical: false)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: statusType)
            }
        }
        .onAppear {
            updateForHoveredLink()
        }
        .onChange(of: hoveredLink) { _, _ in
            updateForHoveredLink()
        }
        // Removed auto-loading display - status bar only shows for link hover and explicit states
        .onChange(of: tab.estimatedProgress) { _, newProgress in
            progress = newProgress
        }
    }
    
    private func updateForHoveredLink() {
        if let linkString = hoveredLink, !linkString.isEmpty {
            showLinkHover(linkString)
        } else {
            hideLinkHover()
        }
    }
    
    private var statusIcon: some View {
        Group {
            switch statusType {
            case .hidden:
                EmptyView()
            case .loading:
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(progress * 360))
            case .linkHover:
                Image(systemName: "link")
            case .download:
                Image(systemName: "arrow.down.circle")
            case .security:
                Image(systemName: "lock.shield")
            case .success:
                Image(systemName: "checkmark.circle")
            case .error:
                Image(systemName: "exclamationmark.triangle")
            }
        }
    }
    
    private var statusColor: Color {
        switch statusType {
        case .hidden, .loading, .linkHover:
            return .primary
        case .download:
            return .blue
        case .security, .success:
            return .green
        case .error:
            return .red
        }
    }
    
    private var statusBarBackground: some View {
        ZStack {
            // Base material
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
            
            // Dynamic color overlay based on status type
            RoundedRectangle(cornerRadius: 8)
                .fill(statusOverlayColor.opacity(0.1))
                .animation(.easeInOut(duration: 0.3), value: statusType)
        }
    }
    
    private var statusOverlayColor: Color {
        switch statusType {
        case .download:
            return .blue
        case .security, .success:
            return .green
        case .error:
            return .red
        default:
            return .clear
        }
    }
    
    // MARK: - Public Methods
    func showLinkHover(_ urlString: String) {
        // Show the full URL instead of just the domain
        updateStatus(type: .linkHover, message: urlString)
        
        // Store current URL and create contextual actions
        if let url = URL(string: urlString) {
            currentHoveredURL = url
            contextualActions = createLinkContextualActions(for: url)
        } else {
            currentHoveredURL = nil
            contextualActions = []
        }
    }
    
    func hideLinkHover() {
        currentHoveredURL = nil
        contextualActions = []
        hideStatusWithDelay(delay: 0.5)
    }
    
    func showDownload(filename: String, progress: Double) {
        self.progress = progress
        updateStatus(type: .download, message: "Downloading \(filename)")
        
        // Add download-specific actions
        contextualActions = createDownloadContextualActions(filename: filename)
    }
    
    func showSecurity(message: String) {
        updateStatus(type: .security, message: message)
        
        contextualActions = [
            ContextualAction(icon: "info.circle", title: "Security Details") {
                // Show security details sheet
                showSecurityDetails()
            }
        ]
    }
    
    func showSuccess(message: String) {
        updateStatus(type: .success, message: message)
        contextualActions = []
        hideStatusWithDelay(delay: 2.0)
    }
    
    func showError(message: String) {
        updateStatus(type: .error, message: message)
        
        contextualActions = [
            ContextualAction(icon: "arrow.clockwise", title: "Retry") {
                // Retry the failed action
                retryLastAction()
            }
        ]
    }
    
    func showLoading() {
        updateStatus(type: .loading, message: "Loading...")
        contextualActions = []
    }
    
    // MARK: - Private Methods
    private func updateStatus(type: StatusType, message: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            statusType = type
            statusMessage = message
        }
    }
    
    private func hideStatusWithDelay(delay: TimeInterval = 2.0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.easeOut(duration: 0.3)) {
                statusType = .hidden
                contextualActions = []
            }
        }
    }
    
    // MARK: - Contextual Actions
    private func createLinkContextualActions(for url: URL) -> [ContextualAction] {
        return [
            ContextualAction(icon: "doc.on.doc", title: "Copy Link") {
                copyToClipboard(url.absoluteString)
                showSuccess(message: "Link copied to clipboard")
            },
            ContextualAction(icon: "safari", title: "Open in Safari") {
                NSWorkspace.shared.open(url)
                showSuccess(message: "Opened in Safari")
            },
            ContextualAction(icon: "plus.square", title: "Open in New Tab") {
                openInNewTab(url)
                showSuccess(message: "Opened in new tab")
            }
        ]
    }
    
    private func createDownloadContextualActions(filename: String) -> [ContextualAction] {
        return [
            ContextualAction(icon: "folder", title: "Show in Finder") {
                showDownloadInFinder(filename)
            },
            ContextualAction(icon: "pause", title: "Pause Download") {
                pauseDownload(filename)
            },
            ContextualAction(icon: "xmark.circle", title: "Cancel Download") {
                cancelDownload(filename)
            }
        ]
    }
    
    // MARK: - Action Implementations
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    
    private func openInNewTab(_ url: URL) {
        NotificationCenter.default.post(
            name: .createNewTabWithURL,
            object: url
        )
    }
    
    private func showDownloadInFinder(_ filename: String) {
        // Get downloads folder
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        if let downloadsURL = downloadsURL {
            let fileURL = downloadsURL.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: downloadsURL.path)
            } else {
                NSWorkspace.shared.open(downloadsURL)
            }
        }
    }
    
    private func pauseDownload(_ filename: String) {
        // Post notification to pause download
        NotificationCenter.default.post(
            name: .pauseDownload,
            object: filename
        )
    }
    
    private func cancelDownload(_ filename: String) {
        // Post notification to cancel download
        NotificationCenter.default.post(
            name: .cancelDownload,
            object: filename
        )
    }
    
    private func showSecurityDetails() {
        // Post notification to show security details
        NotificationCenter.default.post(
            name: .showSecurityDetails,
            object: tab
        )
    }
    
    private func retryLastAction() {
        // Post notification to retry last failed action
        NotificationCenter.default.post(
            name: .retryLastAction,
            object: tab
        )
    }
}

// MARK: - Supporting Views and Styles
struct ContextualActionButtonStyle: ButtonStyle {
    @State private var isHovered = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(4)
            .background(
                Circle()
                    .fill(.quaternary)
                    .opacity(configuration.isPressed ? 0.8 : (isHovered ? 1.0 : 0.6))
            )
            .scaleEffect(configuration.isPressed ? 0.9 : (isHovered ? 1.05 : 1.0))
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.2), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

struct EnhancedLinearProgressStyle: ProgressViewStyle {
    @State private var gradientOffset: CGFloat = -1
    
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 2)
                    .fill(.quaternary)
                    .frame(height: 3)
                
                // Progress with animated gradient
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.7), .purple.opacity(0.8), .blue.opacity(0.7)],
                            startPoint: UnitPoint(x: gradientOffset, y: 0),
                            endPoint: UnitPoint(x: gradientOffset + 0.4, y: 0)
                        )
                    )
                    .frame(
                        width: geometry.size.width * (configuration.fractionCompleted ?? 0),
                        height: 3
                    )
                    .animation(.easeInOut(duration: 0.2), value: configuration.fractionCompleted)
                    .onAppear {
                        withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                            gradientOffset = 1
                        }
                    }
            }
        }
    }
}

// MARK: - Notification Extensions
extension Notification.Name {
    static let pauseDownload = Notification.Name("pauseDownload")
    static let cancelDownload = Notification.Name("cancelDownload")
    static let showSecurityDetails = Notification.Name("showSecurityDetails")
    static let retryLastAction = Notification.Name("retryLastAction")
}

#Preview {
    SmartStatusBar(tab: Tab(), hoveredLink: "https://example.com")
        .padding()
}