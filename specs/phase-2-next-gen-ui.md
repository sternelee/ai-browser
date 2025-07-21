# Phase 2: Next-Generation UI/UX - Detailed Implementation

## Overview
This phase implements the revolutionary user interface features that will "disrupt the industry" including custom glass windows, favicon-only sidebar, and edge-to-edge mode.

## 1. Custom Glass Window System

### Revolutionary Glass Window Implementation
```swift
// GlassWindow.swift - Custom window with advanced glass effects
import SwiftUI
import AppKit

class GlassWindow: NSWindow {
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        
        setupGlassEffect()
        setupCustomTitleBar()
        setupHoverTracking()
    }
    
    private func setupGlassEffect() {
        // Enable glass effect
        appearance = NSAppearance(named: .aqua)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        
        // Custom material and blur
        if let contentView = contentView {
            let visualEffect = NSVisualEffectView()
            visualEffect.material = .hudWindow
            visualEffect.blendingMode = .behindWindow
            visualEffect.state = .active
            
            contentView.addSubview(visualEffect, positioned: .below, relativeTo: nil)
            visualEffect.frame = contentView.bounds
            visualEffect.autoresizingMask = [.width, .height]
        }
        
        // Subtle border radius (requires custom drawing)
        contentView?.wantsLayer = true
        contentView?.layer?.cornerRadius = 12
        contentView?.layer?.masksToBounds = true
        
        // Super slight padding
        if let contentView = contentView {
            contentView.frame = contentView.frame.insetBy(dx: 8, dy: 8)
        }
    }
    
    private func setupCustomTitleBar() {
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        
        // Create collapsible title bar (Arc-style)
        let titleBarHeight: CGFloat = 40
        
        // Position window controls in custom positions
        if let closeButton = standardWindowButton(.closeButton),
           let miniButton = standardWindowButton(.miniaturizeButton),
           let zoomButton = standardWindowButton(.zoomButton) {
            
            // Initially hide controls
            closeButton.alphaValue = 0.0
            miniButton.alphaValue = 0.0
            zoomButton.alphaValue = 0.0
            
            // Position controls with subtle spacing
            let controlsFrame = NSRect(x: 16, y: frame.height - 32, width: 60, height: 16)
            closeButton.frame = NSRect(x: controlsFrame.minX, y: controlsFrame.minY, width: 16, height: 16)
            miniButton.frame = NSRect(x: controlsFrame.minX + 20, y: controlsFrame.minY, width: 16, height: 16)
            zoomButton.frame = NSRect(x: controlsFrame.minX + 40, y: controlsFrame.minY, width: 16, height: 16)
        }
    }
    
    private func setupHoverTracking() {
        // Setup mouse tracking for hover effects
        let trackingArea = NSTrackingArea(
            rect: NSRect(x: 0, y: frame.height - 50, width: frame.width, height: 50),
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        contentView?.addTrackingArea(trackingArea)
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        showWindowControls()
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hideWindowControls()
    }
    
    private func showWindowControls() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.allowsImplicitAnimation = true
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            standardWindowButton(.closeButton)?.alphaValue = 1.0
            standardWindowButton(.miniaturizeButton)?.alphaValue = 1.0
            standardWindowButton(.zoomButton)?.alphaValue = 1.0
        }
    }
    
    private func hideWindowControls() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.allowsImplicitAnimation = true
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            standardWindowButton(.closeButton)?.alphaValue = 0.0
            standardWindowButton(.miniaturizeButton)?.alphaValue = 0.0
            standardWindowButton(.zoomButton)?.alphaValue = 0.0
        }
    }
}

// SwiftUI wrapper for custom glass window
struct GlassWindowView<Content: View>: NSViewControllerRepresentable {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    func makeNSViewController(context: Context) -> NSViewController {
        let viewController = NSViewController()
        let hostingView = NSHostingView(rootView: content)
        viewController.view = hostingView
        return viewController
    }
    
    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {
        if let hostingView = nsViewController.view as? NSHostingView<Content> {
            hostingView.rootView = content
        }
    }
}
```

