import SwiftUI

struct NavigationControls: View {
    @ObservedObject var tab: Tab
    @State private var showHistory: Bool = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Back button with long press for history
            Button(action: { tab.goBack() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(tab.canGoBack ? .primary : .secondary)
            }
            .disabled(!tab.canGoBack)
            .buttonStyle(GlassButtonStyle())
            .onLongPressGesture {
                showHistory = true
            }
            .popover(isPresented: $showHistory) {
                BackHistoryView(tab: tab)
            }
            
            // Forward button
            Button(action: { tab.goForward() }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(tab.canGoForward ? .primary : .secondary)
            }
            .disabled(!tab.canGoForward)
            .buttonStyle(GlassButtonStyle())
            
            // Reload/Stop button with smooth transition
            Button(action: { 
                if tab.isLoading {
                    tab.stopLoading()
                } else {
                    tab.reload()
                }
            }) {
                Image(systemName: tab.isLoading ? "xmark" : "arrow.clockwise")
                    .font(.system(size: 14, weight: .medium))
                    .rotationEffect(.degrees(tab.isLoading ? 0 : 360))
                    .animation(.easeInOut(duration: 0.3), value: tab.isLoading)
            }
            .buttonStyle(GlassButtonStyle())
        }
    }
}

// Glass button style for navigation
struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.ultraThinMaterial)
                    .opacity(configuration.isPressed ? 0.8 : 1.0)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// Placeholder for back history view
struct BackHistoryView: View {
    @ObservedObject var tab: Tab
    
    var body: some View {
        VStack {
            Text("Back History")
                .font(.headline)
                .padding()
            
            Text("History functionality will be implemented in future phases")
                .foregroundColor(.secondary)
                .padding()
        }
        .frame(width: 200, height: 100)
    }
}

#Preview {
    NavigationControls(tab: Tab())
}