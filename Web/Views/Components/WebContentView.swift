import SwiftUI

// Web content view for displaying individual tabs
struct WebContentView: View {
    @ObservedObject var tab: Tab
    @Binding var urlString: String
    @State private var pulsingScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            if tab.isHibernated, let snapshot = tab.snapshot {
                // Show snapshot for hibernated tabs
                Image(nsImage: snapshot)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .overlay(
                        VStack {
                            Text("Tab Hibernated")
                                .font(.headline)
                            Text("Click to reload")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    )
                    .onTapGesture {
                        tab.wakeUp()
                    }
            } else {
                // Active web view
                if tab.url != nil {
                    WebView(
                        url: Binding(
                            get: { tab.url },
                            set: { tab.url = $0 }
                        ),
                        canGoBack: Binding(
                            get: { tab.canGoBack },
                            set: { tab.canGoBack = $0 }
                        ),
                        canGoForward: Binding(
                            get: { tab.canGoForward },
                            set: { tab.canGoForward = $0 }
                        ),
                        isLoading: Binding(
                            get: { tab.isLoading },
                            set: { tab.isLoading = $0 }
                        ),
                        estimatedProgress: Binding(
                            get: { tab.estimatedProgress },
                            set: { tab.estimatedProgress = $0 }
                        ),
                        title: Binding(
                            get: { tab.title },
                            set: { tab.title = $0 ?? "New Tab" }
                        ),
                        favicon: Binding(
                            get: { tab.favicon },
                            set: { tab.favicon = $0 }
                        ),
                        tab: tab,
                        onNavigationAction: nil,
                        onDownloadRequest: nil
                    )
                    .onChange(of: tab.url) { _, newURL in
                        if let url = newURL {
                            urlString = url.absoluteString
                        }
                    }
                } else {
                    NewTabView()
                }
            }
            
            // Enhanced loading progress bar with theme color integration
            if tab.isLoading {
                VStack {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background track
                            Rectangle()
                                .fill(Color.secondary.opacity(0.15))
                                .frame(height: 3)
                            
                            // Main progress fill with theme color
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            themeAwareProgressColor.opacity(0.9),
                                            themeAwareProgressColor,
                                            themeAwareProgressColor.opacity(0.8)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * progressPercent, height: 3)
                                .animation(.easeOut(duration: 0.2), value: tab.estimatedProgress)
                                .animation(.easeInOut(duration: 0.5), value: tab.themeColor)
                            
                            // Primary glow layer
                            Rectangle()
                                .fill(themeAwareProgressColor.opacity(0.5))
                                .frame(width: geometry.size.width * progressPercent, height: 3)
                                .blur(radius: 2)
                                .animation(.easeOut(duration: 0.2), value: tab.estimatedProgress)
                                .animation(.easeInOut(duration: 0.5), value: tab.themeColor)
                            
                            // Secondary glow layer (wider)
                            Rectangle()
                                .fill(themeAwareProgressColor.opacity(0.3))
                                .frame(width: geometry.size.width * progressPercent, height: 5)
                                .blur(radius: 4)
                                .animation(.easeOut(duration: 0.2), value: tab.estimatedProgress)
                                .animation(.easeInOut(duration: 0.5), value: tab.themeColor)
                            
                            // Outer glow layer (widest)
                            Rectangle()
                                .fill(themeAwareProgressColor.opacity(0.2))
                                .frame(width: geometry.size.width * progressPercent, height: 8)
                                .blur(radius: 6)
                                .animation(.easeOut(duration: 0.2), value: tab.estimatedProgress)
                                .animation(.easeInOut(duration: 0.5), value: tab.themeColor)
                            
                            // Pulsing core highlight
                            Rectangle()
                                .fill(themeAwareProgressColor.opacity(0.8))
                                .frame(width: geometry.size.width * progressPercent, height: 1)
                                .blur(radius: 0.5)
                                .scaleEffect(y: pulsingScale)
                                .animation(.easeOut(duration: 0.2), value: tab.estimatedProgress)
                                .animation(.easeInOut(duration: 0.5), value: tab.themeColor)
                        }
                        .clipShape(Capsule())
                    }
                    .frame(height: 3)
                    .transition(.opacity.combined(with: .scale(scale: 1.0, anchor: .leading)))
                    
                    Spacer()
                }
            }
        }
        .onReceive(tab.$isLoading) { isLoading in
            if isLoading {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulsingScale = 1.5
                }
            } else {
                withAnimation(.easeOut(duration: 0.3)) {
                    pulsingScale = 1.0
                }
            }
        }
    }
    
    // Theme-aware progress color with fallback
    private var themeAwareProgressColor: Color {
        if let themeColor = tab.themeColor {
            let nsColor = themeColor
            // Ensure the color has good visibility
            return Color(nsColor).opacity(0.9)
        }
        return Color.blue
    }
    
    // Progress as percentage for width calculation
    private var progressPercent: CGFloat {
        return CGFloat(SafeNumericConversions.safeProgress(tab.estimatedProgress))
    }
}