import SwiftUI

/// Manages floating panels for history, bookmarks, and downloads
/// Provides next-gen overlay system with glass morphism and smooth animations
struct PanelManager: View {
    @ObservedObject private var keyboardHandler = KeyboardShortcutHandler.shared
    @State private var dragOffset = CGSize.zero
    @State private var isDragging = false
    @State private var urlBarHandledEscape = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // History Panel
                if keyboardHandler.showHistoryPanel {
                    HistoryView()
                        .frame(
                            width: max(480, min(geometry.size.width * 0.4, 720)),
                            height: max(400, geometry.size.height * 0.85)
                        )
                        .position(
                            x: calculateSafePosition(
                                preferred: keyboardHandler.historyPanelPosition.x + dragOffset.width,
                                panelWidth: max(480, min(geometry.size.width * 0.4, 720)),
                                containerWidth: geometry.size.width
                            ),
                            y: calculateSafePosition(
                                preferred: keyboardHandler.historyPanelPosition.y + dragOffset.height,
                                panelWidth: max(400, geometry.size.height * 0.85),
                                containerWidth: geometry.size.height
                            )
                        )
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                        removal: .scale(scale: 0.9).combined(with: .opacity)
                    ))
                    .scaleEffect(isDragging ? 1.02 : 1.0)
                    .shadow(color: .black.opacity(0.2), radius: isDragging ? 30 : 20)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if !isDragging {
                                    isDragging = true
                                }
                                dragOffset = value.translation
                            }
                            .onEnded { value in
                                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                    keyboardHandler.historyPanelPosition.x += value.translation.width
                                    keyboardHandler.historyPanelPosition.y += value.translation.height
                                    dragOffset = .zero
                                    isDragging = false
                                }
                            }
                    )
                    .zIndex(3)
            }
            
                // Bookmarks Panel
                if keyboardHandler.showBookmarksPanel {
                    BookmarkView()
                        .frame(
                            width: max(560, min(geometry.size.width * 0.45, 800)),
                            height: max(400, geometry.size.height * 0.85)
                        )
                        .position(
                            x: calculateSafePosition(
                                preferred: keyboardHandler.bookmarksPanelPosition.x + dragOffset.width,
                                panelWidth: max(560, min(geometry.size.width * 0.45, 800)),
                                containerWidth: geometry.size.width
                            ),
                            y: calculateSafePosition(
                                preferred: keyboardHandler.bookmarksPanelPosition.y + dragOffset.height,
                                panelWidth: max(400, geometry.size.height * 0.85),
                                containerWidth: geometry.size.height
                            )
                        )
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                        removal: .scale(scale: 0.9).combined(with: .opacity)
                    ))
                    .scaleEffect(isDragging ? 1.02 : 1.0)
                    .shadow(color: .black.opacity(0.2), radius: isDragging ? 30 : 20)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if !isDragging {
                                    isDragging = true
                                }
                                dragOffset = value.translation
                            }
                            .onEnded { value in
                                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                    keyboardHandler.bookmarksPanelPosition.x += value.translation.width
                                    keyboardHandler.bookmarksPanelPosition.y += value.translation.height
                                    dragOffset = .zero
                                    isDragging = false
                                }
                            }
                    )
                    .zIndex(2)
            }
            
                // Downloads Panel
                if keyboardHandler.showDownloadsPanel {
                    DownloadsView()
                        .frame(
                            width: max(400, min(geometry.size.width * 0.35, 600)),
                            height: max(350, geometry.size.height * 0.75)
                        )
                        .position(
                            x: calculateSafePosition(
                                preferred: keyboardHandler.downloadsPanelPosition.x + dragOffset.width,
                                panelWidth: max(400, min(geometry.size.width * 0.35, 600)),
                                containerWidth: geometry.size.width
                            ),
                            y: calculateSafePosition(
                                preferred: keyboardHandler.downloadsPanelPosition.y + dragOffset.height,
                                panelWidth: max(350, geometry.size.height * 0.75),
                                containerWidth: geometry.size.height
                            )
                        )
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                        removal: .scale(scale: 0.9).combined(with: .opacity)
                    ))
                    .scaleEffect(isDragging ? 1.02 : 1.0)
                    .shadow(color: .black.opacity(0.2), radius: isDragging ? 30 : 20)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if !isDragging {
                                    isDragging = true
                                }
                                dragOffset = value.translation
                            }
                            .onEnded { value in
                                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                    keyboardHandler.downloadsPanelPosition.x += value.translation.width
                                    keyboardHandler.downloadsPanelPosition.y += value.translation.height
                                    dragOffset = .zero
                                    isDragging = false
                                }
                            }
                    )
                    .zIndex(1)
            }
            
                // About Panel
                if keyboardHandler.showAboutPanel {
                    AboutView()
                        .frame(width: 400, height: 480)
                        .position(
                            x: calculateSafePosition(
                                preferred: keyboardHandler.aboutPanelPosition.x + dragOffset.width,
                                panelWidth: 400,
                                containerWidth: geometry.size.width
                            ),
                            y: calculateSafePosition(
                                preferred: keyboardHandler.aboutPanelPosition.y + dragOffset.height,
                                panelWidth: 480,
                                containerWidth: geometry.size.height
                            )
                        )
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                        removal: .scale(scale: 0.9).combined(with: .opacity)
                    ))
                    .scaleEffect(isDragging ? 1.02 : 1.0)
                    .shadow(color: .black.opacity(0.2), radius: isDragging ? 30 : 20)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if !isDragging {
                                    isDragging = true
                                }
                                dragOffset = value.translation
                            }
                            .onEnded { value in
                                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                    keyboardHandler.aboutPanelPosition.x += value.translation.width
                                    keyboardHandler.aboutPanelPosition.y += value.translation.height
                                    dragOffset = .zero
                                    isDragging = false
                                }
                            }
                    )
                    .zIndex(5)
            }
            
                // Settings Panel
                if keyboardHandler.showSettingsPanel {
                    SettingsView()
                        .frame(
                            width: max(700, min(geometry.size.width * 0.55, 900)),
                            height: max(500, geometry.size.height * 0.85)
                        )
                        .position(
                            x: calculateSafePosition(
                                preferred: keyboardHandler.settingsPanelPosition.x + dragOffset.width,
                                panelWidth: max(700, min(geometry.size.width * 0.55, 900)),
                                containerWidth: geometry.size.width
                            ),
                            y: calculateSafePosition(
                                preferred: keyboardHandler.settingsPanelPosition.y + dragOffset.height,
                                panelWidth: max(500, geometry.size.height * 0.85),
                                containerWidth: geometry.size.height
                            )
                        )
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                        removal: .scale(scale: 0.9).combined(with: .opacity)
                    ))
                    .scaleEffect(isDragging ? 1.02 : 1.0)
                    .shadow(color: .black.opacity(0.2), radius: isDragging ? 30 : 20)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if !isDragging {
                                    isDragging = true
                                }
                                dragOffset = value.translation
                            }
                            .onEnded { value in
                                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                    keyboardHandler.settingsPanelPosition.x += value.translation.width
                                    keyboardHandler.settingsPanelPosition.y += value.translation.height
                                    dragOffset = .zero
                                    isDragging = false
                                }
                            }
                    )
                    .zIndex(4)
            }
            }
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: keyboardHandler.showHistoryPanel)
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: keyboardHandler.showBookmarksPanel)
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: keyboardHandler.showDownloadsPanel)
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: keyboardHandler.showAboutPanel)
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: keyboardHandler.showSettingsPanel)
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.escape) {
                handleEscapeKey()
                return .handled
            }
            .onReceive(NotificationCenter.default.publisher(for: .hoverableURLBarDismissed)) { _ in
                urlBarHandledEscape = true
                // Reset after a short delay to ensure proper state management
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    urlBarHandledEscape = false
                }
            }
        }
    }
    
    /// Handle ESCAPE key to close panels with priority system
    /// Priority: HoverableURLBar → About → Settings → History → Downloads → Bookmarks
    private func handleEscapeKey() {
        // Reset the URLBar handled flag before processing
        urlBarHandledEscape = false
        
        // First, try to dismiss HoverableURLBar with notification
        // This gives it highest priority
        NotificationCenter.default.post(name: .dismissHoverableURLBar, object: nil)
        
        // Use a small delay to allow HoverableURLBar to handle the dismissal first
        // and update the urlBarHandledEscape flag
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // Only proceed with panel closure if URLBar didn't handle the escape
            if !self.urlBarHandledEscape {
                // Check and close panels in priority order (About has highest priority among panels)
                if self.keyboardHandler.showAboutPanel {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        self.keyboardHandler.showAboutPanel = false
                    }
                } else if self.keyboardHandler.showSettingsPanel {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        self.keyboardHandler.showSettingsPanel = false
                    }
                } else if self.keyboardHandler.showHistoryPanel {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        self.keyboardHandler.showHistoryPanel = false
                    }
                } else if self.keyboardHandler.showDownloadsPanel {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        self.keyboardHandler.showDownloadsPanel = false
                    }
                } else if self.keyboardHandler.showBookmarksPanel {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        self.keyboardHandler.showBookmarksPanel = false
                    }
                }
            }
        }
    }
    
    /// Calculate safe position ensuring panels stay within window bounds with improved padding
    private func calculateSafePosition(preferred: CGFloat, panelWidth: CGFloat, containerWidth: CGFloat) -> CGFloat {
        let halfPanelWidth = panelWidth / 2
        let minPosition = halfPanelWidth + 30  // Increased padding from window edges
        let maxPosition = containerWidth - halfPanelWidth - 30
        
        return max(minPosition, min(preferred, maxPosition))
    }
}

