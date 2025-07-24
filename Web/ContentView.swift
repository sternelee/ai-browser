import SwiftUI

struct ContentView: View {
    @State private var isEdgeToEdgeMode: Bool = false
    @State private var isExpanded: Bool = false
    @State private var previousWindowFrame: CGRect = .zero
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: isExpanded ? 0 : 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    Color.black.opacity(0.40)
                        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 0 : 12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: isExpanded ? 0 : 12)
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
                    color: .black.opacity(isExpanded ? 0 : 0.15),
                    radius: isExpanded ? 0 : 20,
                    x: 0,
                    y: isExpanded ? 0 : 8
                )
                .background(Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Browser content inside the styled window
            BrowserView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
                .padding(6)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            
            // Floating panels overlay
            PanelManager()
                .allowsHitTesting(true)
            
            // Strategic window drag areas overlay
            // These areas allow dragging from empty spaces while *not* blocking clicks on sidebar tabs
            // or custom window controls.
            WindowDragOverlay()
        }
        // CRITICAL FIX: Temporarily disable double-tap gesture to test input locking fix
        // This window-wide gesture may be consuming single taps preventing input focus
        // .onTapGesture(count: 2) {
        //     toggleExpanded()
        // }
        .onReceive(NotificationCenter.default.publisher(for: .toggleEdgeToEdge)) { _ in
            isEdgeToEdgeMode.toggle()
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isExpanded)
        // Allow the window chrome to cover the (now transparent) title-bar area
        .ignoresSafeArea(.container, edges: .top)
    }
    
    private func toggleExpanded() {
        guard let window = NSApplication.shared.keyWindow else { return }
        
        if isExpanded {
            // Return to previous size
            isExpanded = false
            if previousWindowFrame != .zero {
                window.setFrame(previousWindowFrame, display: true, animate: true)
            }
        } else {
            // Store current frame before expanding
            previousWindowFrame = window.frame
            // Expand to fill screen
            isExpanded = true
            if let screen = window.screen {
                let screenFrame = screen.visibleFrame
                window.setFrame(screenFrame, display: true, animate: true)
            }
        }
    }
}


/// Strategic window drag overlay that provides draggable areas without interfering with interactive content
struct WindowDragOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Corner drag areas - small triangular zones at corners for dragging
                VStack {
                    HStack {
                        // Top-left corner drag area (hit-test transparent to keep window controls clickable)
                        Triangle()
                            .fill(Color.clear)
                            .background(WindowDragArea(allowsHitTesting: false))
                            .frame(width: 40, height: 40)
                        
                        Spacer()
                        
                        // Top-right corner drag area
                        Triangle()
                            .fill(Color.clear)
                            .background(WindowDragArea())
                            .frame(width: 40, height: 40)
                            .rotationEffect(.degrees(90))
                    }
                    
                    Spacer()
                    
                    HStack {
                        // Bottom-left corner drag area
                        Triangle()
                            .fill(Color.clear)
                            .background(WindowDragArea())
                            .frame(width: 40, height: 40)
                            .rotationEffect(.degrees(-90))
                        
                        Spacer()
                        
                        // Bottom-right corner drag area  
                        Triangle()
                            .fill(Color.clear)
                            .background(WindowDragArea())
                            .frame(width: 40, height: 40)
                            .rotationEffect(.degrees(180))
                    }
                }
                
                // Edge drag strips - thin areas along edges for dragging
                VStack {
                    // Top edge drag strip (excluding corners)
                    HStack {
                        Spacer().frame(width: 60) // Avoid corner
                        Rectangle()
                            .fill(Color.clear)
                            .background(WindowDragArea())
                            .frame(height: 8)
                        Spacer().frame(width: 60) // Avoid corner
                    }
                    
                    Spacer()
                    
                    // Bottom edge drag strip (excluding corners)
                    HStack {
                        Spacer().frame(width: 60) // Avoid corner
                        Rectangle()
                            .fill(Color.clear)
                            .background(WindowDragArea())
                            .frame(height: 8)
                        Spacer().frame(width: 60) // Avoid corner
                    }
                }
                
                HStack {
                    // Left edge drag strip (excluding corners and tab areas)
                    VStack {
                        Spacer().frame(height: 100) // Avoid top corner and sidebar tabs
                        Rectangle()
                            .fill(Color.clear)
                            .background(WindowDragArea(allowsHitTesting: false))
                            .frame(width: 8)
                        Spacer().frame(height: 60) // Avoid bottom corner
                    }
                    
                    Spacer()
                    
                    // Right edge drag strip (excluding corners)
                    VStack {
                        Spacer().frame(height: 60) // Avoid top corner
                        Rectangle()
                            .fill(Color.clear)
                            .background(WindowDragArea())
                            .frame(width: 8)
                        Spacer().frame(height: 60) // Avoid bottom corner
                    }
                }
            }
        }
        .allowsHitTesting(true)
    }
}

/// Simple triangle shape for corner drag areas
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    ContentView()
        .frame(width: 1200, height: 800)
}
