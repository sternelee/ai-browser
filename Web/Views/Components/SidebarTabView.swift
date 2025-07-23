import SwiftUI

struct SidebarTabView: View {
    @ObservedObject var tabManager: TabManager
    @State private var draggedTab: Web.Tab?
    @State private var hoveredTab: Web.Tab?
    
    var body: some View {
        VStack(spacing: 0) {
            // Window controls as first element in square format
            CompactWindowControls()
                .padding(.top, 8)
            
            // Small divider
            CavedDivider()
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            
            // Tab list with custom scrolling
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(tabManager.tabs) { tab in
                        SidebarTabItem(
                            tab: tab,
                            isActive: tab.id == tabManager.activeTab?.id,
                            isHovered: hoveredTab?.id == tab.id,
                            tabManager: tabManager
                        ) {
                            tabManager.setActiveTab(tab)
                        }
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                hoveredTab = hovering ? tab : nil
                            }
                        }
                        .contextMenu {
                            TabContextMenu(tab: tab, tabManager: tabManager)
                        }
                        .draggable(tab) {
                            FaviconView(tab: tab, size: 24)
                                .opacity(0.8)
                        }
                    }
                    
                    // Plus button positioned after tabs (where next tab would be)
                    newTabButton
                        .padding(.top, 2)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
            }
            
            Spacer()
                .background(WindowDragArea())  // Make empty sidebar area draggable
            
            // Bottom section with settings only
            VStack(spacing: 8) {
                CavedDivider()
                    .padding(.horizontal, 12)
                
                settingsButton
                    .padding(.bottom, 12)
            }
        }
        .frame(width: 50)
        .dropDestination(for: Web.Tab.self) { tabs, location in
            handleTabDrop(tabs: tabs, location: location)
            return true
        }
    }
    
    private var newTabButton: some View {
        Button(action: { 
            _ = tabManager.createNewTab() 
        }) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(newTabHovering ? Color.primary : Color.secondary)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color.secondary.opacity(newTabHovering ? 0.1 : 0.0))
                        .scaleEffect(newTabHovering ? 1.0 : 0.8)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(newTabHovering ? 1.0 : 0.9)
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                newTabHovering = hovering
            }
        }
    }
    
    @State private var newTabHovering: Bool = false
    
    private var settingsButton: some View {
        Button(action: { 
            KeyboardShortcutHandler.shared.showSettingsPanel.toggle()
        }) {
            Image(systemName: "gearshape")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(settingsHovering ? Color.primary : Color.secondary)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color.secondary.opacity(settingsHovering ? 0.1 : 0.0))
                        .scaleEffect(settingsHovering ? 1.0 : 0.8)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(settingsHovering ? 1.0 : 0.9)
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                settingsHovering = hovering
            }
        }
    }
    
    @State private var settingsHovering: Bool = false
    
    private func handleTabDrop(tabs: [Web.Tab], location: CGPoint) {
        guard let droppedTab = tabs.first,
              let fromIndex = tabManager.tabs.firstIndex(where: { $0.id == droppedTab.id }) else { return }
        
        // Calculate drop position with refined spacing
        let tabHeight: CGFloat = 44
        let dropIndex = min(max(0, Int(location.y / tabHeight)), tabManager.tabs.count - 1)
        
        if fromIndex != dropIndex {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                tabManager.tabs.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: dropIndex)
            }
        }
    }
}

struct SidebarTabItem: View {
    let tab: Web.Tab
    let isActive: Bool
    let isHovered: Bool
    let tabManager: TabManager
    let onTap: () -> Void
    
    @State private var showCloseButton: Bool = false
    @State private var extractedColor: Color = .clear
    
