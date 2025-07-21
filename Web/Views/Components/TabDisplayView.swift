import SwiftUI

enum TabDisplayMode: String, CaseIterable {
    case sidebar = "sidebar"
    case topBar = "topBar"
    case hidden = "hidden"
}

struct TabDisplayView: View {
    @ObservedObject var tabManager: TabManager
    @AppStorage("tabDisplayMode") private var displayMode: TabDisplayMode = .sidebar
    @AppStorage("hideTopBar") private var hideTopBar: Bool = false
    @State private var isEdgeToEdgeMode: Bool = false
    @State private var showSidebarOnHover: Bool = false
    @State private var showTopBarOnHover: Bool = false
    @State private var showBottomSearchOnHover: Bool = false
    @State private var showHoverableURLBar: Bool = false
    @State private var hideTimer: Timer?
    @State private var topTabAutoHideTimer: Timer?
    @State private var showTopTabTemporary: Bool = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Main content area
                VStack(spacing: 0) {
                    // Top bar tabs (with borderless auto-hide behavior)
                    if displayMode == .topBar && shouldShowTopTab {
                        TopBarTabView(tabManager: tabManager)
                            .frame(height: 40)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    // Web content
                    HStack(spacing: 0) {
                        // Sidebar tabs (if enabled and not edge-to-edge)
                        if displayMode == .sidebar && (!isEdgeToEdgeMode || showSidebarOnHover) {
                            SidebarTabView(tabManager: tabManager)
                                .frame(width: 50)
                                .transition(.move(edge: .leading).combined(with: .opacity))
                                .opacity(isEdgeToEdgeMode && !showSidebarOnHover ? 0 : 1)
                                .onHover { hovering in
                                    if isEdgeToEdgeMode {
                                        handleSidebarHover(hovering)
                                    }
                                }
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
                
                // Hoverable URL bar overlay (when top bar is hidden or in edge-to-edge mode)
                if hideTopBar || isEdgeToEdgeMode {
                    VStack {
                        if let activeTab = tabManager.activeTab, let url = activeTab.url {
                            HoverableURLBar(
                                urlString: .constant(url.absoluteString),
                                themeColor: activeTab.themeColor,
                                onSubmit: { urlString in
                                    // Handle URL submission
                                    if let newURL = URL(string: urlString) {
                                        activeTab.navigate(to: newURL)
                                    }
                                },
                                pageTitle: activeTab.title,
                                tabManager: tabManager
                            )
                        } else {
                            HoverableURLBar(
                                urlString: .constant(""),
                                themeColor: nil,
                                onSubmit: { urlString in
                                    if let url = URL(string: urlString) {
                                        _ = tabManager.createNewTab(url: url)
                                    }
                                },
                                pageTitle: "New Tab",
                                tabManager: tabManager
                            )
                        }
                        Spacer()
                    }
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
        .onReceive(NotificationCenter.default.publisher(for: .newTabRequested)) { _ in
            tabManager.createNewTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeTabRequested)) { _ in
            if let activeTab = tabManager.activeTab {
                tabManager.closeTab(activeTab)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .reopenTabRequested)) { _ in
            _ = tabManager.reopenLastClosedTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nextTabRequested)) { _ in
            tabManager.selectNextTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: .previousTabRequested)) { _ in
            tabManager.selectPreviousTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectTabByNumber)) { notification in
            if let number = notification.object as? Int {
                tabManager.selectTabByNumber(number)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .createNewTabWithURL)) { notification in
            if let url = notification.object as? URL {
                tabManager.createNewTab(url: url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleTopBar)) { _ in
            hideTopBar.toggle()
            // Restart auto-hide timer when entering borderless mode
            if hideTopBar {
                startTopTabAutoHideTimer()
            } else {
                topTabAutoHideTimer?.invalidate()
                showTopTabTemporary = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateCurrentTab)) { notification in
            if let url = notification.object as? URL {
                if let activeTab = tabManager.activeTab {
                    activeTab.navigate(to: url)
                } else {
                    _ = tabManager.createNewTab(url: url)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .reloadRequested)) { _ in
            if let activeTab = tabManager.activeTab {
                activeTab.reload()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusAddressBarRequested)) { _ in
            // Focus the URL bar - we'll need to implement this with a focus coordinator
            NotificationCenter.default.post(name: .focusURLBarRequested, object: nil)
        }
        .onAppear {
            startTopTabAutoHideTimer()
        }
    }
    
    // Computed property to determine if top tab should be shown
    private var shouldShowTopTab: Bool {
        // In borderless mode with hidden top bar: show temporarily or on hover
        if hideTopBar {
            return showTopTabTemporary || showTopBarOnHover
        }
        // In edge-to-edge mode: show on hover only
        else if isEdgeToEdgeMode {
            return showTopBarOnHover
        }
        // Normal mode: always show
        else {
            return true
        }
    }
    
    private func startTopTabAutoHideTimer() {
        // Only start timer in borderless mode with hidden top bar
        guard hideTopBar else { return }
        
        // Cancel existing timer
        topTabAutoHideTimer?.invalidate()
        
        // Show tab temporarily
        showTopTabTemporary = true
        
        // Set timer to hide after 2 seconds
        topTabAutoHideTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            withAnimation(.easeOut(duration: 0.3)) {
                showTopTabTemporary = false
            }
        }
    }
    
    @ViewBuilder
    private func edgeToEdgeHoverZones(geometry: GeometryProxy) -> some View {
        ZStack {
            // Left edge hover zone for sidebar (better usability)
            if displayMode == .sidebar {
                HStack {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 12) // Keep consistent small trigger zone
                        .onHover { hovering in
                            handleSidebarHover(hovering)
                        }
                    Spacer()
                }
            }
            
            // Top edge hover zone for top bar (better usability)
            if displayMode == .topBar {
                VStack {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 12) // Increased from 3px to 12px for better UX
                        .onHover { hovering in
                            handleTopBarHover(hovering)
                        }
                    Spacer()
                }
            }
            
            // Bottom edge hover zone for hoverable URL bar (when top bar hidden)
            if hideTopBar || displayMode == .hidden {
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 12) // Increased from 3px to 12px for better UX
                        .onHover { hovering in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showHoverableURLBar = hovering
                            }
                        }
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
            showBottomSearchOnHover = false
            showHoverableURLBar = false
        }
    }
    
    private func handleSidebarHover(_ hovering: Bool) {
        hideTimer?.invalidate()
        hideTimer = nil
        
        if hovering {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showSidebarOnHover = true
            }
        } else {
            // Add a longer delay before hiding to allow clicking on tabs
            hideTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showSidebarOnHover = false
                }
            }
        }
    }
    
    private func handleTopBarHover(_ hovering: Bool) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showTopBarOnHover = hovering
        }
        
        // In borderless mode, restart the auto-hide timer when hover ends
        if hideTopBar && !hovering {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                startTopTabAutoHideTimer()
            }
        }
    }
}

