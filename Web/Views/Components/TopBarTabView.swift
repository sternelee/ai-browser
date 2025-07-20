import SwiftUI

// Horizontal tab bar for top display mode
struct TopBarTabView: View {
    @ObservedObject var tabManager: TabManager
    @State private var draggedTab: Tab?
    
    var body: some View {
        HStack(spacing: 0) {
            tabScrollArea
            newTabButton
        }
        .frame(height: 40)
        .background(.ultraThinMaterial)
        .dropDestination(for: Tab.self) { tabs, location in
            handleTabDrop(tabs: tabs, location: location)
            return true
        }
    }
    
    private var tabScrollArea: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(tabManager.tabs) { tab in
                    tabItemView(for: tab)
                }
            }
            .padding(.horizontal, 8)
        }
    }
    
    private func tabItemView(for tab: Tab) -> some View {
        TopBarTabItem(
            tab: tab,
            isActive: tab.id == tabManager.activeTab?.id,
            onTap: {
                tabManager.setActiveTab(tab)
            },
            tabManager: tabManager
        )
        .frame(minWidth: 120, idealWidth: 180, maxWidth: 200)
        .contextMenu {
            TabContextMenu(tab: tab, tabManager: tabManager)
        }
        .draggable(tab) {
            TopBarTabPreview(tab: tab)
        }
    }
    
    private var newTabButton: some View {
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
    
    private func handleTabDrop(tabs: [Tab], location: CGPoint) {
        // Handle tab reordering logic for horizontal layout
        guard let droppedTab = tabs.first,
              let fromIndex = tabManager.tabs.firstIndex(where: { $0.id == droppedTab.id }) else { return }
        
        // Calculate drop position based on horizontal location
        let tabWidth: CGFloat = 180
        let dropIndex = min(max(0, Int(location.x / tabWidth)), tabManager.tabs.count - 1)
        
        if fromIndex != dropIndex {
            tabManager.tabs.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: dropIndex)
        }
    }
}

struct TopBarTabItem: View {
    let tab: Tab
    let isActive: Bool
    let onTap: () -> Void
    @ObservedObject var tabManager: TabManager
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: onTap) {
            tabContent
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
    
    private var tabContent: some View {
        HStack(spacing: 8) {
            faviconView
            titleView
            Spacer(minLength: 0)
            if isHovered {
                closeButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(tabBackground)
    }
    
    private var faviconView: some View {
        Group {
            if tab.isLoading {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
            } else {
                FaviconView(tab: tab, size: 16)
            }
        }
    }
    
    private var titleView: some View {
        Text(tab.title)
            .font(.system(.caption, weight: isActive ? .medium : .regular))
            .lineLimit(1)
            .foregroundColor(isActive ? .primary : .secondary)
    }
    
    private var closeButton: some View {
        Button(action: {
            tabManager.closeTab(tab)
        }) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .transition(.scale.combined(with: .opacity))
    }
    
    private var tabBackground: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(isActive ? Color.accentColor.opacity(0.2) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isActive ? .blue : .clear, lineWidth: 1)
            )
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

// Preview for dragging tabs
struct TopBarTabPreview: View {
    let tab: Tab
    
    var body: some View {
        HStack(spacing: 8) {
            FaviconView(tab: tab, size: 16)
            Text(tab.title)
                .font(.system(.caption, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: 120)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.2))
        )
        .opacity(0.8)
    }
}