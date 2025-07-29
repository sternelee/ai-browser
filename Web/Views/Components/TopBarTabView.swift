import SwiftUI

struct TopBarTabView: View {
    @ObservedObject var tabManager: TabManager
    @State private var draggedTab: Web.Tab?
    @State private var hoveredTabId: UUID?
    @State private var dropTargetIndex: Int?
    @State private var isDragging: Bool = false
    @State private var isValidDropTarget: Bool = true
    @State private var dragStartPosition: CGPoint = .zero
    
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
        } isTargeted: { isTargeted in
            withAnimation(.easeInOut(duration: 0.2)) {
                if !isTargeted {
                    dropTargetIndex = nil
                    isDragging = false
                }
            }
        }
    }
    
    private var tabScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(tabManager.tabs.enumerated()), id: \.element.id) { index, tab in
                    TopBarTabItem(
                        tab: tab,
                        isActive: tab.id == tabManager.activeTab?.id,
                        isHovered: hoveredTabId == tab.id,
                        isDragging: isDragging && draggedTab?.id == tab.id,
                        onTap: { tabManager.setActiveTab(tab) },
                        tabManager: tabManager
                    )
                    .frame(minWidth: 140, idealWidth: 180, maxWidth: 220)
                    .scaleEffect(isDragging && draggedTab?.id == tab.id ? 1.02 : 1.0)
                    .opacity(isDragging && draggedTab?.id == tab.id ? 0.95 : 1.0)
                    .zIndex(isDragging && draggedTab?.id == tab.id ? 1000 : 0)
                    .overlay(
                        // Drop zone indicator - left edge
                        Rectangle()
                            .fill(isValidDropTarget ? Color.accentColor : Color.red)
                            .frame(width: 2, height: 28)
                            .opacity(dropTargetIndex == index && isDragging ? 0.8 : 0.0)
                            .offset(x: -71)
                            .animation(.easeInOut(duration: 0.2), value: dropTargetIndex)
                            .animation(.easeInOut(duration: 0.2), value: isValidDropTarget)
                    )
                    .overlay(
                        // Drop zone indicator - right edge (for last position)
                        Rectangle()
                            .fill(isValidDropTarget ? Color.accentColor : Color.red)
                            .frame(width: 2, height: 28)
                            .opacity(dropTargetIndex == index + 1 && isDragging ? 0.8 : 0.0)
                            .offset(x: 71)
                            .animation(.easeInOut(duration: 0.2), value: dropTargetIndex)
                            .animation(.easeInOut(duration: 0.2), value: isValidDropTarget)
                    )
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            hoveredTabId = hovering ? tab.id : nil
                        }
                    }
                    .draggable(tab) {
                        TopBarTabPreview(tab: tab, isDragging: true)
                    }
                    .onDrag {
                        isDragging = true
                        draggedTab = tab
                        return NSItemProvider()
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
        
        // Enhanced drop calculation with edge detection
        let tabWidth: CGFloat = 180
        let padding: CGFloat = 12
        let adjustedX = max(0, location.x - padding)
        
        // Calculate which tab position this corresponds to
        let tabIndex = Int(adjustedX / tabWidth)
        let positionInTab = adjustedX.truncatingRemainder(dividingBy: tabWidth)
        
        // Determine if we're closer to the left or right edge of the tab
        let dropIndex: Int
        if positionInTab < tabWidth / 2 {
            // Closer to left edge - insert before this tab
            dropIndex = min(tabIndex, tabManager.tabs.count)
        } else {
            // Closer to right edge - insert after this tab
            dropIndex = min(tabIndex + 1, tabManager.tabs.count)
        }
        
        // Validate drop target
        let isValidDrop = dropIndex != fromIndex && 
                         dropIndex >= 0 && dropIndex <= tabManager.tabs.count
        
        // Update visual feedback
        withAnimation(.easeInOut(duration: 0.15)) {
            dropTargetIndex = dropIndex
            isValidDropTarget = isValidDrop
        }
        
        // Perform the move using enhanced TabManager method (only if valid)
        var success = false
        if isValidDrop {
            success = tabManager.moveTabSafely(fromIndex: fromIndex, toIndex: dropIndex)
        }
        
        // Provide visual feedback for invalid drops
        if !success && !isValidDrop {
            // Shake animation for invalid drop
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                // Invalid drop feedback could be added here
            }
            
            // Haptic feedback for invalid drop
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
        
        // Clean up drag state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.2)) {
                dropTargetIndex = nil
                isDragging = false
                draggedTab = nil
                isValidDropTarget = true
            }
        }
    }
}

struct TopBarTabItem: View {
    let tab: Web.Tab
    let isActive: Bool
    let isHovered: Bool
    let isDragging: Bool
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
                        color: isActive ? .black.opacity(0.1) : (isDragging ? .black.opacity(0.15) : .clear),
                        radius: isActive ? 4 : (isDragging ? 8 : 0),
                        x: 0,
                        y: isDragging ? 4 : (isActive ? 1 : 0)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            showCloseButton = hovering
        }
    }
}

// Enhanced tab preview for drag operations
struct TopBarTabPreview: View {
    let tab: Web.Tab
    let isDragging: Bool
    
    init(tab: Web.Tab, isDragging: Bool = false) {
        self.tab = tab
        self.isDragging = isDragging
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Use proper favicon view
            FaviconView(tab: tab, size: 16)
            
            Text(tab.title.isEmpty ? "New Tab" : tab.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .foregroundColor(.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.thickMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
        )
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
        .shadow(color: .blue.opacity(0.1), radius: 4, x: 0, y: 2)
        .scaleEffect(isDragging ? 1.02 : 0.98)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
    }
}
