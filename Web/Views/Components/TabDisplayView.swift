import SwiftUI

struct TabDisplayView: View {
    @ObservedObject var tabManager: TabManager
    @AppStorage("tabDisplayMode") private var displayMode: TabDisplayMode = .sidebar
    @State private var isEdgeToEdgeMode: Bool = false
    @State private var showSidebarOnHover: Bool = false
    @State private var showTopBarOnHover: Bool = false
    @State private var showBottomSearchOnHover: Bool = false
    
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
                
                // Bottom search overlay (edge-to-edge mode)
                if isEdgeToEdgeMode && showBottomSearchOnHover {
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
            showBottomSearchOnHover = false
        }
    }
}

// Web content area wrapper
struct WebContentArea: View {
    @ObservedObject var tabManager: TabManager
    @State private var urlString: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // URL bar (always visible unless edge-to-edge)
            HStack(spacing: 12) {
                // Navigation controls
                if let activeTab = tabManager.activeTab {
                    NavigationControls(tab: activeTab)
                }
                
                // URL bar
                URLBar(urlString: $urlString, onSubmit: navigateToURL)
                    .frame(maxWidth: .infinity)
                
                // Menu button
                Button(action: showMenu) {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16))
                }
                .buttonStyle(GlassButtonStyle(size: .medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            
            // Web content
            if let activeTab = tabManager.activeTab {
                WebContentView(tab: activeTab, urlString: $urlString)
            } else {
                NewTabView()
            }
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
}