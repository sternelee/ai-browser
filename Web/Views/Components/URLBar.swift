import SwiftUI
import AppKit

struct URLBar: View {
    @Binding var urlString: String
    let themeColor: NSColor?
    let onSubmit: (String) -> Void
    let pageTitle: String
    @FocusState private var isURLBarFocused: Bool
    @State private var hovering: Bool = false
    @State private var editingText: String = ""
    @State private var displayString: String = ""
    @State private var suggestions: [AutofillSuggestion] = []
    
    // Simplified - use native SwiftUI focus management
    
    // Convert NSColor to SwiftUI Color
    private var swiftUIThemeColor: Color {
        if let nsColor = themeColor {
            return Color(nsColor)
        }
        return .clear
    }
    
    // Simple binding for display text using state variable
    private var displayText: Binding<String> {
        Binding(
            get: { 
                if isURLBarFocused || hovering {
                    return editingText
                } else {
                    return displayString
                }
            },
            set: { newValue in
                if isURLBarFocused || hovering {
                    editingText = newValue
                } else {
                    displayString = newValue
                }
            }
        )
    }
    
    // Update display string based on current state
    private func updateDisplayString() {
        guard !isURLBarFocused && !hovering else { return }
        
        let hasValidTitle = !pageTitle.isEmpty && pageTitle != "New Tab"
        if hasValidTitle && !urlString.isEmpty {
            displayString = pageTitle
        } else if !urlString.isEmpty {
            displayString = cleanDisplayURL(urlString)
        } else {
            displayString = ""
        }
    }
    
