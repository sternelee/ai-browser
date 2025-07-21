import SwiftUI

struct ContentView: View {
    @State private var isEdgeToEdgeMode: Bool = false
    
    var body: some View {
        // Browser content with padding from transparent parent window
        BrowserView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
            .padding(8) // Padding from screen edges via transparent parent window
            .onReceive(NotificationCenter.default.publisher(for: .toggleEdgeToEdge)) { _ in
                isEdgeToEdgeMode.toggle()
            }
    }
}

#Preview {
    ContentView()
        .frame(width: 1200, height: 800)
}
