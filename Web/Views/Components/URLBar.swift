import SwiftUI
import AppKit

struct URLBar: View {
    @Binding var urlString: String
    let themeColor: NSColor?
    let onSubmit: (String) -> Void
    let pageTitle: String?
    @FocusState private var isURLBarFocused: Bool
    @State private var hovering: Bool = false
    @State private var editingText: String = ""
    
    // Autofill state
    @StateObject private var autofillService = AutofillService()
    @State private var showingSuggestions = false
    @State private var suggestions: [AutofillSuggestion] = []
    @State private var selectedSuggestionIndex = 0
    @State private var suggestionTask: Task<Void, Never>?
    
    // Convert NSColor to SwiftUI Color
    private var swiftUIThemeColor: Color {
        if let nsColor = themeColor {
            return Color(nsColor)
        }
        return .clear
    }
    
    // Computed property for display text (title-first approach)
    private var displayText: Binding<String> {
        Binding(
            get: {
                if isURLBarFocused || hovering {
                    return editingText
                } else if let title = pageTitle, !title.isEmpty && title != "New Tab" && !urlString.isEmpty {
                    return title
                } else if !urlString.isEmpty {
                    return cleanDisplayURL(urlString)
                } else {
                    return ""
                }
            },
            set: { newValue in
                editingText = newValue
            }
        )
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
                    handleSubmit()
                }
                .onChange(of: isURLBarFocused) { _, focused in
                    handleFocusChange(focused)
                }
                .onChange(of: urlString) { _, newURL in
                    if !isURLBarFocused {
                        editingText = newURL
                    }
                }
                .onChange(of: editingText) { _, newText in
                    handleTextChange(newText)
                }
                .onKeyPress { keyPress in
                    handleKeyPress(keyPress)
                }
            
            // Quick actions with improved spacing
            HStack(spacing: 6) {
                ShareButton(urlString: urlString)
                BookmarkButton(urlString: urlString, autofillService: autofillService)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(urlBarBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                self.hovering = hovering
            }
        }
        .overlay(alignment: .topLeading) {
            // Autofill suggestions positioned with proper offset to avoid affecting parent height
            if showingSuggestions {
                VStack(spacing: 4) {
                    if !suggestions.isEmpty {
                        AutofillSuggestionsView(
                            suggestions: suggestions,
                            selectedIndex: selectedSuggestionIndex,
                            onSelect: selectSuggestion,
                            onDismiss: dismissSuggestions
                        )
                    } else if autofillService.isLoading {
                        AutofillLoadingView()
                    }
                }
                .offset(y: 44) // Position below URLBar without affecting layout
                .zIndex(1000) // Ensure it appears above other content
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showingSuggestions)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: suggestions.isEmpty)
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
    
    // MARK: - Navigation Methods
    
    private func handleSubmit() {
        // Check if we should use a selected suggestion
        if showingSuggestions && !suggestions.isEmpty && selectedSuggestionIndex >= 0 && selectedSuggestionIndex < suggestions.count {
            let selectedSuggestion = suggestions[selectedSuggestionIndex]
            selectSuggestion(selectedSuggestion)
        } else {
            // Normal navigation with current input
            dismissSuggestions()
            navigateToURL()
        }
    }
    
    private func handleFocusChange(_ focused: Bool) {
        if focused {
            editingText = urlString
            // Show suggestions immediately if there's text
            if !editingText.isEmpty {
                loadSuggestions(for: editingText)
            }
        } else {
            // Hide suggestions when unfocused
            dismissSuggestions()
        }
    }
    
    private func handleTextChange(_ newText: String) {
        loadSuggestions(for: newText)
    }
    
    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        guard showingSuggestions else { return .ignored }
        
        switch keyPress.key {
        case .downArrow:
            selectedSuggestionIndex = min(selectedSuggestionIndex + 1, suggestions.count - 1)
            return .handled
        case .upArrow:
            selectedSuggestionIndex = max(selectedSuggestionIndex - 1, 0)
            return .handled
        case .escape:
            dismissSuggestions()
            return .handled
        default:
            return .ignored
        }
    }
    
    private func loadSuggestions(for query: String) {
        // Cancel previous task
        suggestionTask?.cancel()
        
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Hide suggestions for very short queries
        guard trimmedQuery.count >= 1 else {
            dismissSuggestions()
            return
        }
        
        // Start new task
        suggestionTask = Task {
            let newSuggestions = await autofillService.getSuggestions(for: trimmedQuery)
            
            await MainActor.run {
                guard !Task.isCancelled else { return }
                
                suggestions = newSuggestions
                selectedSuggestionIndex = 0
                showingSuggestions = !suggestions.isEmpty || autofillService.isLoading
            }
        }
    }
    
    private func selectSuggestion(_ suggestion: AutofillSuggestion) {
        editingText = suggestion.url
        
        // Navigate to the selected URL
        let finalURL = suggestion.url.hasPrefix("http") ? suggestion.url : "https://\(suggestion.url)"
        
        // Record the visit
        autofillService.recordVisit(url: finalURL, title: suggestion.title)
        
        onSubmit(finalURL)
        dismissSuggestions()
        isURLBarFocused = false
    }
    
    private func dismissSuggestions() {
        suggestionTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            showingSuggestions = false
            suggestions.removeAll()
        }
    }
    
    private func navigateToURL() {
        let inputText = editingText.isEmpty ? urlString : editingText
        let finalURL: String
        let title: String
        
        // Determine if input is URL or search query
        if isValidURL(inputText) {
            finalURL = inputText.hasPrefix("http") ? inputText : "https://\(inputText)"
            title = cleanDisplayURL(finalURL)
        } else {
            // Search Google
            let searchQuery = inputText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            finalURL = "https://www.google.com/search?q=\(searchQuery)"
            title = "Search for \"\(inputText)\""
        }
        
        // Record the visit for autofill suggestions
        autofillService.recordVisit(url: finalURL, title: title)
        
        onSubmit(finalURL)
        isURLBarFocused = false
        dismissSuggestions()
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
    let autofillService: AutofillService
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
        .onAppear {
            checkBookmarkStatus()
        }
        .onChange(of: urlString) { _, _ in
            checkBookmarkStatus()
        }
    }
    
    private func toggleBookmark() {
        if isBookmarked {
            autofillService.removeBookmark(url: urlString)
        } else {
            // Extract title from URL for now - in real app would use page title
            let title = cleanDisplayURL(urlString)
            autofillService.addBookmark(url: urlString, title: title)
        }
        isBookmarked.toggle()
    }
    
    private func checkBookmarkStatus() {
        // In a real app, this would check the bookmark status from the service
        // For now, we'll keep the existing behavior
    }
    
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
}


// Custom button style for URL bar actions
struct URLBarActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle()
                    .fill(.ultraThinMaterial)
                    .opacity(configuration.isPressed ? 0.8 : 0.0)
            )
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}


#Preview {
    VStack {
        URLBar(urlString: .constant("https://www.google.com"), themeColor: nil, onSubmit: { _ in }, pageTitle: "Google")
        URLBar(urlString: .constant(""), themeColor: nil, onSubmit: { _ in }, pageTitle: nil)
    }
    .padding()
    .background(.ultraThinMaterial)
}