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

// Custom window controls that appear on hover with mini icon animation
struct CustomWindowControls: View {
    @Binding var isVisible: Bool
    @State private var isHovered: Bool = false
    @State private var showFullControls: Bool = false
    @AppStorage("tabDisplayMode") private var displayMode: TabDisplayMode = .sidebar
    
    var body: some View {
        ZStack {
            // Mini indicator (always visible)
            miniIndicator
                .opacity(showFullControls ? 0 : 1)
                .scaleEffect(showFullControls ? 0.1 : 1.0)
            
            // Full window controls (appear on hover)
            fullWindowControls
                .opacity(showFullControls ? 1 : 0)
                .scaleEffect(showFullControls ? 1.0 : 0.1)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showFullControls)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                showFullControls = hovering
                isHovered = hovering
                isVisible = hovering
            }
        }
        .padding(.top, displayMode == .topBar ? 16 : 8)
        .padding(.leading, displayMode == .sidebar ? 70 : 8) // Account for sidebar width
    }
    
    private var miniIndicator: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.3),
                        Color.white.opacity(0.1)
                    ],
                    center: .center,
                    startRadius: 2,
                    endRadius: 8
                )
            )
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 0.5)
    }
    
    private var fullWindowControls: some View {
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
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
    }
}

// Individual window control button with enhanced styling
struct WindowControlButton: View {
    let color: Color
    let action: () -> Void
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: action) {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            color.opacity(0.9),
                            color.opacity(0.7)
                        ],
                        center: .topLeading,
                        startRadius: 2,
                        endRadius: 8
                    )
                )
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.3),
                                    Color.black.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
                .shadow(
                    color: .black.opacity(0.15),
                    radius: isHovered ? 2 : 1,
                    x: 0,
                    y: isHovered ? 1 : 0.5
                )
                .scaleEffect(isHovered ? 1.1 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 1200, height: 800)
}
