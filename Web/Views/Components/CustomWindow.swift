import SwiftUI
import AppKit

// Custom window wrapper that handles window controls visibility
struct CustomWindowControlsOverlay: View {
    @State private var isHoveringTitleArea: Bool = false
    @State private var windowControlsOpacity: Double = 0.0
    
    var body: some View {
        VStack {
            // Top area with window controls
            HStack {
                // Window controls (only shown on hover)
                HStack(spacing: 8) {
                    windowButton(.closeButton, color: .red)
                    windowButton(.miniaturizeButton, color: .yellow)
                    windowButton(.zoomButton, color: .green)
                }
                .opacity(windowControlsOpacity)
                .animation(.easeInOut(duration: 0.2), value: windowControlsOpacity)
                .padding(.leading, 16)
                .padding(.top, 12)
                
                Spacer()
            }
            
            Spacer()
        }
        .background(
            // Invisible hover area for title bar region
            HStack {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 200, height: 40) // Hover zone for window controls
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            windowControlsOpacity = hovering ? 1.0 : 0.0
                        }
                    }
                
                Spacer()
            }
        )
    }
    
    private func windowButton(_ type: NSWindow.ButtonType, color: Color) -> some View {
        Button(action: {
            performWindowAction(type)
        }) {
            Circle()
                .fill(color)
                .frame(width: 13, height: 13)
                .overlay(
                    Circle()
                        .strokeBorder(Color.black.opacity(0.1), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHoveringTitleArea ? 1.0 : 0.9)
    }
    
    private func performWindowAction(_ type: NSWindow.ButtonType) {
        guard let window = NSApplication.shared.keyWindow else { return }
        
        switch type {
        case .closeButton:
            window.performClose(nil)
        case .miniaturizeButton:
            window.performMiniaturize(nil)
        case .zoomButton:
            window.performZoom(nil)
        default:
            break
        }
    }
}

// Usage in ContentView for next-gen window controls
struct NextGenWindowView: View {
    @State private var isEdgeToEdgeMode: Bool = false
    
    var body: some View {
        ZStack {
            // Main browser content
            BrowserView()
                .padding(isEdgeToEdgeMode ? 4 : 0)
                .background(Color.bgBase)
                .clipShape(RoundedRectangle(cornerRadius: isEdgeToEdgeMode ? 8 : 0))
            
            // Custom window controls overlay (only when not in edge-to-edge)
            if !isEdgeToEdgeMode {
                CustomWindowControlsOverlay()
            }
        }
        .background(Color.bgBase)
        .onReceive(NotificationCenter.default.publisher(for: .toggleEdgeToEdge)) { _ in
            isEdgeToEdgeMode.toggle()
        }
    }
}