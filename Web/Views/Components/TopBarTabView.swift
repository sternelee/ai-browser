import SwiftUI

struct TopBarTabView: View {
    @ObservedObject var tabManager: TabManager
    @State private var draggedTab: Web.Tab?
    @State private var hoveredTabId: UUID?
    
    var body: some View {
        HStack(spacing: 0) {
            // Window controls as first element in square format
            CompactWindowControls()
                .padding(.leading, 8)
            
            // Small vertical divider
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.15),
                            Color.white.opacity(0.03)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 0.5)
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            
            tabScrollView
        }
        .frame(height: 40)
        .background(WindowDragArea())  // Make top bar draggable
        .dropDestination(for: Web.Tab.self) { tabs, location in
            handleTabDrop(tabs: tabs, location: location)
            return true
        }
    }
    
    private var tabScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(tabManager.tabs) { tab in
                    TopBarTabItem(
                        tab: tab,
                        isActive: tab.id == tabManager.activeTab?.id,
                        isHovered: hoveredTabId == tab.id,
                        onTap: { tabManager.setActiveTab(tab) },
                        tabManager: tabManager
                    )
                    .frame(minWidth: 140, idealWidth: 180, maxWidth: 220)
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            hoveredTabId = hovering ? tab.id : nil
                        }
                    }
                    .draggable(tab) {
                        TopBarTabPreview(tab: tab)
                    }
                }
                
                // New tab button positioned after tabs
                newTabButton
                    .padding(.leading, 8)
            }
            .padding(.horizontal, 12)
        }
    }
    
    
    private var topBarBackground: some View {
        ZStack {
            // Beautiful glass material
            Rectangle()
                .fill(.regularMaterial)
            
            // Soft glass overlay with gradient
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Subtle bottom border
            VStack {
                Spacer()
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.15),
                                Color.white.opacity(0.03)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 0.5)
            }
        }
    }
    
    private var newTabButton: some View {
        Button(action: { 
            _ = tabManager.createNewTab() 
        }) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.secondary)
                .frame(width: 32, height: 28)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    
    private func handleTabDrop(tabs: [Web.Tab], location: CGPoint) {
        guard let droppedTab = tabs.first,
              let fromIndex = tabManager.tabs.firstIndex(where: { $0.id == droppedTab.id }) else { return }
        
        // Calculate drop position based on horizontal layout
        let tabWidth: CGFloat = 180
        let dropIndex = min(max(0, Int(location.x / tabWidth)), tabManager.tabs.count - 1)
        
        if fromIndex != dropIndex {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                tabManager.tabs.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: dropIndex)
            }
        }
    }
}

struct TopBarTabItem: View {
    let tab: Web.Tab
    let isActive: Bool
    let isHovered: Bool
    let onTap: () -> Void
    let tabManager: TabManager
    
    @State private var showCloseButton: Bool = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // Favicon with proper view
                if tab.isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .tint(.textSecondary)
                        .frame(width: 16, height: 16)
                } else {
                    FaviconView(tab: tab, size: 16)
                }
                
                // Title
                Text(tab.title.isEmpty ? "New Tab" : tab.title)
                    .font(.system(size: 13))
                    .fontWeight(isActive ? .medium : .regular)
                    .lineLimit(1)
                    .foregroundColor(isActive ? .textPrimary : .textSecondary)
                
                Spacer(minLength: 0)
                
                // Close button
                if showCloseButton {
                    Button(action: {
                        tabManager.closeTab(tab)
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(Color.secondary)
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? .regularMaterial : .ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                isActive ? 
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.6), Color.blue.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ) :
                                LinearGradient(
                                    colors: [Color.white.opacity(0.1), Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: isActive ? 1 : 0.5
                            )
                    )
                    .shadow(
                        color: isActive ? .black.opacity(0.1) : .clear,
                        radius: isActive ? 4 : 0,
                        x: 0,
                        y: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            showCloseButton = hovering
        }
    }
}

// Tab preview for drag operations
struct TopBarTabPreview: View {
    let tab: Web.Tab
    
    var body: some View {
        HStack(spacing: 8) {
            // Use proper favicon view
            FaviconView(tab: tab, size: 16)
            
            Text(tab.title.isEmpty ? "New Tab" : tab.title)
                .font(.system(size: 13))
                .lineLimit(1)
                .foregroundColor(.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.thickMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.gray.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        .scaleEffect(0.95)
    }
}
