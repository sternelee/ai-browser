import SwiftUI

// Seamless new tab input that slides up from bottom edge on hover
// Inspired by macOS 18 Finder - never overlays content, appears from edge
struct BottomHoverSearch: View {
    @Binding var isVisible: Bool
    let tabManager: TabManager
    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool
    @State private var suggestions: [SearchSuggestion] = []
    
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
        .offset(y: isVisible ? 0 : 100)
        .opacity(isVisible ? 1 : 0)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isVisible)
        .onAppear {
            if isVisible {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isSearchFocused = true
                }
            }
        }
        .onChange(of: isVisible) { _, visible in
            if !visible {
                isSearchFocused = false
                searchText = ""
                suggestions = []
            }
        }
    }
    
    private var searchBar: some View {
        HStack(spacing: 12) {
            searchIcon
            searchTextField
            if !searchText.isEmpty {
                clearButton
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(searchBarBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: -2)
    }
    
    private var searchIcon: some View {
        Image(systemName: "magnifyingglass")
            .foregroundColor(.secondary)
            .font(.system(size: 16, weight: .medium))
    }
    
    private var searchTextField: some View {
        TextField("Search Google or enter website", text: $searchText)
            .textFieldStyle(.plain)
            .font(.system(.body, weight: .regular))
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
                .foregroundColor(.secondary)
                .font(.system(size: 14))
        }
        .buttonStyle(.plain)
        .transition(.scale.combined(with: .opacity))
    }
    
    private var searchBarBackground: some View {
        ZStack {
            // Backdrop blur effect
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
            
            // Subtle border
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isSearchFocused ? .blue.opacity(0.5) : .primary.opacity(0.1), 
                    lineWidth: 1
                )
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
            .foregroundColor(.secondary)
            .font(.system(size: 14))
            .frame(width: 16)
    }
    
    private func suggestionTextView(_ text: String) -> some View {
        Text(text)
            .font(.system(.body))
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var historyIconView: some View {
        Image(systemName: "clock")
            .foregroundColor(Color.primary.opacity(0.3))
            .font(.system(size: 12))
    }
    
    private var suggestionBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.ultraThinMaterial)
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: -1)
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