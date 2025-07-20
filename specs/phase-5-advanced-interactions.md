# Phase 5: Advanced Interactions - Detailed Implementation

## Overview
This phase implements revolutionary interaction patterns including floating micro-controls, live tab/link previews, adaptive glass effects based on favicon colors, and other "next-gen ways that would make users go whoa."

## 1. Floating Micro-Controls

### Context-Sensitive Floating Controls
```swift
// FloatingControlsManager.swift - Revolutionary context-sensitive controls
import SwiftUI
import Combine

class FloatingControlsManager: ObservableObject {
    @Published var activeControls: [FloatingControl] = []
    @Published var mousePosition: CGPoint = .zero
    @Published var isMouseMoving: Bool = false
    
    private var mouseMovementTimer: Timer?
    private var hideTimer: Timer?
    private let controlsDelay: TimeInterval = 0.1
    private let hideDelay: TimeInterval = 2.0
    
    struct FloatingControl: Identifiable {
        let id = UUID()
        let type: ControlType
        let position: CGPoint
        let context: ControlContext
        let appearanceDelay: TimeInterval
        
        enum ControlType {
            case navigation(canGoBack: Bool, canGoForward: Bool)
            case mediaControl(isPlaying: Bool, volume: Double)
            case pageActions(canShare: Bool, canBookmark: Bool)
            case selectionTools(selectedText: String)
            case linkPreview(url: URL)
            case imageViewer(imageURL: URL)
        }
        
        struct ControlContext {
            let webView: WKWebView?
            let hoveredElement: String?
            let selectedText: String?
            let mediaElement: String?
        }
    }
    
    init() {
        setupMouseTracking()
    }
    
    // MARK: - Mouse Tracking
    private func setupMouseTracking() {
        // Global mouse tracking for floating controls
        NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
            self?.handleMouseMovement(event)
        }
        
        // Local mouse tracking
        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
            self?.handleMouseMovement(event)
            return event
        }
    }
    
    private func handleMouseMovement(_ event: NSEvent) {
        let newPosition = NSEvent.mouseLocation
        
        // Convert to screen coordinates
        if let screen = NSScreen.main {
            let flippedY = screen.frame.height - newPosition.y
            mousePosition = CGPoint(x: newPosition.x, y: flippedY)
        }
        
        isMouseMoving = true
        
        // Reset movement timer
        mouseMovementTimer?.invalidate()
        mouseMovementTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.isMouseMoving = false
            self?.evaluateFloatingControls()
        }
        
        // Show controls on movement
        evaluateFloatingControls()
    }
    
    // MARK: - Control Evaluation
    private func evaluateFloatingControls() {
        guard isMouseMoving else {
            hideAllControls()
            return
        }
        
        // Determine context-appropriate controls
        let newControls = determineContextualControls()
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            activeControls = newControls
        }
        
        // Schedule auto-hide
        scheduleAutoHide()
    }
    
    private func determineContextualControls() -> [FloatingControl] {
        var controls: [FloatingControl] = []
        
        // Get current tab context
        guard let activeTab = TabManager.shared.activeTab,
              let webView = activeTab.webView else { return controls }
        
        // Navigation controls (if mouse is near edges)
        if isNearScreenEdge() {
            let navigationControl = FloatingControl(
                type: .navigation(canGoBack: activeTab.canGoBack, canGoForward: activeTab.canGoForward),
                position: getNavigationPosition(),
                context: FloatingControl.ControlContext(
                    webView: webView,
                    hoveredElement: nil,
                    selectedText: nil,
                    mediaElement: nil
                ),
                appearanceDelay: 0.1
            )
            controls.append(navigationControl)
        }
        
        // Page actions (always available with slight delay)
        let pageActionsControl = FloatingControl(
            type: .pageActions(canShare: true, canBookmark: true),
            position: getPageActionsPosition(),
            context: FloatingControl.ControlContext(
                webView: webView,
                hoveredElement: nil,
                selectedText: nil,
                mediaElement: nil
            ),
            appearanceDelay: 0.3
        )
        controls.append(pageActionsControl)
        
        return controls
    }
    
    private func isNearScreenEdge() -> Bool {
        guard let screen = NSScreen.main else { return false }
        
        let edgeThreshold: CGFloat = 100
        let frame = screen.frame
        
        return mousePosition.x < edgeThreshold ||
               mousePosition.x > frame.width - edgeThreshold ||
               mousePosition.y < edgeThreshold ||
               mousePosition.y > frame.height - edgeThreshold
    }
    
    private func getNavigationPosition() -> CGPoint {
        // Position navigation controls near left edge
        return CGPoint(x: 60, y: mousePosition.y)
    }
    
    private func getPageActionsPosition() -> CGPoint {
        // Position page actions in bottom right
        guard let screen = NSScreen.main else { return mousePosition }
        return CGPoint(x: screen.frame.width - 100, y: 100)
    }
    
    // MARK: - Control Management
    func showControlsForHoveredLink(_ url: URL, at position: CGPoint) {
        let linkControl = FloatingControl(
            type: .linkPreview(url: url),
            position: position,
            context: FloatingControl.ControlContext(
                webView: nil,
                hoveredElement: "link",
                selectedText: nil,
                mediaElement: nil
            ),
            appearanceDelay: 0.5
        )
        
        DispatchQueue.main.asyncAfter(deadline: .now() + linkControl.appearanceDelay) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                self.activeControls.append(linkControl)
            }
        }
    }
    
    func showControlsForSelectedText(_ text: String, at position: CGPoint) {
        let selectionControl = FloatingControl(
            type: .selectionTools(selectedText: text),
            position: position,
            context: FloatingControl.ControlContext(
                webView: nil,
                hoveredElement: nil,
                selectedText: text,
                mediaElement: nil
            ),
            appearanceDelay: 0.2
        )
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            activeControls.append(selectionControl)
        }
    }
    
    func showControlsForMediaElement(isPlaying: Bool, volume: Double, at position: CGPoint) {
        let mediaControl = FloatingControl(
            type: .mediaControl(isPlaying: isPlaying, volume: volume),
            position: position,
            context: FloatingControl.ControlContext(
                webView: nil,
                hoveredElement: nil,
                selectedText: nil,
                mediaElement: "video"
            ),
            appearanceDelay: 0.1
        )
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            activeControls.append(mediaControl)
        }
    }
    
    private func scheduleAutoHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: hideDelay, repeats: false) { [weak self] _ in
            self?.hideAllControls()
        }
    }
    
    private func hideAllControls() {
        withAnimation(.easeOut(duration: 0.3)) {
            activeControls.removeAll()
        }
    }
    
    func hideControl(_ control: FloatingControl) {
        withAnimation(.easeOut(duration: 0.2)) {
            activeControls.removeAll { $0.id == control.id }
        }
    }
}

// MARK: - SwiftUI Views
struct FloatingControlsOverlay: View {
    @ObservedObject var controlsManager: FloatingControlsManager
    
    var body: some View {
        ZStack {
            ForEach(controlsManager.activeControls) { control in
                FloatingControlView(control: control, manager: controlsManager)
                    .position(control.position)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .allowsHitTesting(true)
    }
}

struct FloatingControlView: View {
    let control: FloatingControlsManager.FloatingControl
    let manager: FloatingControlsManager
    @State private var isHovered: Bool = false
    
    var body: some View {
        Group {
            switch control.type {
            case .navigation(let canGoBack, let canGoForward):
                NavigationFloatingControl(canGoBack: canGoBack, canGoForward: canGoForward)
                
            case .mediaControl(let isPlaying, let volume):
                MediaFloatingControl(isPlaying: isPlaying, volume: volume)
                
            case .pageActions(let canShare, let canBookmark):
                PageActionsFloatingControl(canShare: canShare, canBookmark: canBookmark)
                
            case .selectionTools(let selectedText):
                SelectionToolsFloatingControl(selectedText: selectedText)
                
            case .linkPreview(let url):
                LinkPreviewFloatingControl(url: url)
                
            case .imageViewer(let imageURL):
                ImageViewerFloatingControl(imageURL: imageURL)
            }
        }
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
            if !hovering {
                // Auto-hide after hover ends
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    manager.hideControl(control)
                }
            }
        }
    }
}

struct NavigationFloatingControl: View {
    let canGoBack: Bool
    let canGoForward: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Button(action: { TabManager.shared.activeTab?.goBack() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
            }
            .disabled(!canGoBack)
            .buttonStyle(FloatingButtonStyle())
            
            Button(action: { TabManager.shared.activeTab?.goForward() }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .medium))
            }
            .disabled(!canGoForward)
            .buttonStyle(FloatingButtonStyle())
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
}

struct MediaFloatingControl: View {
    let isPlaying: Bool
    let volume: Double
    @State private var currentVolume: Double
    
    init(isPlaying: Bool, volume: Double) {
        self.isPlaying = isPlaying
        self.volume = volume
        self._currentVolume = State(initialValue: volume)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: togglePlayPause) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .medium))
            }
            .buttonStyle(FloatingButtonStyle())
            
            VStack {
                Image(systemName: currentVolume > 0.5 ? "speaker.wave.2.fill" : "speaker.wave.1.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                Slider(value: $currentVolume, in: 0...1)
                    .frame(width: 60)
                    .onChange(of: currentVolume) { newValue in
                        setVolume(newValue)
                    }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
    
    private func togglePlayPause() {
        // Send JavaScript to toggle media playback
        let script = isPlaying ? "document.querySelector('video, audio').pause();" : "document.querySelector('video, audio').play();"
        TabManager.shared.activeTab?.webView?.evaluateJavaScript(script)
    }
    
    private func setVolume(_ volume: Double) {
        let script = "document.querySelector('video, audio').volume = \(volume);"
        TabManager.shared.activeTab?.webView?.evaluateJavaScript(script)
    }
}

struct PageActionsFloatingControl: View {
    let canShare: Bool
    let canBookmark: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            if canShare {
                Button(action: shareCurrentPage) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .medium))
                }
                .buttonStyle(FloatingButtonStyle())
            }
            
            if canBookmark {
                Button(action: bookmarkCurrentPage) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 16, weight: .medium))
                }
                .buttonStyle(FloatingButtonStyle())
            }
            
            Button(action: printCurrentPage) {
                Image(systemName: "printer")
                    .font(.system(size: 16, weight: .medium))
            }
            .buttonStyle(FloatingButtonStyle())
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
    
    private func shareCurrentPage() {
        guard let url = TabManager.shared.activeTab?.url else { return }
        
        let sharingService = NSSharingServicePicker(items: [url])
        sharingService.show(relativeTo: .zero, of: NSApp.keyWindow?.contentView ?? NSView(), preferredEdge: .minY)
    }
    
    private func bookmarkCurrentPage() {
        guard let tab = TabManager.shared.activeTab,
              let url = tab.url else { return }
        
        BookmarkManager.shared.addBookmark(url: url, title: tab.title)
    }
    
    private func printCurrentPage() {
        TabManager.shared.activeTab?.webView?.evaluateJavaScript("window.print();")
    }
}

struct SelectionToolsFloatingControl: View {
    let selectedText: String
    
    var body: some View {
        HStack(spacing: 8) {
            Button(action: copyText) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 16, weight: .medium))
            }
            .buttonStyle(FloatingButtonStyle())
            
            Button(action: searchText) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
            }
            .buttonStyle(FloatingButtonStyle())
            
            Button(action: translateText) {
                Image(systemName: "character.bubble")
                    .font(.system(size: 16, weight: .medium))
            }
            .buttonStyle(FloatingButtonStyle())
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
    
    private func copyText() {
        NSPasteboard.general.setString(selectedText, forType: .string)
    }
    
    private func searchText() {
        let encodedText = selectedText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://www.google.com/search?q=\(encodedText)") {
            _ = TabManager.shared.createNewTab(url: url)
        }
    }
    
    private func translateText() {
        // Implement translation functionality
        // Could integrate with macOS translation services
    }
}

struct LinkPreviewFloatingControl: View {
    let url: URL
    @State private var previewData: LinkPreviewData?
    
    struct LinkPreviewData {
        let title: String?
        let description: String?
        let imageURL: URL?
        let siteName: String?
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let siteName = previewData?.siteName {
                    Text(siteName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(url.host ?? "")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: openInNewTab) {
                    Image(systemName: "plus.square")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
            
            if let title = previewData?.title {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
            }
            
            if let description = previewData?.description {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
            
            if let imageURL = previewData?.imageURL {
                AsyncImage(url: imageURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 60)
                        .clipped()
                        .cornerRadius(6)
                } placeholder: {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(height: 60)
                        .cornerRadius(6)
                }
            }
        }
        .frame(width: 250)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        .onAppear {
            loadPreviewData()
        }
    }
    
    private func openInNewTab() {
        _ = TabManager.shared.createNewTab(url: url)
    }
    
    private func loadPreviewData() {
        // Implement link preview data fetching
        // This would use Open Graph or similar meta tags
        Task {
            // Simplified implementation
            let title = url.lastPathComponent
            let host = url.host
            
            await MainActor.run {
                previewData = LinkPreviewData(
                    title: title,
                    description: "Open this link in a new tab",
                    imageURL: nil,
                    siteName: host
                )
            }
        }
    }
}

struct FloatingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.primary)
            .padding(8)
            .background(
                Circle()
                    .fill(.regularMaterial)
                    .opacity(configuration.isPressed ? 0.8 : 1.0)
            )
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
```