## 2. Revolutionary Tab Management UI

### Tab Display Mode Toggle System
```swift
// TabDisplayView.swift - Revolutionary tab management
import SwiftUI

struct TabDisplayView: View {
    @ObservedObject var tabManager: TabManager
    @AppStorage("tabDisplayMode") private var displayMode: TabDisplayMode = .sidebar
    @State private var isEdgeToEdgeMode: Bool = false
    @State private var showSidebarOnHover: Bool = false
    @State private var showTopBarOnHover: Bool = false
    
    enum TabDisplayMode: String, CaseIterable {
        case sidebar = "sidebar"
        case topBar = "topBar"
        case hidden = "hidden"
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Main content area
                VStack(spacing: 0) {
                    // Top bar tabs (if enabled and not edge-to-edge)
                    if displayMode == .topBar && (!isEdgeToEdgeMode || showTopBarOnHover) {
                        TopBarTabView(tabManager: tabManager)
                            .frame(height: 40)
                            .background(.ultraThinMaterial)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .opacity(isEdgeToEdgeMode && !showTopBarOnHover ? 0 : 1)
                    }
                    
                    // Web content
                    HStack(spacing: 0) {
                        // Sidebar tabs (if enabled and not edge-to-edge)
                        if displayMode == .sidebar && (!isEdgeToEdgeMode || showSidebarOnHover) {
                            SidebarTabView(tabManager: tabManager)
                                .frame(width: 60)
                                .background(.ultraThinMaterial)
                                .transition(.move(edge: .leading).combined(with: .opacity))
                                .opacity(isEdgeToEdgeMode && !showSidebarOnHover ? 0 : 1)
                        }
                        
                        // Main web content
                        WebContentArea(tabManager: tabManager)
                            .clipped()
                    }
                }
                
                // Edge-to-edge hover zones
                if isEdgeToEdgeMode {
                    edgeToEdgeHoverZones(geometry: geometry)
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: displayMode)
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: isEdgeToEdgeMode)
        .animation(.easeInOut(duration: 0.2), value: showSidebarOnHover)
        .animation(.easeInOut(duration: 0.2), value: showTopBarOnHover)
        .onReceive(NotificationCenter.default.publisher(for: .toggleTabDisplay)) { _ in
            toggleTabDisplay()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleEdgeToEdge)) { _ in
            toggleEdgeToEdgeMode()
        }
    }
    
    @ViewBuilder
    private func edgeToEdgeHoverZones(geometry: GeometryProxy) -> some View {
        ZStack {
            // Left edge hover zone for sidebar (macOS 18 Finder-style)
            if displayMode == .sidebar {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 20) // Larger hover zone for better UX
                    .frame(maxHeight: .infinity)
                    .position(x: 10, y: geometry.size.height / 2)
                    .onHover { hovering in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showSidebarOnHover = hovering
                        }
                    }
            }
            
            // Top edge hover zone for top bar (macOS 18 Finder-style)
            if displayMode == .topBar {
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 20) // Larger hover zone
                    .frame(maxWidth: .infinity)
                    .position(x: geometry.size.width / 2, y: 10)
                    .onHover { hovering in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showTopBarOnHover = hovering
                        }
                    }
            }
            
            // Bottom edge hover zone for new tab search (inspired by macOS 18)
            Rectangle()
                .fill(Color.clear)
                .frame(height: 20)
                .frame(maxWidth: .infinity)
                .position(x: geometry.size.width / 2, y: geometry.size.height - 10)
                .onHover { hovering in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showBottomSearchOnHover = hovering
                    }
                }
        }
    }
    
    private func toggleTabDisplay() {
        switch displayMode {
        case .sidebar:
            displayMode = .topBar
        case .topBar:
            displayMode = .sidebar
        case .hidden:
            displayMode = .sidebar
        }
    }
    
    private func toggleEdgeToEdgeMode() {
        isEdgeToEdgeMode.toggle()
        
        // Reset hover states when exiting edge-to-edge
        if !isEdgeToEdgeMode {
            showSidebarOnHover = false
            showTopBarOnHover = false
        }
    }
}
```