    var body: some View {
        Button(action: onTap) {
            tabItemContent
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                showCloseButton = hovering
            }
        }
        .scaleEffect(isActive ? 1.02 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isActive)
        .onReceive(tab.$favicon) { favicon in
            extractFaviconColor(from: favicon)
        }
        .onReceive(tab.$url) { _ in
            // Trigger UI update when URL changes to ensure favicon gets updated
        }
    }
    
    private var tabItemContent: some View {
        ZStack {
            backgroundView
            
            ZStack {
                // Favicon perfectly centered in full width
                faviconView
                    .frame(width: 24, height: 24)
                
                // Incognito indicator (small icon in bottom-right of favicon)
                if tab.isIncognito {
                    HStack {
                        Spacer()
                        VStack {
                            Spacer()
                            incognitoIndicator
                        }
                    }
                    .padding(.bottom, 8)
                    .padding(.trailing, 8)
                }
                
                // Close button positioned absolutely in top-right area
                if showCloseButton && isHovered {
                    HStack {
                        Spacer()
                        VStack {
                            closeButton
                                .transition(.scale.combined(with: .opacity))
                            Spacer()
                        }
                    }
                    .padding(.top, 2)
                    .padding(.trailing, 2)
                }
            }
            .frame(width: 48, height: 44)
        }
    }
    
    private var backgroundView: some View {
        Group {
            if isActive {
                RoundedRectangle(cornerRadius: 10)
                    .fill(backgroundMaterial)
                    .overlay(
                        // Soft glass border only for active tabs
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        borderColor.opacity(0.8),
                                        borderColor.opacity(0.4)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
            } else {
                // No background for non-active tabs
                Color.clear
            }
        }
            .shadow(
                color: isActive ? extractedColor.opacity(0.3) : .clear,
                radius: isActive ? 12 : 0,
                x: 0,
                y: isActive ? 3 : 0
            )
            .overlay(
                // Subtle color accent from favicon with better blending - only for active tabs
                Group {
                    if isActive {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                RadialGradient(
                                    colors: [
                                        extractedColor.opacity(0.25),
                                        extractedColor.opacity(0.15),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 8,
                                    endRadius: 20
                                )
                            )
                            .animation(.easeInOut(duration: 0.3), value: extractedColor)
                    }
                }
            )
    }
    
    private var backgroundMaterial: Material {
        if isActive {
            return .thickMaterial
        } else if isHovered {
            return .ultraThinMaterial
        } else {
            return .ultraThinMaterial
        }
    }
    
    private var borderColor: Color {
        if isActive {
            return extractedColor != .clear ? extractedColor : .blue
        }
        return .clear
    }
    
    private var faviconView: some View {
        Group {
            if tab.isLoading {
                // Refined loading indicator
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(Color.secondary)
            } else {
                FaviconView(tab: tab, size: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }
    
    private var incognitoIndicator: some View {
        Circle()
            .fill(.purple.opacity(0.8))
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
            )
            .shadow(color: .purple.opacity(0.3), radius: 2, x: 0, y: 1)
    }
    
    private var closeButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
                tabManager.closeTab(tab)
            }
        }) {
            ZStack {
                // Liquidy, bigger background with blur effect
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.red.opacity(0.8),
                                Color.red.opacity(0.6),
                                Color.red.opacity(0.3)
                            ],
                            center: .topLeading,
                            startRadius: 1,
                            endRadius: 10
                        )
                    )
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .blendMode(.overlay)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.4),
                                        Color.white.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.5
                            )
                    )
                
                // X mark
                Image(systemName: "xmark")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.1 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
    }
    
    private func extractFaviconColor(from image: NSImage?) {
        guard let image = image,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            extractedColor = .clear
            return
        }
        
        // Simplified color extraction for performance
        Task {
            let color = await extractDominantColor(from: cgImage)
            await MainActor.run {
                extractedColor = color
            }
        }
    }
    
    private func extractDominantColor(from cgImage: CGImage) async -> Color {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .background).async {
                // Simple average color extraction
                let width = min(cgImage.width, 16) // Limit size for performance
                let height = min(cgImage.height, 16)
                
                guard let context = CGContext(
                    data: nil,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else {
                    continuation.resume(returning: .clear)
                    return
                }
                
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
                
                guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else {
                    continuation.resume(returning: .clear)
                    return
                }
                
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
                var pixelCount: Int = 0
                
                for y in 0..<height {
                    for x in 0..<width {
                        let offset = (y * width + x) * 4
                        let alpha = CGFloat(data[offset + 3]) / 255.0
                        
                        if alpha > 0.5 { // Only consider opaque pixels
                            r += CGFloat(data[offset]) / 255.0
                            g += CGFloat(data[offset + 1]) / 255.0
                            b += CGFloat(data[offset + 2]) / 255.0
                            pixelCount += 1
                        }
                    }
                }
                
                if pixelCount > 0 {
                    r /= CGFloat(pixelCount)
                    g /= CGFloat(pixelCount)
                    b /= CGFloat(pixelCount)
                    continuation.resume(returning: Color(red: r, green: g, blue: b))
                } else {
                    continuation.resume(returning: .clear)
                }
            }
        }
    }
}