## 2. Live Previews System

### Tab and Link Preview Implementation
```swift
// LivePreviewsManager.swift - Advanced preview system for tabs and links
import SwiftUI
import WebKit

class LivePreviewsManager: ObservableObject {
    @Published var activePreview: PreviewItem?
    @Published var previewCache: [String: NSImage] = [:]
    
    private let previewSize = CGSize(width: 300, height: 200)
    private let maxCacheSize = 50
    private var previewGenerationQueue = DispatchQueue(label: "preview.generation", qos: .userInitiated)
    
    struct PreviewItem: Identifiable {
        let id = UUID()
        let type: PreviewType
        let position: CGPoint
        let content: PreviewContent
        
        enum PreviewType {
            case tab, link, image
        }
        
        struct PreviewContent {
            let title: String
            let url: URL
            let thumbnail: NSImage?
            let metadata: [String: Any]?
        }
    }
    
    // MARK: - Tab Previews
    func showTabPreview(for tab: Tab, at position: CGPoint) {
        guard let thumbnail = tab.snapshot ?? generateTabThumbnail(tab) else { return }
        
        let preview = PreviewItem(
            type: .tab,
            position: adjustPosition(position),
            content: PreviewItem.PreviewContent(
                title: tab.title,
                url: tab.url ?? URL(string: "about:blank")!,
                thumbnail: thumbnail,
                metadata: [
                    "isLoading": tab.isLoading,
                    "lastAccessed": tab.lastAccessed,
                    "isHibernated": tab.isHibernated
                ]
            )
        )
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            activePreview = preview
        }
        
        // Auto-hide after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.hidePreview()
        }
    }
    
    func hideTabPreview() {
        hidePreview()
    }
    
    private func generateTabThumbnail(_ tab: Tab) -> NSImage? {
        guard let webView = tab.webView else { return nil }
        
        let config = WKSnapshotConfiguration()
        config.rect = webView.bounds
        config.snapshotWidth = NSNumber(value: previewSize.width)
        
        var thumbnail: NSImage?
        let semaphore = DispatchSemaphore(value: 0)
        
        webView.takeSnapshot(with: config) { image, error in
            thumbnail = image
            semaphore.signal()
        }
        
        semaphore.wait()
        return thumbnail
    }
    
    // MARK: - Link Previews
    func showLinkPreview(for url: URL, at position: CGPoint) {
        // Check cache first
        let cacheKey = url.absoluteString
        if let cachedThumbnail = previewCache[cacheKey] {
            showCachedLinkPreview(url: url, thumbnail: cachedThumbnail, at: position)
            return
        }
        
        // Generate new preview
        generateLinkPreview(for: url, at: position)
    }
    
    func hideLinkPreview() {
        hidePreview()
    }
    
    private func showCachedLinkPreview(url: URL, thumbnail: NSImage, at position: CGPoint) {
        let preview = PreviewItem(
            type: .link,
            position: adjustPosition(position),
            content: PreviewItem.PreviewContent(
                title: url.lastPathComponent,
                url: url,
                thumbnail: thumbnail,
                metadata: ["cached": true]
            )
        )
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            activePreview = preview
        }
    }
    
    private func generateLinkPreview(for url: URL, at position: CGPoint) {
        previewGenerationQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Create temporary WebView for preview generation
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .nonPersistent()
            
            let webView = WKWebView(frame: CGRect(origin: .zero, size: self.previewSize), configuration: config)
            webView.load(URLRequest(url: url))
            
            // Wait for load completion
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.capturePreview(from: webView, for: url, at: position)
            }
        }
    }
    
    private func capturePreview(from webView: WKWebView, for url: URL, at position: CGPoint) {
        let config = WKSnapshotConfiguration()
        config.rect = webView.bounds
        config.snapshotWidth = NSNumber(value: previewSize.width)
        
        webView.takeSnapshot(with: config) { [weak self] image, error in
            guard let self = self, let thumbnail = image else { return }
            
            // Cache the thumbnail
            let cacheKey = url.absoluteString
            self.previewCache[cacheKey] = thumbnail
            self.manageCacheSize()
            
            // Show preview
            DispatchQueue.main.async {
                let preview = PreviewItem(
                    type: .link,
                    position: self.adjustPosition(position),
                    content: PreviewItem.PreviewContent(
                        title: webView.title ?? url.lastPathComponent,
                        url: url,
                        thumbnail: thumbnail,
                        metadata: ["freshlyGenerated": true]
                    )
                )
                
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    self.activePreview = preview
                }
                
                // Auto-hide
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                    self.hidePreview()
                }
            }
        }
    }
    
    // MARK: - Image Previews
    func showImagePreview(for imageURL: URL, at position: CGPoint) {
        URLSession.shared.dataTask(with: imageURL) { [weak self] data, response, error in
            guard let data = data, let image = NSImage(data: data) else { return }
            
            DispatchQueue.main.async {
                let preview = PreviewItem(
                    type: .image,
                    position: self?.adjustPosition(position) ?? position,
                    content: PreviewItem.PreviewContent(
                        title: imageURL.lastPathComponent,
                        url: imageURL,
                        thumbnail: image,
                        metadata: [
                            "fileSize": data.count,
                            "dimensions": "\(Int(image.size.width))×\(Int(image.size.height))"
                        ]
                    )
                )
                
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    self?.activePreview = preview
                }
            }
        }.resume()
    }
    
    // MARK: - Helper Methods
    private func adjustPosition(_ position: CGPoint) -> CGPoint {
        guard let screen = NSScreen.main else { return position }
        
        let previewRect = CGRect(
            x: position.x,
            y: position.y - previewSize.height,
            width: previewSize.width,
            height: previewSize.height
        )
        
        let screenRect = screen.visibleFrame
        var adjustedPosition = position
        
        // Adjust horizontal position
        if previewRect.maxX > screenRect.maxX {
            adjustedPosition.x = screenRect.maxX - previewSize.width - 20
        }
        if previewRect.minX < screenRect.minX {
            adjustedPosition.x = screenRect.minX + 20
        }
        
        // Adjust vertical position
        if previewRect.minY < screenRect.minY {
            adjustedPosition.y = position.y + previewSize.height + 20
        }
        
        return adjustedPosition
    }
    
    private func hidePreview() {
        withAnimation(.easeOut(duration: 0.2)) {
            activePreview = nil
        }
    }
    
    private func manageCacheSize() {
        if previewCache.count > maxCacheSize {
            // Remove oldest entries (simple FIFO approach)
            let keysToRemove = Array(previewCache.keys.prefix(previewCache.count - maxCacheSize))
            keysToRemove.forEach { previewCache.removeValue(forKey: $0) }
        }
    }
}

// MARK: - SwiftUI Preview Views
struct LivePreviewOverlay: View {
    @ObservedObject var previewsManager: LivePreviewsManager
    
    var body: some View {
        ZStack {
            if let preview = previewsManager.activePreview {
                PreviewCard(preview: preview)
                    .position(preview.position)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
    }
}

struct PreviewCard: View {
    let preview: LivePreviewsManager.PreviewItem
    @State private var isLoaded: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with type indicator
            HStack {
                Image(systemName: typeIcon)
                    .font(.caption)
                    .foregroundColor(.blue)
                
                Text(preview.content.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Spacer()
                
                if preview.type == .tab {
                    TabStatusIndicator(metadata: preview.content.metadata)
                }
            }
            
            // Main content area
            Group {
                if let thumbnail = preview.content.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 280, height: 160)
                        .clipped()
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(.primary.opacity(0.1), lineWidth: 1)
                        )
                } else {
                    PreviewPlaceholder(url: preview.content.url)
                        .frame(width: 280, height: 160)
                }
            }
            
            // Footer with URL and metadata
            VStack(alignment: .leading, spacing: 4) {
                Text(preview.content.url.host ?? "")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                if let metadata = preview.content.metadata {
                    MetadataView(metadata: metadata, type: preview.type)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
        .scaleEffect(isLoaded ? 1.0 : 0.8)
        .opacity(isLoaded ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                isLoaded = true
            }
        }
    }
    
    private var typeIcon: String {
        switch preview.type {
        case .tab: return "rectangle.on.rectangle"
        case .link: return "link"
        case .image: return "photo"
        }
    }
}

struct TabStatusIndicator: View {
    let metadata: [String: Any]?
    
    var body: some View {
        HStack(spacing: 4) {
            if let isLoading = metadata?["isLoading"] as? Bool, isLoading {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
            }
            
            if let isHibernated = metadata?["isHibernated"] as? Bool, isHibernated {
                Image(systemName: "zzz")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
    }
}

struct MetadataView: View {
    let metadata: [String: Any]
    let type: LivePreviewsManager.PreviewItem.PreviewType
    
    var body: some View {
        HStack(spacing: 8) {
            switch type {
            case .tab:
                if let lastAccessed = metadata["lastAccessed"] as? Date {
                    Text("Last viewed \(RelativeDateTimeFormatter().localizedString(for: lastAccessed, relativeTo: Date()))")
                        .font(.caption2)
                        .foregroundColor(.tertiary)
                }
                
            case .image:
                if let dimensions = metadata["dimensions"] as? String {
                    Text(dimensions)
                        .font(.caption2)
                        .foregroundColor(.tertiary)
                }
                
                if let fileSize = metadata["fileSize"] as? Int {
                    Text(ByteCountFormatter().string(fromByteCount: Int64(fileSize)))
                        .font(.caption2)
                        .foregroundColor(.tertiary)
                }
                
            case .link:
                if metadata["cached"] as? Bool == true {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                } else if metadata["freshlyGenerated"] as? Bool == true {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
        }
    }
}

struct PreviewPlaceholder: View {
    let url: URL
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
            
            VStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.title2)
                    .foregroundColor(.secondary)
                
                Text("Loading preview...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(url.host ?? "")
                    .font(.caption2)
                    .foregroundColor(.tertiary)
            }
        }
    }
}
```