### Revolutionary Minimal Sidebar
```swift
// SidebarTabView.swift - Industry-disrupting favicon-only sidebar
import SwiftUI

struct SidebarTabView: View {
    @ObservedObject var tabManager: TabManager
    @State private var draggedTab: Tab?
    @State private var hoveredTab: Tab?
    
    var body: some View {
        VStack(spacing: 0) {
            // Top section with new tab button
            VStack(spacing: 4) {
                newTabButton
                
                if !tabManager.tabs.isEmpty {
                    Divider()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
            }
            .padding(.top, 8)
            
            // Tab list
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(tabManager.tabs) { tab in
                        SidebarTabItem(
                            tab: tab,
                            isActive: tab.id == tabManager.activeTab?.id,
                            isHovered: hoveredTab?.id == tab.id
                        ) {
                            tabManager.setActiveTab(tab)
                        }
                        .onHover { hovering in
                            hoveredTab = hovering ? tab : nil
                        }
                        .contextMenu {
                            TabContextMenu(tab: tab, tabManager: tabManager)
                        }
                        .draggable(tab) {
                            FaviconView(tab: tab, size: 24)
                                .opacity(0.8)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            
            Spacer()
            
            // Bottom section with settings
            VStack(spacing: 4) {
                Divider()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                
                settingsButton
            }
            .padding(.bottom, 8)
        }
        .frame(width: 60)
        .background(.ultraThinMaterial)
        .dropDestination(for: Tab.self) { tabs, location in
            handleTabDrop(tabs: tabs, location: location)
            return true
        }
    }
    
    private var newTabButton: some View {
        Button(action: { 
            _ = tabManager.createNewTab() 
        }) {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(SidebarButtonStyle())
    }
    
    private var settingsButton: some View {
        Button(action: { 
            // Open settings 
        }) {
            Image(systemName: "gearshape")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(SidebarButtonStyle())
    }
    
    private func handleTabDrop(tabs: [Tab], location: CGPoint) {
        // Handle tab reordering logic
        guard let droppedTab = tabs.first,
              let fromIndex = tabManager.tabs.firstIndex(where: { $0.id == droppedTab.id }) else { return }
        
        // Calculate drop position based on location
        let tabHeight: CGFloat = 44
        let dropIndex = min(max(0, Int(location.y / tabHeight)), tabManager.tabs.count - 1)
        
        if fromIndex != dropIndex {
            tabManager.tabs.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: dropIndex)
        }
    }
}

struct SidebarTabItem: View {
    let tab: Tab
    let isActive: Bool
    let isHovered: Bool
    let onTap: () -> Void
    
    @State private var showCloseButton: Bool = false
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Background with adaptive color based on favicon
                backgroundView
                
                // Main content
                VStack(spacing: 4) {
                    // Favicon or loading indicator
                    faviconView
                    
                    // Close button (appears on hover)
                    if showCloseButton && isHovered {
                        closeButton
                    }
                }
                .frame(width: 44, height: 44)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                showCloseButton = hovering
            }
        }
        .scaleEffect(isActive ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
    }
    
    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(backgroundMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(borderColor, lineWidth: isActive ? 2 : 0)
            )
            .shadow(color: .black.opacity(isActive ? 0.1 : 0), radius: 2, x: 0, y: 1)
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
        if isActive {
            // Extract color from favicon or use default blue
            return extractedFaviconColor ?? .blue
        }
        return .clear
    }
    
    private var extractedFaviconColor: Color? {
        // TODO: Implement favicon color extraction
        // This would analyze the dominant color in the favicon
        return nil
    }
    
    private var faviconView: some View {
        Group {
            if tab.isLoading {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 24, height: 24)
            } else {
                FaviconView(tab: tab, size: 24)
            }
        }
    }
    
    private var closeButton: some View {
        Button(action: {
            TabManager.shared.closeTab(tab)
        }) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: 16, height: 16)
                .background(Circle().fill(.ultraThinMaterial))
        }
        .buttonStyle(.plain)
        .transition(.scale.combined(with: .opacity))
    }
}

struct SidebarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.ultraThinMaterial)
                    .opacity(configuration.isPressed ? 0.8 : 1.0)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
```

