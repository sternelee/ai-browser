import SwiftUI

// Compact window controls for integration into sidebar and top bar
struct CompactWindowControls: View {
    @State private var isHovered: Bool = false
    @State private var showFullControls: Bool = false
    
    private func getCurrentWindow() -> NSWindow? {
        return NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow ?? NSApplication.shared.windows.first
    }
    
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
        .frame(width: 48, height: 44) // Square format to fit in sidebar/topbar
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showFullControls)
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                showFullControls = hovering
                isHovered = hovering
            }
        }
    }
    
    private var miniIndicator: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.2),
                        Color.white.opacity(0.05)
                    ],
                    center: .center,
                    startRadius: 4,
                    endRadius: 12
                )
            )
            .frame(width: 24, height: 8)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
    }
    
    private var fullWindowControls: some View {
        HStack(spacing: 4) {
            // Close button
            CompactWindowControlButton(
                color: .red,
                action: { 
                    getCurrentWindow()?.performClose(nil)
                }
            )
            
            // Minimize button with different gradient
            CompactWindowControlButton(
                color: .orange,
                isMinimizeButton: true,
                action: { 
                    getCurrentWindow()?.performMiniaturize(nil)
                }
            )
            
            // Zoom button (bigger and more functional)
            CompactWindowControlButton(
                color: .green,
                isMaximizeButton: true,
                action: { 
                    getCurrentWindow()?.performZoom(nil)
                }
            )
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.25),
                                    Color.white.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
                .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1.5)
        )
    }
}

// Compact window control button for tight spaces
struct CompactWindowControlButton: View {
    let color: Color
    let isMinimizeButton: Bool
    let isMaximizeButton: Bool
    let action: () -> Void
    @State private var isHovered: Bool = false
    
    init(color: Color, isMinimizeButton: Bool = false, isMaximizeButton: Bool = false, action: @escaping () -> Void) {
        self.color = color
        self.isMinimizeButton = isMinimizeButton
        self.isMaximizeButton = isMaximizeButton
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            Circle()
                .fill(buttonGradient)
                .frame(width: buttonSize, height: buttonSize)
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.25),
                                    Color.black.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.3
                        )
                )
                .shadow(
                    color: .black.opacity(0.12),
                    radius: isHovered ? 1.5 : 1,
                    x: 0,
                    y: isHovered ? 0.8 : 0.5
                )
                .scaleEffect(isHovered ? 1.15 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.15, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
    }
    
    private var buttonGradient: RadialGradient {
        if isMinimizeButton {
            return RadialGradient(
                colors: [
                    Color.orange.opacity(0.9),
                    Color.yellow.opacity(0.7)
                ],
                center: .topLeading,
                startRadius: 1,
                endRadius: 4
            )
        } else {
            return RadialGradient(
                colors: [
                    color.opacity(0.85),
                    color.opacity(0.65)
                ],
                center: .topLeading,
                startRadius: 1,
                endRadius: 4
            )
        }
    }
    
    private var buttonSize: CGFloat {
        if isMaximizeButton {
            return 14 // Make maximize button much bigger
        } else if isMinimizeButton {
            return 12 // Make minimize button bigger too
        } else {
            return 12 // Make close button bigger
        }
    }
}

#Preview {
    CompactWindowControls()
        .padding()
        .background(.regularMaterial)
}