// Web content area wrapper with rounded corners and margin
struct WebContentArea: View {
    @ObservedObject var tabManager: TabManager
    @AppStorage("tabDisplayMode") private var displayMode: TabDisplayMode = .sidebar
    @AppStorage("hideTopBar") private var hideTopBar: Bool = false
    @State private var isEdgeToEdgeMode: Bool = false
    
    // Computed property to get current URL string from active tab - NO SHARED STATE
    private var currentURLString: Binding<String> {
        Binding(
            get: {
                if let activeTab = tabManager.activeTab, let url = activeTab.url {
                    return url.absoluteString
                }
                return ""
            },
            set: { newValue in
                // Update the active tab's URL directly, not a shared state
                if let activeTab = tabManager.activeTab,
                   let url = URL(string: newValue) {
                    activeTab.url = url
                }
            }
        )
    }
    
    var body: some View {
        // Add rounded wrapper with 1px margin
        VStack(spacing: 0) {
            // URL bar (hidden in edge-to-edge mode or when hideTopBar is enabled)
            if !isEdgeToEdgeMode && !hideTopBar {
                HStack(spacing: 12) {
                    // Navigation controls
                    if let activeTab = tabManager.activeTab {
                        NavigationControls(tab: activeTab)
                    }
                    
                    // URL bar with reduced height and theme color
                    URLBar(
                        urlString: currentURLString, 
                        themeColor: tabManager.activeTab?.themeColor,
                        onSubmit: navigateToURL,
                        pageTitle: tabManager.activeTab?.title ?? "New Tab"
                    )
                    .frame(maxWidth: .infinity)
                    
                    // Menu button
                    Button(action: showMenu) {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6) // Further reduced for even more minimal height
                .background(
                    ZStack {
                        // Clean base with subtle material
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .opacity(0.3)
                        
                        // Next-gen ambient gradient system
                        if let themeColor = tabManager.activeTab?.themeColor {
                            // Primary ambient glow (top-left origin)
                            Rectangle()
                                .fill(
                                    EllipticalGradient(
                                        colors: [
                                            Color(themeColor).opacity(0.08),
                                            Color(themeColor).opacity(0.05),
                                            Color(themeColor).opacity(0.02),
                                            Color.clear
                                        ],
                                        center: .init(x: 0.1, y: 0.0),
                                        startRadiusFraction: 0.1,
                                        endRadiusFraction: 1.2
                                    )
                                )
                                .animation(.spring(response: 0.8, dampingFraction: 0.8), value: themeColor)
                            
                            // Secondary ambient point (center-right)
                            Rectangle()
                                .fill(
                                    EllipticalGradient(
                                        colors: [
                                            Color.clear,
                                            Color(themeColor).opacity(0.04),
                                            Color(themeColor).opacity(0.07),
                                            Color(themeColor).opacity(0.03),
                                            Color.clear
                                        ],
                                        center: .init(x: 0.85, y: 0.5),
                                        startRadiusFraction: 0.15,
                                        endRadiusFraction: 0.9
                                    )
                                )
                                .animation(.spring(response: 0.8, dampingFraction: 0.8), value: themeColor)
                            
                            // Tertiary diffused glow (bottom spread)
                            Rectangle()
                                .fill(
                                    EllipticalGradient(
                                        colors: [
                                            Color.clear,
                                            Color.clear,
                                            Color(themeColor).opacity(0.03),
                                            Color(themeColor).opacity(0.06),
                                            Color(themeColor).opacity(0.02),
                                            Color.clear
                                        ],
                                        center: .init(x: 0.4, y: 1.0),
                                        startRadiusFraction: 0.2,
                                        endRadiusFraction: 0.8
                                    )
                                )
                                .animation(.spring(response: 0.8, dampingFraction: 0.8), value: themeColor)
                        } else {
                            // Subtle fallback ambient system
                            Rectangle()
                                .fill(
                                    EllipticalGradient(
                                        colors: [
                                            Color.accentBeam.opacity(0.04),
                                            Color.accentBeam.opacity(0.02),
                                            Color.clear
                                        ],
                                        center: .init(x: 0.2, y: 0.0),
                                        startRadiusFraction: 0.15,
                                        endRadiusFraction: 1.0
                                    )
                                )
                            
                            Rectangle()
                                .fill(
                                    EllipticalGradient(
                                        colors: [
                                            Color.clear,
                                            Color.accentBeam.opacity(0.03),
                                            Color.accentBeam.opacity(0.01),
                                            Color.clear
                                        ],
                                        center: .init(x: 0.7, y: 1.0),
                                        startRadiusFraction: 0.3,
                                        endRadiusFraction: 0.7
                                    )
                                )
                        }
                        
                        // Minimal surface highlight
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.015),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                )
            }
            
            // Web content with smart status bar overlay
            ZStack(alignment: .bottom) {
                if let activeTab = tabManager.activeTab {
                    WebContentView(tab: activeTab, urlString: currentURLString)
                } else {
                    NewTabView()
                }
            }
        }
        .background(Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(2) // 2px margin as requested
        .onReceive(NotificationCenter.default.publisher(for: .toggleEdgeToEdge)) { _ in
            isEdgeToEdgeMode.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleTopBar)) { _ in
            // This ensures both components stay in sync
        }
        .onAppear {
            // Initialize with a default URL if needed
            if let firstTab = tabManager.tabs.first, firstTab.url == nil {
                navigateToURL("google.com")
            }
        }
    }
    
    private func navigateToURL(_ url: String) {
        guard let activeTab = tabManager.activeTab else { return }
        
        let processedURL: URL?
        
        // Use same logic as URLBar for consistency
        if isValidURL(url) {
            if url.hasPrefix("http://") || url.hasPrefix("https://") {
                processedURL = URL(string: url)
            } else {
                processedURL = URL(string: "https://\(url)")
            }
        } else {
            // Search Google for anything that doesn't look like a URL
            let query = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            processedURL = URL(string: "https://www.google.com/search?q=\(query)")
        }
        
        guard let validURL = processedURL else { return }
        
        // Navigate to URL - tab manages its own state
        activeTab.navigate(to: validURL)
    }
    
    private func isValidURL(_ string: String) -> Bool {
        // Check if it already has a scheme
        if string.hasPrefix("http://") || string.hasPrefix("https://") {
            return URL(string: string) != nil
        }
        
        // Check if it looks like a domain (contains . and no spaces)
        if string.contains(".") && !string.contains(" ") {
            // Make sure it's not just a decimal number
            if !string.allSatisfy({ $0.isNumber || $0 == "." }) {
                return true
            }
        }
        
        return false
    }
    
    private func showMenu() {
        // TODO: Implement menu functionality
    }
    
}