### Top Bar Tab Implementation
```swift
// TopBarTabView.swift - Horizontal tab bar for top display mode
import SwiftUI

struct TopBarTabView: View {
    @ObservedObject var tabManager: TabManager
    @State private var draggedTab: Tab?
    
    var body: some View {
        HStack(spacing: 0) {
            // Tab list
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(tabManager.tabs) { tab in
                        TopBarTabItem(
                            tab: tab,
                            isActive: tab.id == tabManager.activeTab?.id
                        ) {
                            tabManager.setActiveTab(tab)
                        }
                        .frame(minWidth: 120, maxWidth: 200, idealWidth: 180)
                        .contextMenu {
                            TabContextMenu(tab: tab, tabManager: tabManager)
                        }
                        .draggable(tab) {
                            TopBarTabPreview(tab: tab)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
            
            // New tab button
            Button(action: { 
                _ = tabManager.createNewTab() 
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(TopBarButtonStyle())
            .padding(.trailing, 8)
        }
        .frame(height: 40)
        .background(.ultraThinMaterial)
        .dropDestination(for: Tab.self) { tabs, location in
            // Handle tab reordering
            return true
        }
    }
}

struct TopBarTabItem: View {
    let tab: Tab
    let isActive: Bool
    let onTap: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // Favicon
                if tab.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                } else {
                    FaviconView(tab: tab, size: 16)
                }
                
                // Title
                Text(tab.title)
                    .font(.system(.caption, weight: isActive ? .medium : .regular))
                    .lineLimit(1)
                    .foregroundColor(isActive ? .primary : .secondary)
                
                Spacer(minLength: 0)
                
                // Close button
                if isHovered {
                    Button(action: {
                        TabManager.shared.closeTab(tab)
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? .selection : .clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(isActive ? .blue : .clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

struct TopBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.ultraThinMaterial)
                    .opacity(configuration.isPressed ? 0.8 : 1.0)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
```

## 3. Edge-to-Edge Mode Implementation *(macOS 18 Finder-Inspired)*

