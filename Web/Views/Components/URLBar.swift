import SwiftUI
import AppKit

struct URLBar: View {
    @Binding var urlString: String
    let onSubmit: (String) -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            // Security indicator
            SecurityIndicator(urlString: urlString)
            
            // Main input field
            TextField("Search or enter website", text: $urlString)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .onSubmit {
                    navigateToURL()
                }
            
            // Quick actions
            HStack(spacing: 4) {
                ShareButton(urlString: urlString)
                BookmarkButton(urlString: urlString)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
        )
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
        if string.contains(".") && !string.contains(" ") {
            return true
        }
        return URL(string: string) != nil
    }
    
}

// Security indicator component
struct SecurityIndicator: View {
    let urlString: String
    
    private var isSecure: Bool {
        urlString.hasPrefix("https://")
    }
    
    var body: some View {
        Image(systemName: isSecure ? "lock.fill" : "lock.open.fill")
            .font(.system(size: 12))
            .foregroundColor(isSecure ? .green : .orange)
    }
}

// Share button component
struct ShareButton: View {
    let urlString: String
    
    var body: some View {
        Button(action: shareURL) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .disabled(urlString.isEmpty)
    }
    
    private func shareURL() {
        guard let url = URL(string: urlString) else { return }
        
        let sharingPicker = NSSharingServicePicker(items: [url])
        if let window = NSApplication.shared.keyWindow {
            sharingPicker.show(relativeTo: .zero, of: window.contentView!, preferredEdge: .minY)
        }
    }
}

// Bookmark button component
struct BookmarkButton: View {
    let urlString: String
    @State private var isBookmarked = false
    
    var body: some View {
        Button(action: toggleBookmark) {
            Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                .font(.system(size: 12))
                .foregroundColor(isBookmarked ? .blue : .secondary)
        }
        .buttonStyle(.plain)
        .disabled(urlString.isEmpty)
    }
    
    private func toggleBookmark() {
        isBookmarked.toggle()
        // TODO: Implement actual bookmark functionality
    }
}


#Preview {
    URLBar(urlString: .constant("google.com"), onSubmit: { _ in })
}