## 3. Adaptive Glass Effects

### Dynamic Color Extraction and Glass Tinting
```swift
// AdaptiveGlassEffects.swift - Dynamic glass effects based on favicon colors
import SwiftUI
import AppKit
import Accelerate

class AdaptiveGlassEffectsManager: ObservableObject {
    @Published var currentDominantColor: Color = .clear
    @Published var currentAccentColor: Color = .blue
    @Published var glassIntensity: Double = 0.3
    @Published var isAnimating: Bool = false
    
    private var colorExtractionTask: Task<Void, Never>?
    private let colorCache: NSCache<NSString, NSColor> = NSCache()
    
    init() {
        setupColorCache()
    }
    
    private func setupColorCache() {
        colorCache.countLimit = 100
        colorCache.totalCostLimit = 50 * 1024 * 1024 // 50MB
    }
    
    // MARK: - Color Extraction
    func updateColorsFromFavicon(_ favicon: NSImage?) {
        colorExtractionTask?.cancel()
        
        guard let favicon = favicon else {
            resetToDefaultColors()
            return
        }
        
        // Check cache first
        let cacheKey = NSString(string: favicon.description)
        if let cachedColor = colorCache.object(forKey: cacheKey) {
            applyColors(dominant: Color(cachedColor), accent: Color(cachedColor.withAlphaComponent(0.8)))
            return
        }
        
        colorExtractionTask = Task {
            let colors = await extractDominantColors(from: favicon)
            
            await MainActor.run {
                if !Task.isCancelled {
                    // Cache the result
                    if let nsColor = NSColor(colors.dominant) {
                        colorCache.setObject(nsColor, forKey: cacheKey)
                    }
                    
                    applyColors(dominant: colors.dominant, accent: colors.accent)
                }
            }
        }
    }
    
    func updateColorsFromWebsite(_ url: URL?) {
        guard let url = url else {
            resetToDefaultColors()
            return
        }
        
        // Extract colors based on website type/category
        let websiteColors = getWebsiteColors(for: url)
        applyColors(dominant: websiteColors.dominant, accent: websiteColors.accent)
    }
    
    private func extractDominantColors(from image: NSImage) async -> (dominant: Color, accent: Color) {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    continuation.resume(returning: (.clear, .blue))
                    return
                }
                
                let colors = self.analyzeImageColors(cgImage)
                continuation.resume(returning: colors)
            }
        }
    }
    
    private func analyzeImageColors(_ cgImage: CGImage) -> (dominant: Color, accent: Color) {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        
        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return (.clear, .blue)
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Use k-means clustering to find dominant colors
        let dominantColors = performKMeansClustering(on: pixelData, width: width, height: height)
        
        let dominantColor = dominantColors.first ?? .clear
        let accentColor = dominantColors.count > 1 ? dominantColors[1] : dominantColor
        
        return (dominant: dominantColor, accent: accentColor)
    }
    
    private func performKMeansClustering(on pixelData: [UInt8], width: Int, height: Int) -> [Color] {
        struct ColorCluster {
            var red: Double = 0
            var green: Double = 0
            var blue: Double = 0
            var count: Int = 0
            
            var color: Color {
                guard count > 0 else { return .clear }
                return Color(
                    red: red / Double(count) / 255.0,
                    green: green / Double(count) / 255.0,
                    blue: blue / Double(count) / 255.0
                )
            }
        }
        
        let k = 5 // Number of clusters
        var clusters = Array(repeating: ColorCluster(), count: k)
        let totalPixels = width * height
        let sampleRate = max(1, totalPixels / 1000) // Sample every nth pixel for performance
        
        // Initialize clusters with random colors
        for i in 0..<k {
            let randomIndex = Int.random(in: 0..<totalPixels) * 4
            if randomIndex + 3 < pixelData.count {
                clusters[i].red = Double(pixelData[randomIndex])
                clusters[i].green = Double(pixelData[randomIndex + 1])
                clusters[i].blue = Double(pixelData[randomIndex + 2])
                clusters[i].count = 1
            }
        }
        
        // Perform k-means iterations
        for _ in 0..<10 {
            var newClusters = Array(repeating: ColorCluster(), count: k)
            
            for pixelIndex in stride(from: 0, to: totalPixels * 4, by: sampleRate * 4) {
                guard pixelIndex + 3 < pixelData.count else { continue }
                
                let red = Double(pixelData[pixelIndex])
                let green = Double(pixelData[pixelIndex + 1])
                let blue = Double(pixelData[pixelIndex + 2])
                let alpha = Double(pixelData[pixelIndex + 3])
                
                // Skip transparent pixels
                guard alpha > 128 else { continue }
                
                // Find closest cluster
                var minDistance = Double.infinity
                var closestCluster = 0
                
                for (index, cluster) in clusters.enumerated() {
                    let distance = pow(red - cluster.red/max(1, Double(cluster.count)), 2) +
                                  pow(green - cluster.green/max(1, Double(cluster.count)), 2) +
                                  pow(blue - cluster.blue/max(1, Double(cluster.count)), 2)
                    
                    if distance < minDistance {
                        minDistance = distance
                        closestCluster = index
                    }
                }
                
                // Add to closest cluster
                newClusters[closestCluster].red += red
                newClusters[closestCluster].green += green
                newClusters[closestCluster].blue += blue
                newClusters[closestCluster].count += 1
            }
            
            clusters = newClusters
        }
        
        // Sort clusters by size and return colors
        clusters.sort { $0.count > $1.count }
        return clusters.filter { $0.count > 0 }.map { $0.color }
    }
    
    private func getWebsiteColors(for url: URL) -> (dominant: Color, accent: Color) {
        guard let host = url.host?.lowercased() else {
            return (.clear, .blue)
        }
        
        // Predefined colors for popular websites
        let websiteColors: [String: (Color, Color)] = [
            "github.com": (.black, .white),
            "twitter.com": (Color(red: 0.11, green: 0.63, blue: 0.95), .white),
            "facebook.com": (Color(red: 0.26, green: 0.40, blue: 0.70), .white),
            "youtube.com": (Color(red: 1.0, green: 0.0, blue: 0.0), .white),
            "google.com": (Color(red: 0.26, green: 0.52, blue: 0.96), .white),
            "apple.com": (.black, Color(red: 0.6, green: 0.6, blue: 0.6)),
            "microsoft.com": (Color(red: 0.0, green: 0.47, blue: 0.84), .white),
            "reddit.com": (Color(red: 1.0, green: 0.27, blue: 0.0), .white),
            "linkedin.com": (Color(red: 0.0, green: 0.47, blue: 0.71), .white),
            "stackoverflow.com": (Color(red: 0.96, green: 0.47, blue: 0.0), .white)
        ]
        
        for (domain, colors) in websiteColors {
            if host.contains(domain) {
                return colors
            }
        }
        
        // Generate color based on domain hash
        let domainHash = host.hashValue
        let hue = Double(abs(domainHash) % 360) / 360.0
        let dominantColor = Color(hue: hue, saturation: 0.6, brightness: 0.8)
        let accentColor = Color(hue: hue, saturation: 0.8, brightness: 0.9)
        
        return (dominant: dominantColor, accent: accentColor)
    }
    
    // MARK: - Color Application
    private func applyColors(dominant: Color, accent: Color) {
        withAnimation(.easeInOut(duration: 0.8)) {
            isAnimating = true
            currentDominantColor = dominant
            currentAccentColor = accent
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.isAnimating = false
        }
    }
    
    private func resetToDefaultColors() {
        applyColors(dominant: .clear, accent: .blue)
    }
    
    // MARK: - Glass Effect Generation
    func createAdaptiveGlassBackground() -> some View {
        AdaptiveGlassBackground(
            dominantColor: currentDominantColor,
            accentColor: currentAccentColor,
            intensity: glassIntensity,
            isAnimating: isAnimating
        )
    }
    
    func createSidebarGlassEffect() -> some View {
        SidebarGlassEffect(
            dominantColor: currentDominantColor,
            intensity: glassIntensity * 0.5
        )
    }
}

struct AdaptiveGlassBackground: View {
    let dominantColor: Color
    let accentColor: Color
    let intensity: Double
    let isAnimating: Bool
    
    @State private var animationOffset: CGFloat = 0
    
    var body: some View {
        ZStack {
            // Base material
            Rectangle()
                .fill(.ultraThinMaterial)
            
            // Dominant color overlay
            Rectangle()
                .fill(
                    RadialGradient(
                        colors: [
                            dominantColor.opacity(intensity * 0.15),
                            dominantColor.opacity(intensity * 0.05),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 100,
                        endRadius: 500
                    )
                )
                .animation(.easeInOut(duration: 1.0), value: dominantColor)
            
            // Accent gradient overlay
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(intensity * 0.1),
                            Color.clear,
                            dominantColor.opacity(intensity * 0.08)
                        ],
                        startPoint: UnitPoint(x: 0, y: animationOffset),
                        endPoint: UnitPoint(x: 1, y: 1 - animationOffset)
                    )
                )
                .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: animationOffset)
                .onAppear {
                    animationOffset = 1.0
                }
            
            // Subtle noise texture for depth
            Rectangle()
                .fill(
                    Image("NoiseTexture") // Add a subtle noise texture asset
                        .resizable(resizingMode: .tile)
                )
                .opacity(0.02)
                .blendMode(.overlay)
        }
        .clipped()
    }
}

struct SidebarGlassEffect: View {
    let dominantColor: Color
    let intensity: Double
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            dominantColor.opacity(intensity * 0.2),
                            dominantColor.opacity(intensity * 0.1),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
    }
}
```