### Seamless Borderless Browsing Experience
*Reference: macOS 18 Finder interface - content is never obscured, controls appear from edges on hover*
```swift
// EdgeToEdgeController.swift - Complete chrome hiding functionality
import SwiftUI
import AppKit

class EdgeToEdgeController: ObservableObject {
    @Published var isEdgeToEdgeMode: Bool = false
    
    private weak var window: NSWindow?
    private var originalWindowLevel: NSWindow.Level = .normal
    private var originalStyleMask: NSWindow.StyleMask = []
    
    func configure(window: NSWindow) {
        self.window = window
        self.originalWindowLevel = window.level
        self.originalStyleMask = window.styleMask
    }
    
    func toggleEdgeToEdgeMode() {
        isEdgeToEdgeMode.toggle()
        
        guard let window = window else { return }
        
        if isEdgeToEdgeMode {
            enterEdgeToEdgeMode(window: window)
        } else {
            exitEdgeToEdgeMode(window: window)
        }
    }
    
    private func enterEdgeToEdgeMode(window: NSWindow) {
        // Hide title bar completely
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        
        // Remove window decorations
        window.styleMask.remove(.titled)
        window.styleMask.remove(.closable)
        window.styleMask.remove(.miniaturizable)
        window.styleMask.remove(.resizable)
        
        // Make window borderless
        window.styleMask.insert(.borderless)
        
        // Hide window controls
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        
        // Animate to fullscreen-like experience
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.allowsImplicitAnimation = true
            
            if let screen = window.screen {
                let screenFrame = screen.visibleFrame
                window.setFrame(screenFrame, display: true, animate: true)
            }
        }
        
        // Setup gesture recognizers for navigation
        setupEdgeToEdgeGestures(window: window)
    }
    
    private func exitEdgeToEdgeMode(window: NSWindow) {
        // Restore window decorations
        window.styleMask = originalStyleMask
        
        // Show window controls
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false
        
        // Restore title bar
        window.titleVisibility = .hidden // Keep hidden for custom design
        window.titlebarAppearsTransparent = true
        
        // Remove gesture recognizers
        removeEdgeToEdgeGestures(window: window)
    }
    
    private func setupEdgeToEdgeGestures(window: NSWindow) {
        // Add two-finger swipe gesture for navigation
        let swipeGesture = NSPanGestureRecognizer(target: self, action: #selector(handleSwipeGesture(_:)))
        window.contentView?.addGestureRecognizer(swipeGesture)
        
        // Add escape key handler to exit edge-to-edge mode
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape key
                self?.toggleEdgeToEdgeMode()
                return nil
            }
            return event
        }
    }
    
    private func removeEdgeToEdgeGestures(window: NSWindow) {
        // Remove gesture recognizers
        window.contentView?.gestureRecognizers.removeAll()
    }
    
    @objc private func handleSwipeGesture(_ gesture: NSPanGestureRecognizer) {
        let translation = gesture.translation(in: gesture.view)
        
        if gesture.state == .ended {
            // Determine swipe direction and perform navigation
            if abs(translation.x) > abs(translation.y) {
                if translation.x > 50 {
                    // Swipe right - go back
                    NotificationCenter.default.post(name: .navigateBack, object: nil)
                } else if translation.x < -50 {
                    // Swipe left - go forward
                    NotificationCenter.default.post(name: .navigateForward, object: nil)
                }
            }
        }
    }
}
```

## 4. Bottom Hover Search Implementation *(macOS 18 Finder-Inspired)*

