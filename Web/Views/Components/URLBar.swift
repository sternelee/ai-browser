import SwiftUI
import AppKit

struct URLBar: View {
    @Binding var urlString: String
    let themeColor: NSColor?
    let onSubmit: (String) -> Void
    @FocusState private var isURLBarFocused: Bool
    @State private var hovering: Bool = false
    
    // Convert NSColor to SwiftUI Color
    private var swiftUIThemeColor: Color {
        if let nsColor = themeColor {
            return Color(nsColor)
        }
        return .clear
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Security indicator with enhanced design
            SecurityIndicator(urlString: urlString)
            
            // Main input field with enhanced styling
            TextField("Search or enter website", text: $urlString)
                .textFieldStyle(.plain)
                .font(.webBody)
                .foregroundColor(.textPrimary)
                .focused($isURLBarFocused)
                .textSelection(.enabled)
                .onSubmit {
                    navigateToURL()
                }
            
            // Quick actions with improved spacing
            HStack(spacing: 6) {
                ShareButton(urlString: urlString)
                BookmarkButton(urlString: urlString)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4) // Further reduced for even more minimal height
        .background(urlBarBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                self.hovering = hovering
            }
        }
    }
    
    private var urlBarBackground: some View {
        ZStack {
            // Enhanced glass background
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
            
            // Dark glass surface overlay
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.bgSurface)
            
            // Website theme color integration - seamless next-gen approach
            if themeColor != nil && swiftUIThemeColor != .clear {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [
                                swiftUIThemeColor.opacity(0.08),
                                swiftUIThemeColor.opacity(0.04),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .animation(.easeInOut(duration: 0.4), value: themeColor)
            }
            
            // Enhanced border with better focus state
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    borderColor,
                    lineWidth: borderWidth
                )
                .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isURLBarFocused)
                .animation(.easeInOut(duration: 0.2), value: hovering)
                .animation(.easeInOut(duration: 0.4), value: themeColor)
            
            // Enhanced multi-layer glow effect when focused
            if isURLBarFocused {
                // Inner radial glow
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        RadialGradient(
                            colors: [
                                focusGlowColor.opacity(0.12),
                                focusGlowColor.opacity(0.06),
                                focusGlowColor.opacity(0.02),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 80
                        )
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: themeColor)
                
                // Outer radial glow (larger)
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        RadialGradient(
                            colors: [
                                focusGlowColor.opacity(0.08),
                                focusGlowColor.opacity(0.04),
                                focusGlowColor.opacity(0.01),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 40,
                            endRadius: 160
                        )
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: themeColor)
                
                // Enhanced border glow
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        focusGlowColor.opacity(0.4),
                        lineWidth: 1
                    )
                    .blur(radius: 2)
                    .transition(.opacity)
                
                // Outer border glow (wider)
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        focusGlowColor.opacity(0.2),
                        lineWidth: 1
                    )
                    .blur(radius: 4)
                    .transition(.opacity)
            }
        }
    }
    
    // Computed properties for enhanced styling
    private var borderColor: Color {
        if isURLBarFocused {
            return themeColor != nil ? swiftUIThemeColor.opacity(0.8) : Color.accentBeam
        } else if hovering {
            return Color.borderGlass.opacity(0.8)
        } else {
            return Color.borderGlass.opacity(0.4)
        }
    }
    
    private var borderWidth: CGFloat {
        isURLBarFocused ? 2.0 : 1.0
    }
    
    private var focusGlowColor: Color {
        return themeColor != nil ? swiftUIThemeColor : Color.accentBeam
    }
    
    private func navigateToURL() {
        let finalURL: String
        
        // Determine if input is URL or search query
        if isValidURL(urlString) {
            finalURL = urlString.hasPrefix("http") ? urlString : "https://\(urlString)"
        } else {
            // Search Google
            let searchQuery = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            finalURL = "https://www.google.com/search?q=\(searchQuery)"
        }
        
        onSubmit(finalURL)
    }
    
    private func isValidURL(_ string: String) -> Bool {
        // Check if it already has a scheme
        if string.hasPrefix("http://") || string.hasPrefix("https://") {
            return URL(string: string) != nil
        }
        
        // Check if it looks like a domain (contains . and no spaces)
        if string.contains(".") && !string.contains(" ") {
            // Make sure it's not just a decimal number
            if !string.allSatisfy({ $0.isNumber || $0 == "." }) {
                return true
            }
        }
        
        return false
    }
    
}

// Security indicator component
struct SecurityIndicator: View {
    let urlString: String
    
    private var isSecure: Bool {
        urlString.hasPrefix("https://")
    }
    
    private var hasURL: Bool {
        !urlString.isEmpty && (urlString.contains(".") || urlString.hasPrefix("http"))
    }
    
    var body: some View {
        Group {
            if hasURL {
                Image(systemName: isSecure ? "lock.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isSecure ? .green.opacity(0.8) : .orange.opacity(0.8))
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textSecondary)
            }
        }
        .frame(width: 16, height: 16)
        .animation(.easeInOut(duration: 0.2), value: hasURL)
        .animation(.easeInOut(duration: 0.2), value: isSecure)
    }
}

// Share button component
struct ShareButton: View {
    let urlString: String
    @State private var hovering: Bool = false
    
    var body: some View {
        Button(action: shareURL) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(urlString.isEmpty ? .textSecondary.opacity(0.5) : .textSecondary)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .disabled(urlString.isEmpty)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                self.hovering = hovering
            }
        }
    }
    
    private func shareURL() {
        guard let url = URL(string: urlString) else { return }
        
        let sharingPicker = NSSharingServicePicker(items: [url])
        if let window = NSApplication.shared.keyWindow,
           let contentView = window.contentView {
            sharingPicker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
    }
}

// Bookmark button component
struct BookmarkButton: View {
    let urlString: String
    @State private var isBookmarked = false
    @State private var hovering: Bool = false
    
    var body: some View {
        Button(action: toggleBookmark) {
            Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isBookmarked ? Color.accentBeam : (urlString.isEmpty ? .textSecondary.opacity(0.5) : .textSecondary))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .disabled(urlString.isEmpty)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                self.hovering = hovering
            }
        }
    }
    
    private func toggleBookmark() {
        isBookmarked.toggle()
        // TODO: Implement actual bookmark functionality
    }
}


// Custom button style for URL bar actions
struct URLBarActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle()
                    .fill(Color.bgSurface)
                    .opacity(configuration.isPressed ? 0.8 : 0.0)
            )
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview {
    URLBar(urlString: .constant("google.com"), themeColor: nil, onSubmit: { _ in })
}