import SwiftUI

struct ContentView: View {
    @State private var isEdgeToEdgeMode: Bool = false
    @State private var showWindowControls: Bool = false
    
    var body: some View {
        ZStack {
            // Subtle window background with blur and border
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.2),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
                .shadow(
                    color: .black.opacity(0.15),
                    radius: 20,
                    x: 0,
                    y: 8
                )
                .padding(8) // Subtle padding from window edges
            
            // Browser content inside the styled window
            BrowserView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
                .padding(16) // Inner padding for content
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Custom window controls in top-left corner
            VStack {
                HStack {
                    CustomWindowControls(isVisible: $showWindowControls)
                    Spacer()
                }
                Spacer()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleEdgeToEdge)) { _ in
            isEdgeToEdgeMode.toggle()
        }
    }
}

// Custom window controls that appear on hover
struct CustomWindowControls: View {
    @Binding var isVisible: Bool
    @State private var isHovered: Bool = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Close button
            WindowControlButton(
                color: .red,
                action: { NSApplication.shared.keyWindow?.performClose(nil) }
            )
            
            // Minimize button
            WindowControlButton(
                color: .yellow,
                action: { NSApplication.shared.keyWindow?.performMiniaturize(nil) }
            )
            
            // Zoom button
            WindowControlButton(
                color: .green,
                action: { NSApplication.shared.keyWindow?.performZoom(nil) }
            )
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                )
        )
        .opacity(isVisible || isHovered ? 1.0 : 0.0)
        .scaleEffect(isVisible || isHovered ? 1.0 : 0.8)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isVisible)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
            isVisible = hovering
        }
        .padding(.top, 8)
        .padding(.leading, 8)
    }
}

// Individual window control button
struct WindowControlButton: View {
    let color: Color
    let action: () -> Void
    @State private var isPressed: Bool = false
    
    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .strokeBorder(Color.black.opacity(0.2), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.9 : 1.0)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = hovering
            }
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 1200, height: 800)
}
