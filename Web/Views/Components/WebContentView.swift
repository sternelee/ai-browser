import SwiftUI
import WebKit

// Web content view for displaying individual tabs
struct WebContentView: View {
    @ObservedObject var tab: Tab
    @Binding var urlString: String
    @State private var pulsingScale: CGFloat = 1.0
    @State private var hoveredLink: String? = nil
    @State private var hasInitializedWebView: Bool = false
    
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
                // Active web view - only create WebView once per tab to maintain state
                if tab.url != nil {
                    PersistentWebView(tab: tab, urlString: $urlString, hoveredLink: $hoveredLink)
                        .onAppear {
                            hasInitializedWebView = true
                        }
                } else {
                    NewTabView()
                        .onAppear {
                            hasInitializedWebView = false
                        }
                }
            }
            
            // Enhanced loading progress bar positioned closer to top bar
            if tab.isLoading {
                VStack(spacing: 0) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background track
                            Rectangle()
                                .fill(Color.secondary.opacity(0.15))
                                .frame(height: 3)
                            
                            // Main progress fill with default blue
                            Rectangle()
                                .fill(Color.blue)
                                .frame(width: geometry.size.width * progressPercent, height: 3)
                                .animation(.easeOut(duration: 0.2), value: tab.estimatedProgress)
                                .animation(.easeInOut(duration: 0.5), value: tab.themeColor)
                            
                            // Progressive blur overlay - no blur at start, maximum at end
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.clear, // No effect at start
                                            Color.clear,
                                            Color.blue.opacity(0.2),
                                            Color.blue.opacity(0.5) // Max glow near end
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * progressPercent, height: 6)
                                .blur(radius: progressiveBlurRadius)
                                .animation(.easeOut(duration: 0.2), value: tab.estimatedProgress)
                            
                            // Enhanced progressive trailing glow
                            if tab.estimatedProgress > 0.3 {
                                Rectangle()
                                    .fill(
                                        RadialGradient(
                                            colors: [
                                                Color.blue.opacity(0.6),
                                                Color.blue.opacity(0.3),
                                                Color.blue.opacity(0.1),
                                                Color.clear
                                            ],
                                            center: .center,
                                            startRadius: 1,
                                            endRadius: 15
                                        )
                                    )
                                    .frame(width: 8, height: 8)
                                    .offset(x: geometry.size.width * progressPercent - 4, y: 1)
                                    .blur(radius: progressiveBlurRadius * 0.8)
                                    .scaleEffect(pulsingScale)
                                    .animation(.easeOut(duration: 0.2), value: tab.estimatedProgress)
                            }
                        }
                        .clipShape(Capsule())
                    }
                    .frame(height: 3)
                    .transition(.opacity.combined(with: .scale(scale: 1.0, anchor: .leading)))
                    .padding(.top, 0) // No margin - positioned directly against top bar
                    
                    Spacer()
                }
            }
            
            // Smart Status Bar positioned at bottom-left - only show for link hover, not loading
            VStack {
                Spacer()
                HStack {
                    SmartStatusBar(tab: tab, hoveredLink: hoveredLink)
                    Spacer()
                }
                .padding(.bottom, 16)
                .padding(.leading, 16)
            }
            .allowsHitTesting(false) // Don't interfere with web content interaction
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
            // Convert to SwiftUI color and ensure good saturation
            let swiftColor = Color(nsColor)
            
            // Boost saturation for better visibility in progress bars
            let components = NSColor(swiftColor).usingColorSpace(.sRGB) ?? NSColor.blue
            let red = min(1.0, components.redComponent * 1.2)
            let green = min(1.0, components.greenComponent * 1.2)  
            let blue = min(1.0, components.blueComponent * 1.2)
            
            return Color(red: red, green: green, blue: blue)
        }
        return Color.blue
    }
    
    // Progress as percentage for width calculation
    private var progressPercent: CGFloat {
        return CGFloat(SafeNumericConversions.safeProgress(tab.estimatedProgress))
    }
    
    // Progressive blur radius - starts at 0, increases dramatically toward end
    private var progressiveBlurRadius: CGFloat {
        let progress = SafeNumericConversions.safeProgress(tab.estimatedProgress)
        // Exponential curve: no blur at start (0-30%), dramatic increase at end (70-100%)
        if progress < 0.3 {
            return 0.0
        } else {
            let adjustedProgress = (progress - 0.3) / 0.7 // Map 0.3-1.0 to 0.0-1.0
            return pow(adjustedProgress, 2.0) * 12.0 // Quadratic curve, max 12pt blur
        }
    }
}

// Persistent WebView that maintains state per tab
struct PersistentWebView: View {
    @ObservedObject var tab: Tab
    @Binding var urlString: String
    @Binding var hoveredLink: String?
    
    var body: some View {
        // Only create a new WebView if the tab doesn't already have one
        Group {
            if tab.webView == nil {
                // Create new WebView and store it in the tab
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
                    hoveredLink: $hoveredLink,
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
                // Use existing WebView wrapped in a NSViewRepresentable
                ExistingWebView(tab: tab)
                    .onChange(of: tab.url) { _, newURL in
                        if let url = newURL {
                            urlString = url.absoluteString
                        }
                    }
            }
        }
    }
}

// Wrapper for existing WebView instances
struct ExistingWebView: NSViewRepresentable {
    @ObservedObject var tab: Tab
    
    typealias NSViewType = WKWebView
    
    func makeNSView(context: Context) -> WKWebView {
        return tab.webView!
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        // Don't reload - the WebView maintains its own state
        // Just ensure the tab's properties are synced
        DispatchQueue.main.async {
            tab.canGoBack = webView.canGoBack
            tab.canGoForward = webView.canGoForward
            tab.isLoading = webView.isLoading
            tab.estimatedProgress = webView.estimatedProgress
            tab.title = webView.title ?? "New Tab"
        }
    }
}