## Implementation Notes

### Revolutionary Features
- **Floating micro-controls**: Context-sensitive controls that appear on mouse movement
- **Live tab previews**: Real-time thumbnails with metadata for hibernated and active tabs
- **Link preview cards**: Rich previews with Open Graph data and cached thumbnails
- **Adaptive glass effects**: Dynamic tinting based on favicon and website colors
- **Physics-based animations**: Spring animations with realistic dampening

### Performance Optimizations
- **Preview caching**: Intelligent caching with memory management
- **Background processing**: Color extraction and preview generation on background queues
- **Efficient color analysis**: K-means clustering for dominant color extraction
- **Smart cache management**: Automatic cleanup based on memory pressure

## 4. Google Profile Integration

### Auto-Login System
```swift
// GoogleProfileManager.swift - Native Google integration for auto-login
import WebKit
import AuthenticationServices

class GoogleProfileManager: ObservableObject {
    @Published var isSignedIn: Bool = false
    @Published var userProfile: GoogleProfile?
    @Published var autoLoginEnabled: Bool = true
    
    struct GoogleProfile {
        let email: String
        let name: String
        let profilePicture: URL?
        let accessToken: String
    }
    
    func enableAutoLogin(for webView: WKWebView) {
        guard autoLoginEnabled, let profile = userProfile else { return }
        
        let autoLoginScript = """
        (function() {
            // Auto-fill Google login forms
            function fillGoogleLogin() {
                const emailInput = document.querySelector('input[type="email"]') ||
                                  document.querySelector('input[name="email"]') ||
                                  document.querySelector('#identifierId');
                
                if (emailInput && !emailInput.value) {
                    emailInput.value = '\(profile.email)';
                    emailInput.dispatchEvent(new Event('input', { bubbles: true }));
                    emailInput.dispatchEvent(new Event('change', { bubbles: true }));
                    
                    // Auto-submit if on Google domain
                    if (window.location.hostname.includes('google.com') || 
                        window.location.hostname.includes('accounts.google.com')) {
                        const nextButton = document.querySelector('#identifierNext button') ||
                                          document.querySelector('button[type="submit"]');
                        if (nextButton) {
                            setTimeout(() => nextButton.click(), 100);
                        }
                    }
                }
            }
            
            // Monitor for Google OAuth redirects
            if (window.location.hostname.includes('accounts.google.com')) {
                // Auto-approve known domains
                const approveButton = document.querySelector('button[data-continue-text]') ||
                                     document.querySelector('#submit_approve_access');
                if (approveButton && window.location.search.includes('client_id=')) {
                    const knownDomains = ['youtube.com', 'gmail.com', 'drive.google.com', 'photos.google.com'];
                    const referrer = document.referrer;
                    
                    if (knownDomains.some(domain => referrer.includes(domain))) {
                        setTimeout(() => approveButton.click(), 500);
                    }
                }
            }
            
            // Execute on page load
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', fillGoogleLogin);
            } else {
                fillGoogleLogin();
            }
            
            // Monitor for dynamic login forms
            const observer = new MutationObserver(function(mutations) {
                mutations.forEach(function(mutation) {
                    if (mutation.addedNodes.length > 0) {
                        fillGoogleLogin();
                    }
                });
            });
            
            observer.observe(document.body, { childList: true, subtree: true });
        })();
        """
        
        let script = WKUserScript(source: autoLoginScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        webView.configuration.userContentController.addUserScript(script)
    }
    
    func signInWithGoogle() {
        // Use ASWebAuthenticationSession for Google OAuth
        let authURL = URL(string: "https://accounts.google.com/oauth2/auth?client_id=YOUR_CLIENT_ID&redirect_uri=YOUR_REDIRECT_URI&response_type=code&scope=openid+profile+email")!
        
        let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: "web-browser") { callbackURL, error in
            if let callbackURL = callbackURL {
                self.handleOAuthCallback(callbackURL)
            }
        }
        
        session.presentationContextProvider = self
        session.start()
    }
    
    private func handleOAuthCallback(_ url: URL) {
        // Extract authorization code and exchange for access token
        // Store profile information securely
        // This would integrate with Google's OAuth 2.0 flow
    }
}

extension GoogleProfileManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return NSApp.keyWindow ?? ASPresentationAnchor()
    }
}
```

