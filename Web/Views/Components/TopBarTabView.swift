import SwiftUI

struct TopBarTabView: View {
    @ObservedObject var tabManager: TabManager
    @State private var draggedTab: Web.Tab?
    @State private var hoveredTabId: UUID?
    
    var body: some View {
        HStack(spacing: 0) {
            tabScrollView
            controlsSection
        }
        .frame(height: 40)
        .background(topBarBackground)
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
            }
            .padding(.horizontal, 12)
        }
    }
    
    private var controlsSection: some View {
        HStack(spacing: 8) {
            newTabButton
            menuButton
        }
        .padding(.trailing, 12)
    }
    
    private var topBarBackground: some View {
        ZStack {
            // Base material
            Rectangle()
                .fill(.ultraThinMaterial)
            
            // Dark glass surface overlay
            Rectangle()
                .fill(Color.black.opacity(0.05))
            
            // Bottom border
            VStack {
                Spacer()
                Rectangle()
                    .fill(.gray.opacity(0.3))
                    .frame(height: 1)
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
    
    private var menuButton: some View {
        Button(action: showMenu) {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.secondary)
                .frame(width: 32, height: 28)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func showMenu() {
        // Show browser menu
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
                // Simple favicon
                if tab.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(.textSecondary)
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 14))
                        .foregroundColor(Color.secondary)
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
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? .thickMaterial : .ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(isActive ? .blue : Color.clear, lineWidth: 1)
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
            // Placeholder for favicon
            Image(systemName: "globe")
                .font(.system(size: 16))
                .foregroundColor(Color.secondary)
            
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
