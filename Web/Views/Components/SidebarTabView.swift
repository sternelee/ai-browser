import SwiftUI

struct SidebarTabView: View {
    @ObservedObject var tabManager: TabManager
    @State private var draggedTab: Web.Tab?
    @State private var hoveredTab: Web.Tab?
    
    var body: some View {
        VStack(spacing: 0) {
            // Top spacing
            Rectangle()
                .fill(Color.clear)
                .frame(height: 12)
            
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
                    
                    // Plus button positioned after tabs (where next tab would be)
                    newTabButton
                        .padding(.top, 2)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
            }
            
            Spacer()
            
            // Bottom section with settings only
            VStack(spacing: 8) {
                CavedDivider()
                    .padding(.horizontal, 12)
                
                settingsButton
                    .padding(.bottom, 12)
            }
        }
        .frame(width: 60)
        .background(
            // Beautiful seamless glass background
            ZStack {
                // Primary glass material
                RoundedRectangle(cornerRadius: 0)
                    .fill(.regularMaterial)
                
                // Soft glass overlay with gradient
                RoundedRectangle(cornerRadius: 0)
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
                
                // Subtle inner border
                HStack {
                    Spacer()
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
        RoundedRectangle(cornerRadius: 10)
            .fill(backgroundMaterial)
            .overlay(
                // Soft glass border
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                borderColor.opacity(0.6),
                                borderColor.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isActive ? 1 : 0.5
                    )
            )
            .shadow(
                color: isActive ? .black.opacity(0.1) : .clear,
                radius: isActive ? 8 : 2,
                x: 0,
                y: isActive ? 2 : 1
            )
            .overlay(
                // Subtle color accent from favicon with better blending
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        RadialGradient(
                            colors: [
                                extractedColor.opacity(isActive ? 0.15 : 0.05),
                                extractedColor.opacity(0.02),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 25
                        )
                    )
                    .animation(.easeInOut(duration: 0.3), value: extractedColor)
            )
    }
    
    private var backgroundMaterial: Material {
        if isActive {
            return .regularMaterial
        } else if isHovered {
            return .thinMaterial
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

