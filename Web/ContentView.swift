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
        }
        .onTapGesture(count: 2) {
            toggleExpanded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleEdgeToEdge)) { _ in
            isEdgeToEdgeMode.toggle()
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isExpanded)
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


#Preview {
    ContentView()
        .frame(width: 1200, height: 800)
}
