import SwiftUI
import AppKit

struct URLBar: View {
    @Binding var urlString: String
    let onSubmit: (String) -> Void
    @FocusState private var isURLBarFocused: Bool
    @State private var hovering: Bool = false
    
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
                .onSubmit {
                    navigateToURL()
                }
            
            // Quick actions with improved spacing
            HStack(spacing: 6) {
                ShareButton(urlString: urlString)
                BookmarkButton(urlString: urlString)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
            
            // Dynamic border with focus state
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isURLBarFocused ? Color.accentBeam : (hovering ? Color.borderGlass.opacity(0.8) : Color.borderGlass.opacity(0.4)),
                    lineWidth: isURLBarFocused ? 2 : 1
                )
                .animation(.easeInOut(duration: 0.2), value: isURLBarFocused)
                .animation(.easeInOut(duration: 0.2), value: hovering)
            
            // Subtle inner glow when focused
            if isURLBarFocused {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.accentBeam.opacity(0.03),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 100
                        )
                    )
                    .transition(.opacity)
            }
        }
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
                .frame(width: 24, height: 24)
        }
        .buttonStyle(URLBarActionButtonStyle())
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
                .frame(width: 24, height: 24)
        }
        .buttonStyle(URLBarActionButtonStyle())
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
    URLBar(urlString: .constant("google.com"), onSubmit: { _ in })
}