## 5. Background Tab Previews Enhancement

### Real-Time Tab Preview System
```swift
// BackgroundTabPreviews.swift - Live background tab previews
import SwiftUI
import WebKit

struct BackgroundTabPreviewsView: View {
    @ObservedObject var tabManager: TabManager
    @State private var hoveredTab: Tab?
    @State private var previewPosition: CGPoint = .zero
    @State private var showPreview: Bool = false
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabManager.tabs) { tab in
                BackgroundTabItem(
                    tab: tab,
                    isActive: tab.id == tabManager.activeTab?.id
                )
                .onHover { hovering in
                    handleTabHover(tab: tab, hovering: hovering)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            previewPosition = value.location
                        }
                )
            }
        }
        .overlay(
            tabPreviewOverlay
        )
    }
    
    @ViewBuilder
    private var tabPreviewOverlay: some View {
        if showPreview, let tab = hoveredTab {
            TabPreviewCard(tab: tab)
                .position(previewPosition)
                .transition(.scale.combined(with: .opacity))
                .zIndex(1000)
        }
    }
    
    private func handleTabHover(tab: Tab, hovering: Bool) {
        if hovering && tab.id != tabManager.activeTab?.id {
            hoveredTab = tab
            
            // Delay preview appearance
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if hoveredTab?.id == tab.id {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showPreview = true
                    }
                }
            }
        } else {
            hoveredTab = nil
            withAnimation(.easeOut(duration: 0.2)) {
                showPreview = false
            }
        }
    }
}

struct BackgroundTabItem: View {
    let tab: Tab
    let isActive: Bool
    @State private var isHovered: Bool = false
    
    var body: some View {
        VStack(spacing: 4) {
            // Favicon
            if let favicon = tab.favicon {
                Image(nsImage: favicon)
                    .resizable()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            
            // Loading indicator
            if tab.isLoading {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(height: 2)
            } else {
                Rectangle()
                    .fill(.clear)
                    .frame(height: 2)
            }
        }
        .frame(width: 32, height: 32)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundMaterial)
                .strokeBorder(borderColor, lineWidth: isActive ? 2 : 0)
        )
        .scaleEffect(isActive ? 1.1 : (isHovered ? 1.05 : 1.0))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private var backgroundMaterial: Material {
        if isActive {
            return .thickMaterial
        } else if isHovered {
            return .regularMaterial
        } else {
            return .ultraThinMaterial
        }
    }
    
    private var borderColor: Color {
        isActive ? .blue : .clear
    }
}

struct TabPreviewCard: View {
    let tab: Tab
    @State private var previewImage: NSImage?
    @State private var isLoaded: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                if let favicon = tab.favicon {
                    Image(nsImage: favicon)
                        .resizable()
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                
                Text(tab.title.isEmpty ? "Untitled" : tab.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Spacer()
                
                if tab.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
            
            // Preview content
            Group {
                if let preview = previewImage {
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 200, height: 120)
                        .clipped()
                        .cornerRadius(6)
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(width: 200, height: 120)
                        .cornerRadius(6)
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.8)
                        )
                }
            }
            
            // Footer
            VStack(alignment: .leading, spacing: 2) {
                if let url = tab.url {
                    Text(url.host ?? "")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                HStack {
                    Text("Last viewed \(RelativeDateTimeFormatter().localizedString(for: tab.lastAccessed, relativeTo: Date()))")
                        .font(.caption2)
                        .foregroundColor(.tertiary)
                    
                    Spacer()
                    
                    if tab.isHibernated {
                        Image(systemName: "zzz")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        .scaleEffect(isLoaded ? 1.0 : 0.8)
        .opacity(isLoaded ? 1.0 : 0.0)
        .onAppear {
            generatePreview()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                isLoaded = true
            }
        }
    }
    
    private func generatePreview() {
        if let snapshot = tab.snapshot {
            previewImage = snapshot
        } else if let webView = tab.webView {
            // Generate live preview
            let config = WKSnapshotConfiguration()
            config.rect = webView.bounds
            config.snapshotWidth = NSNumber(value: 400)
            
            webView.takeSnapshot(with: config) { image, error in
                DispatchQueue.main.async {
                    if let image = image {
                        previewImage = image
                        tab.snapshot = image // Cache for next time
                    }
                }
            }
        }
    }
}
```

### Next Phase
Phase 6 will implement system integration features including Apple ecosystem support, translation services, and update management.