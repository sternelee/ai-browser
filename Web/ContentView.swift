import SwiftUI

struct ContentView: View {
    @State private var isEdgeToEdgeMode: Bool = false
    
    var body: some View {
        ZStack {
            // Seamless glass window background
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.2),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: .black.opacity(0.3),
                    radius: 30,
                    x: 0,
                    y: 10
                )
            
            // Main browser content with padding
            BrowserView()
                .padding(isEdgeToEdgeMode ? 8 : 12) // More generous padding for glass aesthetic
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isEdgeToEdgeMode)
        }
        .padding(4) // Outer padding for the glass effect
        .background(Color.clear) // Transparent background
        .onReceive(NotificationCenter.default.publisher(for: .toggleEdgeToEdge)) { _ in
            isEdgeToEdgeMode.toggle()
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 1200, height: 800)
}
