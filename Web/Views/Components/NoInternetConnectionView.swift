import SwiftUI
import AppKit

/// NoInternetConnectionView provides a beautiful glass morphism interface
/// when network connectivity is unavailable. Features retry functionality,
/// troubleshooting tips, and seamless integration with the browser's design system.
struct NoInternetConnectionView: View {
    @StateObject private var networkMonitor = NetworkConnectivityMonitor.shared
    @State private var isRetrying = false
    @State private var showTroubleshooting = false
    @State private var animateWifiIcon = false
    @State private var particleOffset: [CGFloat] = Array(repeating: 0, count: 6)
    @State private var particleOpacity: [Double] = Array(repeating: 0.3, count: 6)
    
    let onRetry: () -> Void
    let onGoBack: (() -> Void)?
    
    init(onRetry: @escaping () -> Void, onGoBack: (() -> Void)? = nil) {
        self.onRetry = onRetry
        self.onGoBack = onGoBack
    }
    
    var body: some View {
        ZStack {
            // Animated background with floating particles
            backgroundWithParticles
            
            // Main content
            VStack(spacing: 40) {
                Spacer()
                
                // Animated WiFi icon with status indicator
                connectionStatusIcon
                
                // Title and message
                VStack(spacing: 16) {
                    Text("No Internet Connection")
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                    
                    Text(getStatusMessage())
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 40)
                }
                
                // Action buttons
                VStack(spacing: 16) {
                    // Retry button
                    Button(action: handleRetry) {
                        HStack(spacing: 8) {
                            if isRetrying {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            
                            Text(isRetrying ? "Checking Connection..." : "Try Again")
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(networkMonitor.hasInternetConnection ? 
                                      Color.accentColor : Color.gray)
                                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                        )
                    }
                    .disabled(isRetrying)
                    .buttonStyle(PlainButtonStyle())
                    .scaleEffect(isRetrying ? 0.95 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: isRetrying)
                    
                    // Go back button (if provided)
                    if let goBack = onGoBack {
                        Button(action: goBack) {
                            Text("Go Back")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                
                // Troubleshooting section
                VStack(spacing: 12) {
                    Button(action: { 
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showTroubleshooting.toggle()
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 14))
                            Text("Troubleshooting Tips")
                                .font(.system(size: 14, weight: .medium))
                            Image(systemName: showTroubleshooting ? "chevron.up" : "chevron.down")
                                .font(.system(size: 12))
                                .rotationEffect(.degrees(showTroubleshooting ? 180 : 0))
                        }
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    if showTroubleshooting {
                        troubleshootingTips
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                
                Spacer()
                
                // Connection status footer
                connectionStatusFooter
            }
            .padding(.horizontal, 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            NoInternetVisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
        .onAppear {
            startAnimations()
        }
        .onChange(of: networkMonitor.isConnected) {
            updateAnimations()
        }
    }
    
    // MARK: - Background with Particles
    
    private var backgroundWithParticles: some View {
        ZStack {
            // Subtle gradient background
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.05),
                    Color.purple.opacity(0.03),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Floating particles
            ForEach(0..<6, id: \.self) { index in
                Circle()
                    .fill(Color.accentColor.opacity(particleOpacity[index]))
                    .frame(width: 4, height: 4)
                    .offset(
                        x: particleOffset[index],
                        y: particleOffset[index] * 0.7
                    )
                    .position(
                        x: CGFloat.random(in: 50...350),
                        y: CGFloat.random(in: 100...400)
                    )
                    .animation(
                        .easeInOut(duration: Double.random(in: 3...5))
                        .repeatForever(autoreverses: true),
                        value: particleOffset[index]
                    )
            }
        }
    }
    
    // MARK: - Connection Status Icon
    
    private var connectionStatusIcon: some View {
        ZStack {
            // Background circle with glass effect
            Circle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 120, height: 120)
                .background(
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
            
            // WiFi icon with animation
            Image(systemName: networkMonitor.isConnected ? "wifi" : "wifi.slash")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(networkMonitor.isConnected ? .green : .red)
                .scaleEffect(animateWifiIcon ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), 
                          value: animateWifiIcon)
        }
    }
    
    // MARK: - Troubleshooting Tips
    
    private var troubleshootingTips: some View {
        VStack(alignment: .leading, spacing: 12) {
            troubleshootingTip(
                icon: "wifi",
                title: "Check WiFi Connection",
                subtitle: "Make sure you're connected to a working network"
            )
            
            troubleshootingTip(
                icon: "antenna.radiowaves.left.and.right",
                title: "Check Signal Strength",
                subtitle: "Move closer to your router or try a different network"
            )
            
            troubleshootingTip(
                icon: "network",
                title: "Restart Network",
                subtitle: "Turn WiFi off and on, or restart your router"
            )
            
            troubleshootingTip(
                icon: "gear",
                title: "Check Network Settings",
                subtitle: "Open System Settings > Network to troubleshoot"
            )
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.05))
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    private func troubleshootingTip(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.accentColor)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Connection Status Footer
    
    private var connectionStatusFooter: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(networkMonitor.isConnected ? .green : .red)
                .frame(width: 8, height: 8)
                .animation(.easeInOut(duration: 0.3), value: networkMonitor.isConnected)
            
            Text(getFooterStatus())
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.bottom, 20)
    }
    
    // MARK: - Helper Methods
    
    private func getStatusMessage() -> String {
        if networkMonitor.isConnected {
            return "Connection restored! You can try loading the page again."
        } else {
            switch networkMonitor.connectionType {
            case .wifi:
                return "Your WiFi connection appears to be disconnected. Please check your network settings."
            case .ethernet:
                return "Your ethernet connection appears to be disconnected. Please check your cable and network settings."
            case .cellular:
                return "Your cellular connection appears to be unavailable. Please check your data plan and signal strength."
            case .unknown:
                return "Cannot detect an internet connection. Please check your network settings and try again."
            }
        }
    }
    
    private func getFooterStatus() -> String {
        if networkMonitor.isConnected {
            return "Connected via \(networkMonitor.connectionType.rawValue)"
        } else {
            return "No internet connection"
        }
    }
    
    private func handleRetry() {
        guard !isRetrying else { return }
        
        isRetrying = true
        
        // Animate retry button
        withAnimation(.easeInOut(duration: 0.2)) {
            // Visual feedback
        }
        
        // Delay to show checking state, then call retry
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            onRetry()
            isRetrying = false
        }
    }
    
    private func startAnimations() {
        animateWifiIcon = true
        
        // Start particle animations
        for i in 0..<particleOffset.count {
            particleOffset[i] = CGFloat.random(in: -30...30)
            particleOpacity[i] = Double.random(in: 0.1...0.5)
        }
    }
    
    private func updateAnimations() {
        // Update animations based on connection status
        withAnimation(.easeInOut(duration: 0.5)) {
            // Icon and particle updates handled by state changes
        }
    }
}

// MARK: - Visual Effect View for Glass Morphism

struct NoInternetVisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Preview

#Preview {
    NoInternetConnectionView(
        onRetry: { print("Retry tapped") },
        onGoBack: { print("Go back tapped") }
    )
    .frame(width: 800, height: 600)
}