    // Clean URL for display (remove protocol, www, etc.)
    private func cleanDisplayURL(_ url: String) -> String {
        var cleanURL = url
        
        // Remove protocol
        if cleanURL.hasPrefix("https://") {
            cleanURL = String(cleanURL.dropFirst(8))
        } else if cleanURL.hasPrefix("http://") {
            cleanURL = String(cleanURL.dropFirst(7))
        }
        
        // Remove www.
        if cleanURL.hasPrefix("www.") {
            cleanURL = String(cleanURL.dropFirst(4))
        }
        
        // Remove trailing slash
        if cleanURL.hasSuffix("/") {
            cleanURL = String(cleanURL.dropLast())
        }
        
        return cleanURL
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Security indicator with enhanced design
            SecurityIndicator(urlString: urlString)
            
            // Main input field with title-first display
            TextField("Search or enter website", text: displayText)
                .textFieldStyle(.plain)
                .font(.webBody)
                .foregroundColor(.textPrimary)
                .focused($isURLBarFocused)
                .textSelection(.enabled)
                .onSubmit {
                    navigateToURL()
                }
                .onChange(of: isURLBarFocused) { _, focused in
                    if focused {
                        editingText = urlString
                    } else {
                        updateDisplayString()
                    }
                }
                .onChange(of: urlString) { _, newURL in
                    if !isURLBarFocused && editingText != newURL {
                        editingText = newURL
                    }
                    updateDisplayString()
                }
                .onChange(of: pageTitle) { _, newTitle in
                    updateDisplayString()
                }
                .onChange(of: editingText) { _, newValue in
                    updateSuggestions(for: newValue)
                }
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.hovering = hovering
                    }
                    if !hovering {
                        updateDisplayString()
                    }
                }
            
            // Quick actions with improved spacing
            HStack(spacing: 6) {
                HistoryButton()
                DownloadsButton()
                BookmarkButton(urlString: urlString)
                AIToggleButton()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4) // Further reduced for even more minimal height
        .background(urlBarBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            updateDisplayString()
        }
        // Removed complex focus coordinator - using native SwiftUI focus
        .onReceive(NotificationCenter.default.publisher(for: .focusURLBarRequested)) { _ in
            isURLBarFocused = true
        }
        .overlay(alignment: .topLeading) {
            // Suggestion list overlay – does not affect layout height
            if isURLBarFocused && !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(suggestions.prefix(5)) { suggestion in
                        suggestionRow(suggestion)
                        if suggestion.id != suggestions.prefix(5).last?.id {
                            Divider()
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                        .shadow(radius: 8)
                )
                .offset(y: 34) // show below URLBar
                .transition(.opacity.combined(with: .move(edge: .top)))
                .zIndex(1000)
            }
        }
    }
    
    private var urlBarBackground: some View {
        ZStack {
            // Fully transparent background for clean input
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.clear)
                .allowsHitTesting(false)
            
            // Subtle theme color integration
            if themeColor != nil && swiftUIThemeColor != .clear {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        EllipticalGradient(
                            colors: [
                                swiftUIThemeColor.opacity(0.04),
                                swiftUIThemeColor.opacity(0.02),
                                Color.clear
                            ],
                            center: .center,
                            startRadiusFraction: 0.3,
                            endRadiusFraction: 1.0
                        )
                    )
                    .animation(.easeInOut(duration: 0.4), value: themeColor)
                    .allowsHitTesting(false)
            }
            
            // Seamless focus enhancement
            if isURLBarFocused {
                // Subtle inner ambient glow
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        EllipticalGradient(
                            colors: [
                                focusGlowColor.opacity(0.06),
                                focusGlowColor.opacity(0.03),
                                focusGlowColor.opacity(0.01),
                                Color.clear
                            ],
                            center: .center,
                            startRadiusFraction: 0.3,
                            endRadiusFraction: 1.2
                        )
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: themeColor)
                    .allowsHitTesting(false)
                
                // Minimal surface elevation
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.02),
                                Color.clear,
                                Color.black.opacity(0.01)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .transition(.opacity)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isURLBarFocused)
                    .allowsHitTesting(false)
            }
            
            // Ultra-subtle border (only when not focused)
            if !isURLBarFocused {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        hovering ? Color.borderGlass.opacity(0.3) : Color.borderGlass.opacity(0.15),
                        lineWidth: 0.5
                    )
                    .animation(.easeInOut(duration: 0.2), value: hovering)
                    .allowsHitTesting(false)
            }
        }
    }
    
    // Seamless focus styling
    
    private var focusGlowColor: Color {
        return themeColor != nil ? swiftUIThemeColor : Color.accentBeam
    }
    
    private func navigateToURL() {
        let inputText = editingText.isEmpty ? urlString : editingText
        let finalURL: String
        
        // Determine if input is URL or search query
        if isValidURL(inputText) {
            finalURL = inputText.hasPrefix("http") ? inputText : "https://\(inputText)"
        } else {
            // Search Google
            let searchQuery = inputText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            finalURL = "https://www.google.com/search?q=\(searchQuery)"
        }
        
        onSubmit(finalURL)
        isURLBarFocused = false
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
    
    private func suggestionRow(_ suggestion: AutofillSuggestion) -> some View {
        Button(action: {
            isURLBarFocused = false
            editingText = suggestion.url
            navigateToURL(from: suggestion)
        }) {
            HStack(spacing: 8) {
                Image(systemName: icon(for: suggestion.sourceType))
                    .foregroundColor(.textSecondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.title)
                        .foregroundColor(.textPrimary)
                    Text(suggestion.url)
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func updateSuggestions(for query: String) {
        guard isURLBarFocused && !query.isEmpty else {
            suggestions = []
            return
        }
        Task {
            let results = await AutofillService.shared.getSuggestions(for: query)
            await MainActor.run {
                suggestions = results
            }
        }
    }

    private func icon(for type: SuggestionSourceType) -> String {
        switch type {
        case .history, .mostVisited:
            return "clock.arrow.circlepath"
        case .bookmark:
            return "bookmark"
        case .searchSuggestion:
            return "magnifyingglass"
        }
    }

    private func navigateToURL(from suggestion: AutofillSuggestion) {
        onSubmit(suggestion.url)
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

// History button component
struct HistoryButton: View {
    @State private var hovering: Bool = false
    
    var body: some View {
        Button(action: showHistory) {
            Image(systemName: "clock")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textSecondary)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                self.hovering = hovering
            }
        }
    }
    
    private func showHistory() {
        KeyboardShortcutHandler.shared.showHistoryPanel.toggle()
    }
}

// Downloads button component
struct DownloadsButton: View {
    @ObservedObject private var downloadManager = DownloadManager.shared
    @State private var hovering: Bool = false
    
    var body: some View {
        Button(action: showDownloads) {
            ZStack {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textSecondary)
                    .frame(width: 20, height: 20)
                
                // Active download indicator
                if downloadManager.totalActiveDownloads > 0 {
                    Circle()
                        .fill(.blue)
                        .frame(width: 6, height: 6)
                        .offset(x: 6, y: -6)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                self.hovering = hovering
            }
        }
    }
    
    private func showDownloads() {
        KeyboardShortcutHandler.shared.showDownloadsPanel.toggle()
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

// AI Toggle button component
struct AIToggleButton: View {
    @State private var hovering: Bool = false
    @State private var isAISidebarExpanded: Bool = false
    
    var body: some View {
        Button(action: toggleAISidebar) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isAISidebarExpanded ? .accentColor : (hovering ? .textPrimary : .textSecondary))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                self.hovering = hovering
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .aISidebarStateChanged)) { notification in
            if let expanded = notification.object as? Bool {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isAISidebarExpanded = expanded
                }
            }
        }
    }
    
    private func toggleAISidebar() {
        NotificationCenter.default.post(name: .toggleAISidebar, object: nil)
    }
}

#Preview {
    URLBar(urlString: .constant("https://www.google.com"), themeColor: nil, onSubmit: { _ in }, pageTitle: "Google")
}