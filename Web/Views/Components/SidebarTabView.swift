import SwiftUI

struct SidebarTabView: View {
    @ObservedObject var tabManager: TabManager
    @State private var draggedTab: Web.Tab?
    @State private var hoveredTab: Web.Tab?
    
    var body: some View {
        VStack(spacing: 0) {
            // Top section with new tab button
            VStack(spacing: 8) {
                newTabButton
                    .padding(.top, 12)
                
                if !tabManager.tabs.isEmpty {
                    CavedDivider()
                        .padding(.horizontal, 12)
                }
            }
            
            // Tab list with custom scrolling
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
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
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
            }
            
            Spacer()
            
            // Bottom section with settings
            VStack(spacing: 8) {
                CavedDivider()
                    .padding(.horizontal, 12)
                
                settingsButton
                    .padding(.bottom, 12)
            }
        }
        .frame(width: 60)
        .background(
            // Enhanced glass background with subtle tint
            ZStack {
                // Base material
                Rectangle()
                    .fill(.ultraThinMaterial)
                
                // Dark glass surface overlay
                Rectangle()
                    .fill(Color.black.opacity(0.05))
                
                // Subtle border on right edge
                HStack {
                    Spacer()
                    Rectangle()
                        .fill(.gray.opacity(0.3))
                        .frame(width: 1)
                }
            }
        )
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
                .foregroundColor(Color.secondary)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(0.9) // Slightly smaller for minimal aesthetic
    }
    
    private var settingsButton: some View {
        Button(action: { 
            // Open settings 
        }) {
            Image(systemName: "gearshape")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.secondary)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(0.9)
    }
    
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
    }
    
    private var tabItemContent: some View {
        ZStack {
            backgroundView
            
            VStack(spacing: 0) {
                Spacer()
                
                faviconView
                    .frame(width: 24, height: 24)
                
                Spacer()
                
                if showCloseButton && isHovered {
                    closeButton
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 48, height: 44)
        }
    }
    
    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(backgroundMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(borderColor, lineWidth: isActive ? 1.5 : 0)
            )
            .shadow(
                color: isActive ? .black.opacity(0.15) : .clear,
                radius: 3,
                x: 0,
                y: 1
            )
            .overlay(
                // Subtle color accent from favicon
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [
                                extractedColor.opacity(isActive ? 0.08 : 0.03),
                                extractedColor.opacity(0.01)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .animation(.easeInOut(duration: 0.3), value: extractedColor)
            )
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
    
    private var closeButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
                tabManager.closeTab(tab)
            }
        }) {
            Image(systemName: "xmark")
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(Color.secondary)
                .frame(width: 14, height: 14)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.05))
                        .overlay(
                            Circle()
                                .strokeBorder(.gray.opacity(0.3), lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(0.9)
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

