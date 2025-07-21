import SwiftUI

struct NavigationControls: View {
    @ObservedObject var tab: Tab
    @State private var showHistory: Bool = false
    @State private var isRotating: Bool = false
    
    var body: some View {
        HStack(spacing: 6) {
            // Back button with enhanced styling
            NavigationButton(
                icon: "chevron.left",
                isEnabled: tab.canGoBack,
                action: { tab.goBack() }
            )
            .onLongPressGesture {
                showHistory = true
            }
            .popover(isPresented: $showHistory) {
                BackHistoryView(tab: tab)
            }
            
            // Forward button
            NavigationButton(
                icon: "chevron.right",
                isEnabled: tab.canGoForward,
                action: { tab.goForward() }
            )
            
            // Reload/Stop button with enhanced animation
            NavigationButton(
                icon: tab.isLoading ? "xmark" : "arrow.clockwise",
                isEnabled: true,
                isLoading: tab.isLoading,
                action: { 
                    if tab.isLoading {
                        tab.stopLoading()
                    } else {
                        tab.reload()
                        triggerReloadAnimation()
                    }
                }
            )
        }
    }
    
    private func triggerReloadAnimation() {
        withAnimation(.easeInOut(duration: 0.5)) {
            isRotating = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isRotating = false
        }
    }
}

// Enhanced navigation button component
struct NavigationButton: View {
    let icon: String
    let isEnabled: Bool
    var isLoading: Bool = false
    let action: () -> Void
    
    @State private var hovering: Bool = false
    @State private var rotationAngle: Double = 0
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(foregroundColor)
                .frame(width: 20, height: 20)
                .rotationEffect(.degrees(isLoading && icon == "arrow.clockwise" ? rotationAngle : 0))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                self.hovering = hovering
            }
        }
        .onChange(of: isLoading) { _, loading in
            if loading && icon == "arrow.clockwise" {
                withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                    rotationAngle = 360
                }
            } else {
                withAnimation(.easeOut(duration: 0.3)) {
                    rotationAngle = 0
                }
            }
        }
    }
    
    private var foregroundColor: Color {
        if !isEnabled {
            return .textSecondary.opacity(0.4)
        } else if hovering {
            return .textPrimary
        } else {
            return .textSecondary
        }
    }
}

// Enhanced glass button style for navigation
struct NavigationButtonStyle: ButtonStyle {
    let isEnabled: Bool
    let isHovered: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
    
    private func buttonBackground(isPressed: Bool) -> some View {
        Color.clear // No background - just the icon
    }
}

// Enhanced back history view
struct BackHistoryView: View {
    @ObservedObject var tab: Tab
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Back History")
                .font(.webH2)
                .foregroundColor(.textPrimary)
            
            Text("History functionality will be implemented in future phases")
                .font(.webBody)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(width: 250, height: 120)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.thickMaterial)
                
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.bgSurface)
                
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.borderGlass, lineWidth: 1)
            }
        )
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
}

#Preview {
    NavigationControls(tab: Tab())
}