### Seamless New Tab Input that Never Obfuscates Content
```swift
// BottomHoverSearch.swift - Edge-reveal search input inspired by macOS 18
import SwiftUI

struct BottomHoverSearch: View {
    @Binding var isVisible: Bool
    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool
    @State private var suggestions: [SearchSuggestion] = []
    
    struct SearchSuggestion: Identifiable {
        let id = UUID()
        let text: String
        let type: SuggestionType
        
        enum SuggestionType {
            case search, url, history
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search suggestions (if any)
            if !suggestions.isEmpty && isSearchFocused {
                suggestionsList
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Main search bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16, weight: .medium))
                
                TextField("Search Google or enter website", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(.body, weight: .regular))
                    .focused($isSearchFocused)
                    .onSubmit {
                        performSearch()
                    }
                    .onChange(of: searchText) { newValue in
                        updateSuggestions(for: newValue)
                    }
                
                if !searchText.isEmpty {
                    Button(action: { 
                        searchText = ""
                        suggestions = []
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(searchBarBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: -2)
        }
        .frame(maxWidth: 500) // Centered, reasonable width
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .offset(y: isVisible ? 0 : 100) // Slide up from bottom
        .opacity(isVisible ? 1 : 0)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isVisible)
        .onAppear {
            if isVisible {
                // Small delay to ensure smooth animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isSearchFocused = true
                }
            }
        }
        .onChange(of: isVisible) { visible in
            if !visible {
                isSearchFocused = false
                searchText = ""
                suggestions = []
            }
        }
    }
    
    private var searchBarBackground: some View {
        ZStack {
            // Backdrop blur effect
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
            
            // Subtle border
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isSearchFocused ? .blue.opacity(0.5) : .primary.opacity(0.1), 
                    lineWidth: 1
                )
        }
    }
    
    private var suggestionsList: some View {
        VStack(spacing: 0) {
            ForEach(suggestions.prefix(5)) { suggestion in
                Button(action: {
                    searchText = suggestion.text
                    performSearch()
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: suggestionIcon(for: suggestion.type))
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                            .frame(width: 16)
                        
                        Text(suggestion.text)
                            .font(.system(.body))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        if suggestion.type == .history {
                            Image(systemName: "clock")
                                .foregroundColor(.tertiary)
                                .font(.system(size: 12))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    // Subtle hover effect could be added here
                }
                
                if suggestion.id != suggestions.prefix(5).last?.id {
                    Divider()
                        .padding(.horizontal, 20)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: -1)
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }
    
    private func suggestionIcon(for type: SearchSuggestion.SuggestionType) -> String {
        switch type {
        case .search:
            return "magnifyingglass"
        case .url:
            return "globe"
        case .history:
            return "clock.arrow.circlepath"
        }
    }
    
    private func updateSuggestions(for query: String) {
        guard !query.isEmpty else {
            suggestions = []
            return
        }
        
        // Simulate search suggestions (in real implementation, this would query history, bookmarks, etc.)
        var newSuggestions: [SearchSuggestion] = []
        
        // Add search suggestion
        newSuggestions.append(SearchSuggestion(text: query, type: .search))
        
        // Add URL suggestion if it looks like a URL
        if query.contains(".") && !query.contains(" ") {
            newSuggestions.append(SearchSuggestion(text: "https://\(query)", type: .url))
        }
        
        // Add mock history suggestions
        let mockHistory = ["github.com", "stackoverflow.com", "developer.apple.com"]
        for item in mockHistory {
            if item.contains(query.lowercased()) {
                newSuggestions.append(SearchSuggestion(text: item, type: .history))
            }
        }
        
        suggestions = newSuggestions
    }
    
    private func performSearch() {
        guard !searchText.isEmpty else { return }
        
        // Navigate to URL or perform search
        if isValidURL(searchText) {
            navigateToURL(searchText)
        } else {
            performGoogleSearch(searchText)
        }
        
        // Hide the search bar after search
        isVisible = false
    }
    
    private func isValidURL(_ string: String) -> Bool {
        return string.contains(".") && !string.contains(" ") && URL(string: addHttpIfNeeded(string)) != nil
    }
    
    private func addHttpIfNeeded(_ string: String) -> String {
        if string.hasPrefix("http://") || string.hasPrefix("https://") {
            return string
        }
        return "https://\(string)"
    }
    
    private func navigateToURL(_ urlString: String) {
        if let url = URL(string: addHttpIfNeeded(urlString)) {
            _ = TabManager.shared.createNewTab(url: url)
        }
    }
    
    private func performGoogleSearch(_ query: String) {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://www.google.com/search?q=\(encodedQuery)") {
            _ = TabManager.shared.createNewTab(url: url)
        }
    }
}

// Integration with the main EdgeToEdge view
struct EdgeToEdgeWithBottomSearch: View {
    @State private var showBottomSearch: Bool = false
    
    var body: some View {
        ZStack {
            // Main web content (always full screen, never obscured)
            WebContentView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Bottom hover zone (invisible)
            VStack {
                Spacer()
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 30)
                    .onHover { hovering in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showBottomSearch = hovering
                        }
                    }
            }
            
            // Bottom search overlay (slides up from bottom, never overlays content)
            VStack {
                Spacer()
                BottomHoverSearch(isVisible: $showBottomSearch)
            }
        }
    }
}
```

## 5. Logo Design Implementation

