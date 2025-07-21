import SwiftUI

// Minimal smart status bar for next-gen macOS UX
struct SmartStatusBar: View {
    @ObservedObject var tab: Tab
    let hoveredLink: String?
    @State private var statusMessage: String = ""
    @State private var statusType: StatusType = .hidden
    @State private var progress: Double = 0
    
    enum StatusType {
        case hidden, loading, linkHover, download, security
    }
    
    var body: some View {
        Group {
            if statusType != .hidden {
                HStack(spacing: 12) {
                    // Status icon
                    statusIcon
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    // Status text
                    Text(statusMessage)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    
                    // Progress indicator for loading
                    if statusType == .loading || statusType == .download {
                        ProgressView(value: progress)
                            .progressViewStyle(LinearProgressViewStyle())
                            .frame(width: 50)
                            .scaleEffect(0.7)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                )
                .fixedSize(horizontal: true, vertical: false) // Adapt to content width
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
                Image(systemName: "arrow.down")
            case .security:
                Image(systemName: "lock.shield")
            }
        }
    }
    
    // MARK: - Public Methods
    func showLinkHover(_ urlString: String) {
        // Show the full URL instead of just the domain
        updateStatus(type: .linkHover, message: urlString)
    }
    
    func hideLinkHover() {
        hideStatusWithDelay(delay: 0.5)
    }
    
    func showDownload(filename: String, progress: Double) {
        self.progress = progress
        updateStatus(type: .download, message: "Downloading \(filename)")
    }
    
    func showSecurity(message: String) {
        updateStatus(type: .security, message: message)
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
            }
        }
    }
}

#Preview {
    SmartStatusBar(tab: Tab(), hoveredLink: "https://example.com")
        .padding()
}