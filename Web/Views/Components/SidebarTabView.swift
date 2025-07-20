import SwiftUI

// Revolutionary Minimal Sidebar - Industry-disrupting favicon-only design
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
                            isHovered: hoveredTab?.id == tab.id,
                            onTap: {
                                tabManager.setActiveTab(tab)
                            },
                            tabManager: tabManager
                        )
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
            // TODO: Open settings 
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
    @ObservedObject var tabManager: TabManager
    
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
                            .transition(.scale.combined(with: .opacity))
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
        // Extract color from favicon for adaptive theming
        return extractedFaviconColor(for: tab)
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
            tabManager.closeTab(tab)
        }) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: 16, height: 16)
                .background(Circle().fill(.ultraThinMaterial))
        }
        .buttonStyle(.plain)
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

// Favicon view component
struct FaviconView: View {
    @ObservedObject var tab: Tab
    let size: CGFloat
    
    var body: some View {
        Group {
            if let favicon = tab.favicon {
                Image(nsImage: favicon)
                    .resizable()
                    .frame(width: size, height: size)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: size * 0.7))
                    .foregroundColor(.secondary)
                    .frame(width: size, height: size)
            }
        }
    }
}

// Tab context menu
struct TabContextMenu: View {
    let tab: Tab
    let tabManager: TabManager
    
    var body: some View {
        Button("Close Tab") {
            tabManager.closeTab(tab)
        }
        
        Button("Duplicate Tab") {
            if let url = tab.url {
                _ = tabManager.createNewTab(url: url)
            }
        }
        
        Button("Pin Tab") {
            // TODO: Implement pinned tabs
        }
        
        Divider()
        
        Button("Close Other Tabs") {
            tabManager.closeOtherTabs(except: tab)
        }
        
        Button("Close Tabs to the Right") {
            tabManager.closeTabsToTheRight(of: tab)
        }
    }
}