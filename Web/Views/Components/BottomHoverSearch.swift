import SwiftUI

// Seamless new tab input that slides up from bottom edge on hover
// Inspired by macOS 18 Finder - never overlays content, appears from edge
struct BottomHoverSearch: View {
    @Binding var isVisible: Bool
    let tabManager: TabManager
    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool
    @State private var suggestions: [SearchSuggestion] = []
    @State private var isHovering: Bool = false
    
    struct SearchSuggestion: Identifiable {
        let id = UUID()
        let text: String
        let type: SuggestionType
        
        enum SuggestionType {
            case search, url, history
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search suggestions (if any)
            if !suggestions.isEmpty && isSearchFocused {
                suggestionsList
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Main search bar
            searchBar
        }
        .frame(maxWidth: 500)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .offset(y: (isVisible || isHovering) ? 0 : 100)
        .opacity((isVisible || isHovering) ? 1 : 0)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isVisible)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
        .onAppear {
            if isVisible {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isSearchFocused = true
                }
            }
        }
        .onChange(of: isVisible) { _, visible in
            if !visible && !isHovering {
                isSearchFocused = false
                searchText = ""
                suggestions = []
            }
        }
        .onChange(of: isHovering) { _, hovering in
            if !hovering && !isVisible {
                isSearchFocused = false
                searchText = ""
                suggestions = []
            }
        }
    }
    
    private var searchBar: some View {
        HStack(spacing: 8) {
            // Quick action buttons
            contextualButtons
            
            // Divider
            Rectangle()
                .fill(Color.borderGlass)
                .frame(width: 1, height: 20)
                .opacity(0.5)
            
            // Search area
            HStack(spacing: 12) {
                searchIcon
                searchTextField
                if !searchText.isEmpty {
                    clearButton
                }
            }
            .frame(minWidth: 200)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(searchBarBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: -8)
    }
    
    private var contextualButtons: some View {
        HStack(spacing: 6) {
            // New tab button
            ContextualButton(
                icon: "plus",
                action: { _ = tabManager.createNewTab() }
            )
            
            // Back button
            ContextualButton(
                icon: "chevron.left",
                action: { NotificationCenter.default.post(name: .navigateBack, object: nil) }
            )
            
            // Forward button
            ContextualButton(
                icon: "chevron.right",
                action: { NotificationCenter.default.post(name: .navigateForward, object: nil) }
            )
            
            // Reload button
            ContextualButton(
                icon: "arrow.clockwise",
                action: { NotificationCenter.default.post(name: .reloadRequested, object: nil) }
            )
            
            // Downloads button
            ContextualButton(
                icon: "arrow.down.circle",
                action: { NotificationCenter.default.post(name: .showDownloadsRequested, object: nil) }
            )
        }
    }
    
    private var searchIcon: some View {
        Image(systemName: "magnifyingglass")
            .foregroundColor(.textSecondary)
            .font(.system(size: 16, weight: .medium))
    }
    
    private var searchTextField: some View {
        TextField("Search Google or enter website", text: $searchText)
            .textFieldStyle(.plain)
            .font(.webBody)
            .foregroundColor(.textPrimary)
            .focused($isSearchFocused)
            .onSubmit {
                performSearch()
            }
            .onChange(of: searchText) { _, newValue in
                updateSuggestions(for: newValue)
            }
    }
    
    private var clearButton: some View {
        Button(action: { 
            searchText = ""
            suggestions = []
        }) {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.textSecondary)
                .font(.system(size: 14))
        }
        .buttonStyle(.plain)
        .transition(.scale.combined(with: .opacity))
    }
    
    private var searchBarBackground: some View {
        ZStack {
            // Enhanced glass background
            RoundedRectangle(cornerRadius: 12)
                .fill(.thickMaterial)
                .allowsHitTesting(false)
            
            // Dark glass surface overlay
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.bgSurface)
                .allowsHitTesting(false)
            
            // Focus ring with accent beam
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isSearchFocused ? Color.accentBeam : Color.borderGlass, 
                    lineWidth: isSearchFocused ? 2 : 1
                )
                .animation(.easeInOut(duration: 0.2), value: isSearchFocused)
                .allowsHitTesting(false)
            
            // Subtle inner glow when focused
            if isSearchFocused {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.accentBeam.opacity(0.05),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 100
                        )
                    )
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
    }
    
    private var suggestionsList: some View {
        VStack(spacing: 0) {
            ForEach(suggestions.prefix(5)) { suggestion in
                suggestionItem(suggestion)
                if suggestion.id != suggestions.prefix(5).last?.id {
                    Divider()
                        .padding(.horizontal, 20)
                }
            }
        }
        .background(suggestionBackground)
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }
    
    private func suggestionItem(_ suggestion: SearchSuggestion) -> some View {
        Button(action: {
            searchText = suggestion.text
            performSearch()
        }) {
            HStack(spacing: 12) {
                suggestionIconView(suggestion.type)
                suggestionTextView(suggestion.text)
                if suggestion.type == .history {
                    historyIconView
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private func suggestionIconView(_ type: SearchSuggestion.SuggestionType) -> some View {
        Image(systemName: suggestionIcon(for: type))
            .foregroundColor(.textSecondary)
            .font(.system(size: 14, weight: .medium))
            .frame(width: 16)
    }
    
    private func suggestionTextView(_ text: String) -> some View {
        Text(text)
            .font(.webBody)
            .foregroundColor(.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var historyIconView: some View {
        Image(systemName: "clock")
            .foregroundColor(.textSecondary)
            .font(.system(size: 12, weight: .medium))
    }
    
    private var suggestionBackground: some View {
        ZStack {
            // Enhanced glass background
            RoundedRectangle(cornerRadius: 12)
                .fill(.thickMaterial)
            
            // Dark glass surface overlay
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.bgSurface)
            
            // Subtle border
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.borderGlass, lineWidth: 1)
            
            // Elevated shadow
            RoundedRectangle(cornerRadius: 12)
                .fill(.clear)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: -4)
        }
    }
    
    private func suggestionIcon(for type: SearchSuggestion.SuggestionType) -> String {
        switch type {
        case .search:
            return "magnifyingglass"
        case .url:
            return "globe"
        case .history:
            return "clock.arrow.circlepath"
        }
    }
    
    private func updateSuggestions(for query: String) {
        guard !query.isEmpty else {
            suggestions = []
            return
        }
        
        // Simulate search suggestions (in real implementation, this would query history, bookmarks, etc.)
        var newSuggestions: [SearchSuggestion] = []
        
        // Add search suggestion
        newSuggestions.append(SearchSuggestion(text: query, type: .search))
        
        // Add URL suggestion if it looks like a URL
        if query.contains(".") && !query.contains(" ") {
            newSuggestions.append(SearchSuggestion(text: "https://\(query)", type: .url))
        }
        
        // Add mock history suggestions
        let mockHistory = ["github.com", "stackoverflow.com", "developer.apple.com"]
        for item in mockHistory {
            if item.contains(query.lowercased()) {
                newSuggestions.append(SearchSuggestion(text: item, type: .history))
            }
        }
        
        suggestions = newSuggestions
    }
    
    private func performSearch() {
        guard !searchText.isEmpty else { return }
        
        // Navigate to URL or perform search
        if isValidURL(searchText) {
            navigateToURL(searchText)
        } else {
            performGoogleSearch(searchText)
        }
        
        // Hide the search bar after search
        isVisible = false
    }
    
    private func isValidURL(_ string: String) -> Bool {
        return string.contains(".") && !string.contains(" ") && URL(string: addHttpIfNeeded(string)) != nil
    }
    
    private func addHttpIfNeeded(_ string: String) -> String {
        if string.hasPrefix("http://") || string.hasPrefix("https://") {
            return string
        }
        return "https://\(string)"
    }
    
    private func navigateToURL(_ urlString: String) {
        if let url = URL(string: addHttpIfNeeded(urlString)) {
            _ = tabManager.createNewTab(url: url)
        }
    }
    
    private func performGoogleSearch(_ query: String) {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://www.google.com/search?q=\(encodedQuery)") {
            _ = tabManager.createNewTab(url: url)
        }
    }
}

// Contextual button for the bottom toolbar
struct ContextualButton: View {
    let icon: String
    let action: () -> Void
    @State private var isHovered: Bool = false
    @State private var isPressed: Bool = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.textSecondary)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(
                            isHovered ? Color.white.opacity(0.1) : Color.clear
                        )
                )
                .scaleEffect(isPressed ? 0.9 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = false
                }
            }
            action()
        }
    }
}