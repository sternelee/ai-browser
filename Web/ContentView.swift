import SwiftUI

struct ContentView: View {
    @State private var isEdgeToEdgeMode: Bool = false
    
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
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleEdgeToEdge)) { _ in
            isEdgeToEdgeMode.toggle()
        }
    }
}


#Preview {
    ContentView()
        .frame(width: 1200, height: 800)
}