### Minimal "W" SVG Logo
```swift
// WebLogo.swift - Adaptive SVG logo implementation
import SwiftUI

struct WebLogo: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // Background circle with subtle gradient
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            logoBackgroundColor.opacity(0.1),
                            logoBackgroundColor.opacity(0.05)
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 40
                    )
                )
            
            // Main "W" shape
            LogoShape()
                .fill(logoForegroundColor)
                .frame(width: 32, height: 24)
        }
    }
    
    private var logoBackgroundColor: Color {
        colorScheme == .dark ? .white : .black
    }
    
    private var logoForegroundColor: Color {
        colorScheme == .dark ? .white : .black
    }
}

struct LogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let width = rect.width
        let height = rect.height
        
        // Create the "W" shape with clean, minimal lines
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: width * 0.2, y: height))
        path.addLine(to: CGPoint(x: width * 0.35, y: height * 0.4))
        path.addLine(to: CGPoint(x: width * 0.5, y: height * 0.8))
        path.addLine(to: CGPoint(x: width * 0.65, y: height * 0.4))
        path.addLine(to: CGPoint(x: width * 0.8, y: height))
        path.addLine(to: CGPoint(x: width, y: 0))
        path.addLine(to: CGPoint(x: width * 0.85, y: 0))
        path.addLine(to: CGPoint(x: width * 0.65, y: height * 0.6))
        path.addLine(to: CGPoint(x: width * 0.5, y: height * 0.2))
        path.addLine(to: CGPoint(x: width * 0.35, y: height * 0.6))
        path.addLine(to: CGPoint(x: width * 0.15, y: 0))
        path.closeSubpath()
        
        return path
    }
}

// Animated logo for loading states
struct AnimatedWebLogo: View {
    @State private var isAnimating: Bool = false
    
    var body: some View {
        WebLogo()
            .scaleEffect(isAnimating ? 1.1 : 1.0)
            .opacity(isAnimating ? 0.8 : 1.0)
            .animation(
                .easeInOut(duration: 1.0)
                .repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

// App icon generator (for use in Xcode project)
struct AppIconGenerator: View {
    let size: CGFloat
    
    var body: some View {
        ZStack {
            // App icon background with subtle gradient
            RoundedRectangle(cornerRadius: size * 0.2)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.1, green: 0.1, blue: 0.15),
                            Color(red: 0.05, green: 0.05, blue: 0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Logo with proper scaling
            WebLogo()
                .frame(width: size * 0.6, height: size * 0.6)
        }
        .frame(width: size, height: size)
    }
}
```

## 5. Adaptive Glass Effects

### Dynamic Tint System
```swift
// AdaptiveGlassEffect.swift - Dynamic glass tinting based on content
import SwiftUI
import AppKit

struct AdaptiveGlassBackground: View {
    @ObservedObject var tab: Tab
    @State private var dominantColor: Color = .clear
    @State private var colorExtractionTask: Task<Void, Never>?
    
    var body: some View {
        ZStack {
            // Base glass material
            Rectangle()
                .fill(.ultraThinMaterial)
            
            // Adaptive tint overlay
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            dominantColor.opacity(0.03),
                            dominantColor.opacity(0.01)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .animation(.easeInOut(duration: 0.5), value: dominantColor)
        }
        .onReceive(tab.$favicon) { favicon in
            extractDominantColor(from: favicon)
        }
        .onReceive(tab.$url) { _ in
            // Reset color when URL changes
            dominantColor = .clear
        }
    }
    
    private func extractDominantColor(from image: NSImage?) {
        colorExtractionTask?.cancel()
        
        colorExtractionTask = Task {
            guard let image = image,
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                await MainActor.run {
                    dominantColor = .clear
                }
                return
            }
            
            let color = await extractDominantColorFromCGImage(cgImage)
            
            await MainActor.run {
                if !Task.isCancelled {
                    dominantColor = color
                }
            }
        }
    }
    
    private func extractDominantColorFromCGImage(_ cgImage: CGImage) async -> Color {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let width = cgImage.width
                let height = cgImage.height
                let bytesPerPixel = 4
                let bytesPerRow = bytesPerPixel * width
                let bitsPerComponent = 8
                
                var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
                
                let context = CGContext(
                    data: &pixelData,
                    width: width,
                    height: height,
                    bitsPerComponent: bitsPerComponent,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
                
                context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
                
                var redSum: Int = 0
                var greenSum: Int = 0
                var blueSum: Int = 0
                var pixelCount: Int = 0
                
                for y in 0..<height {
                    for x in 0..<width {
                        let pixelIndex = (y * width + x) * bytesPerPixel
                        let red = Int(pixelData[pixelIndex])
                        let green = Int(pixelData[pixelIndex + 1])
                        let blue = Int(pixelData[pixelIndex + 2])
                        let alpha = Int(pixelData[pixelIndex + 3])
                        
                        if alpha > 128 { // Only consider non-transparent pixels
                            redSum += red
                            greenSum += green
                            blueSum += blue
                            pixelCount += 1
                        }
                    }
                }
                
                if pixelCount > 0 {
                    let avgRed = Double(redSum) / Double(pixelCount) / 255.0
                    let avgGreen = Double(greenSum) / Double(pixelCount) / 255.0
                    let avgBlue = Double(blueSum) / Double(pixelCount) / 255.0
                    
                    continuation.resume(returning: Color(red: avgRed, green: avgGreen, blue: avgBlue))
                } else {
                    continuation.resume(returning: .clear)
                }
            }
        }
    }
}
```