/// Enhanced downloads view with next-gen design
struct DownloadsView: View {
    @ObservedObject private var downloadManager = DownloadManager.shared
    @State private var hoveredDownload: Download?
    @State private var contentOpacity = 0.0
    
    var body: some View {
        ZStack {
            // Simplified glass background
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.15), lineWidth: 0.5)
                )
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Downloads")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    if downloadManager.totalActiveDownloads > 0 {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.6)
                            
                            Text("\(downloadManager.totalActiveDownloads) active")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(.blue.opacity(0.15))
                                .overlay(
                                    Capsule()
                                        .stroke(.blue.opacity(0.3), lineWidth: 0.5)
                                )
                        )
                    }
                    
                    Button(action: {
                        KeyboardShortcutHandler.shared.showDownloadsPanel = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
                
                Divider()
                    .opacity(0.3)
                    .padding(.horizontal, 20)
                
                // Downloads list
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if downloadManager.downloads.isEmpty && downloadManager.downloadHistory.isEmpty {
                            emptyStateView
                        } else {
                            // Active downloads
                            if !downloadManager.downloads.isEmpty {
                                sectionHeader("Active Downloads")
                                
                                ForEach(downloadManager.downloads, id: \.id) { download in
                                    downloadRow(download, isHistory: false)
                                }
                            }
                            
                            // Download history
                            if !downloadManager.downloadHistory.isEmpty {
                                sectionHeader("Recent Downloads")
                                
                                ForEach(downloadManager.downloadHistory.prefix(10), id: \.id) { historyItem in
                                    historyRow(historyItem)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 16)
                }
                .scrollIndicators(.hidden)
            }
            .opacity(contentOpacity)
        }
        // Frame will be set by PanelManager for responsive sizing
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                contentOpacity = 1.0
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(.secondary)
            
            Text("No Downloads")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Downloaded files will appear here")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
    }
    
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
    
    private func downloadRow(_ download: Download, isHistory: Bool) -> some View {
        HStack(spacing: 12) {
            // File icon
            RoundedRectangle(cornerRadius: 6)
                .fill(.regularMaterial)
                .frame(width: 24, height: 24)
                .overlay(
                    Image(systemName: fileIcon(for: download.filename))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.blue)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(download.filename)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    if download.status == .downloading {
                        ProgressView(value: download.progress)
                            .progressViewStyle(LinearProgressViewStyle())
                            .frame(maxWidth: 120)
                        
                        Text("\(Int(download.progress * 100))%")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.blue)
                    } else {
                        Text(download.formattedFileSize)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        
                        Text(statusText(for: download.status))
                            .font(.system(size: 11))
                            .foregroundColor(statusColor(for: download.status))
                    }
                    
                    Spacer()
                }
            }
            
            // Action buttons
            if download.status == .completed {
                Button(action: {
                    downloadManager.openDownloadedFile(download)
                }) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.blue)
                        .frame(width: 20, height: 20)
                        .background(
                            Circle()
                                .fill(.blue.opacity(0.15))
                                .overlay(
                                    Circle()
                                        .stroke(.blue.opacity(0.3), lineWidth: 0.5)
                                )
                        )
                }
                .buttonStyle(PlainButtonStyle())
            } else if download.status == .downloading {
                Button(action: {
                    downloadManager.pauseDownload(download)
                }) {
                    Image(systemName: "pause")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.orange)
                        .frame(width: 20, height: 20)
                        .background(
                            Circle()
                                .fill(.orange.opacity(0.15))
                                .overlay(
                                    Circle()
                                        .stroke(.orange.opacity(0.3), lineWidth: 0.5)
                                )
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hoveredDownload?.id == download.id ? .white.opacity(0.05) : .clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                hoveredDownload = hovering ? download : nil
            }
        }
    }
    
    private func historyRow(_ historyItem: DownloadHistoryItem) -> some View {
        HStack(spacing: 12) {
            // File icon
            RoundedRectangle(cornerRadius: 6)
                .fill(.regularMaterial)
                .frame(width: 24, height: 24)
                .overlay(
                    Image(systemName: fileIcon(for: historyItem.filename))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(historyItem.filename)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(historyItem.formattedFileSize)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Text(formatDate(historyItem.downloadDate))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
            }
            
            // Show in Finder button
            if historyItem.fileExists {
                Button(action: {
                    NSWorkspace.shared.selectFile(historyItem.filePath, inFileViewerRootedAtPath: "")
                }) {
                    Image(systemName: "folder")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.blue)
                        .frame(width: 20, height: 20)
                        .background(
                            Circle()
                                .fill(.blue.opacity(0.15))
                                .overlay(
                                    Circle()
                                        .stroke(.blue.opacity(0.3), lineWidth: 0.5)
                                )
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
    
    // Helper methods
    private func fileIcon(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        
        switch ext {
        case "pdf": return "doc.text"
        case "jpg", "jpeg", "png", "gif": return "photo"
        case "mp4", "mov", "avi": return "play.rectangle"
        case "mp3", "wav", "aiff": return "music.note"
        case "zip", "tar", "gz": return "archivebox"
        case "dmg": return "externaldrive"
        default: return "doc"
        }
    }
    
    private func statusText(for status: Download.Status) -> String {
        switch status {
        case .downloading: return "Downloading..."
        case .paused: return "Paused"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
    
    private func statusColor(for status: Download.Status) -> Color {
        switch status {
        case .downloading: return .blue
        case .paused: return .orange
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .secondary
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    PanelManager()
        .frame(width: 800, height: 600)
        .background(.black.opacity(0.3))
}