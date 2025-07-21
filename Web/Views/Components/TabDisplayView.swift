import SwiftUI

enum TabDisplayMode: String, CaseIterable {
    case sidebar = "sidebar"
    case topBar = "topBar"
    case hidden = "hidden"
}

struct TabDisplayView: View {
    @ObservedObject var tabManager: TabManager
    @AppStorage("tabDisplayMode") private var displayMode: TabDisplayMode = .sidebar
    @State private var isEdgeToEdgeMode: Bool = false
    @State private var showSidebarOnHover: Bool = false
    @State private var showTopBarOnHover: Bool = false
    @State private var showBottomSearchOnHover: Bool = false
    @State private var hideTimer: Timer?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Main content area
                VStack(spacing: 0) {
                    // Top bar tabs (if enabled and not edge-to-edge)
                    if displayMode == .topBar && (!isEdgeToEdgeMode || showTopBarOnHover) {
                        TopBarTabView(tabManager: tabManager)
                            .frame(height: 40)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .opacity(isEdgeToEdgeMode && !showTopBarOnHover ? 0 : 1)
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
                
                // Bottom search overlay (edge-to-edge mode only)
                if isEdgeToEdgeMode {
                    VStack {
                        Spacer()
                        BottomHoverSearch(isVisible: $showBottomSearchOnHover, tabManager: tabManager)
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
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showTopBarOnHover = hovering
                            }
                        }
                    Spacer()
                }
            }
            
            // Bottom edge hover zone for new tab search (better usability)
            VStack {
                Spacer()
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 12) // Increased from 3px to 12px for better UX
                    .onHover { hovering in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showBottomSearchOnHover = hovering
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
}

// Web content area wrapper with rounded corners and margin
struct WebContentArea: View {
    @ObservedObject var tabManager: TabManager
    @State private var urlString: String = ""
    @AppStorage("tabDisplayMode") private var displayMode: TabDisplayMode = .sidebar
    @State private var isEdgeToEdgeMode: Bool = false
    
    // Computed property to get current URL string from active tab
    private var currentURLString: Binding<String> {
        Binding(
            get: {
                if let activeTab = tabManager.activeTab, let url = activeTab.url {
                    return url.absoluteString
                }
                return urlString
            },
            set: { newValue in
                urlString = newValue
            }
        )
    }
    
    var body: some View {
        // Add rounded wrapper with 1px margin
        VStack(spacing: 0) {
            // URL bar (hidden in edge-to-edge mode)
            if !isEdgeToEdgeMode {
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
                        pageTitle: tabManager.activeTab?.title
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
        .onAppear {
            // Initialize with a default URL if needed
            if let firstTab = tabManager.tabs.first, firstTab.url == nil {
                navigateToURL("google.com")
            }
            syncURLString()
        }
        .onChange(of: tabManager.activeTab) { _, newTab in
            syncURLString()
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
        
        activeTab.navigate(to: validURL)
        urlString = validURL.absoluteString
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
    
    private func syncURLString() {
        if let activeTab = tabManager.activeTab, let url = activeTab.url {
            urlString = url.absoluteString
        } else {
            urlString = ""
        }
    }
}