## Implementation Notes

### ✅ Completed Improvements (Latest Session)
- **Enhanced tab spacing**: Increased gap between sidebar tabs from 2px to 8px for better visual separation
- **Glowy selected tab effect**: Only active tabs now have enhanced gradient, shadow, and border effects for better focus
- **Optimized sidebar width**: Reduced from 60px to 50px for more screen real estate
- **Improved URL bar**: Reduced height with smaller padding (4px vs 6px) and removed button background boxes
- **Fixed Web logo size**: Reduced favicon size from 32x24 to 16x12 for proper proportions
- **Enhanced hover behavior**: Fixed borderless mode sidebar with expanded hover zones and delay timers to prevent flickering
- **Better delete button UX**: Close button now replaces favicon on hover instead of stacking vertically

### ✅ Additional UI Refinements (Second Session)
- **Removed boxes from non-selected tabs**: Non-active sidebar tabs now have clean, minimal appearance without background boxes
- **Fixed favicon auto-updating**: Made FaviconView properly reactive with @ObservedObject to ensure favicon updates appear in sidebar
- **Fixed spinner size**: Constrained progress spinner in top tab bar to 16x16 with proper frame to prevent height issues
- **Minimalist navigation buttons**: Removed background boxes from back/forward/reload buttons, increased touch target to 20x20
- **Next-gen sidebar close button**: Redesigned close button to appear on the right with subtle red tint, glass material background, and proper positioning

### ✅ Final Polish & UX Fixes (Third Session)
- **Fixed favicon positioning**: Favicon now stays centered in sidebar tabs instead of moving when close button appears
- **Compact active tab styling**: Made selected tab background box 6px smaller (3px padding) while maintaining same internal spacing
- **Fixed borderless mode clicking**: Resolved issue where hover zones blocked tab clicks by using allowsHitTesting() conditionally
- **Enhanced window controls**: Minimize button now uses orange-to-yellow gradient, maximize button increased from 8px to 10px
- **Functional window controls**: All window control buttons now properly trigger minimize, maximize, and close actions

### Revolutionary Features *(macOS 18 Finder-Inspired)*
- **Favicon-only sidebar**: Industry-first minimal design showing only favicons
- **Smart window controls**: Appear only on hover for ultimate minimalism
- **Edge-to-edge mode**: Complete chrome hiding with gesture navigation, following macOS 18 principle of never obscuring content
- **Bottom hover search**: Seamless new tab input that slides up from bottom edge on hover, inspired by macOS 18 Finder's edge-reveal interactions
- **Adaptive glass**: Dynamic tinting based on website/favicon colors
- **Content-first design**: Website content is never obfuscated - all UI elements reveal from edges without overlaying the main content area

### Performance Optimizations
- Efficient color extraction using Core Graphics
- Smooth animations with spring physics
- Memory-conscious tab management
- GPU-accelerated visual effects

### Next Phase
Phase 3 will implement advanced features including the new tab experience, smart status bar, and performance enhancements.