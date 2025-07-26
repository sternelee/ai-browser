import SwiftUI
import AppKit

struct HoverableURLBar: View {
    let tabID: UUID
    let themeColor: NSColor?
    let onSubmit: (String) -> Void
    let tabManager: TabManager
    @State private var isVisible: Bool = false
    @State private var hideTimer: Timer?
    @State private var initialShowTimer: Timer?
    @FocusState private var isURLBarFocused: Bool
    @State private var editingText: String = ""
    @State private var suggestions: [SearchSuggestion] = []
    
    // Use centralized URL synchronizer for state management
    @ObservedObject private var urlSynchronizer = URLSynchronizer.shared
    
    struct SearchSuggestion: Identifiable {
        let id = UUID()
        let text: String
        let type: SuggestionType
        
        enum SuggestionType {
            case search, url, history
        }
    }
    
    // Convert NSColor to SwiftUI Color
    private var swiftUIThemeColor: Color {
        if let nsColor = themeColor {
            return Color(nsColor)
        }
        return .clear
    }
    
    // Simplified display text logic using URLSynchronizer
    private var displayText: String {
        if isURLBarFocused {
            return editingText
        } else {
            // For hoverable URL bar, show the full URL instead of the cleaned version
            return urlSynchronizer.currentURL
        }
    }
    
    // Editable binding for input field
    private var editableText: Binding<String> {
        Binding(
            get: { self.displayText },
            set: { newValue in
                self.editingText = newValue
                if self.isURLBarFocused {
                    self.updateSuggestions(for: newValue)
                }
            }
        )
    }
    
    private func syncWithURLSynchronizer() {
        // Initialize editing text when focus is gained
        if isURLBarFocused && editingText.isEmpty {
            editingText = urlSynchronizer.currentURL
        }
    }
    
    var body: some View {
        VStack {
            HStack {
                Spacer()
                
                // Hoverable URL bar that appears at the top center
                if isVisible {
                    HStack(spacing: 12) {
                        // Security indicator
                        SecurityIndicator(urlString: urlSynchronizer.currentURL, mixedContentStatus: nil)
                        
                        // URL input field
                        TextField("Search Google or enter website", text: editableText)
                            .textFieldStyle(.plain)
                            .font(.webBody)
                            .foregroundColor(.textPrimary)
                            .focused($isURLBarFocused)
                            .textSelection(.enabled)
                            .frame(minWidth: 300, maxWidth: 500)
                            .onSubmit {
                                navigateToURL()
                            }
                            .onChange(of: isURLBarFocused) { _, focused in
                                if focused {
                                    syncWithURLSynchronizer()
                                    // Keep visible when focused
                                    cancelHideTimer()
                                } else {
                                    // Hide after delay when unfocused
                                    scheduleHide()
                                    suggestions = []
                                }
                            }
                        
                        // Clear button
                        if !editingText.isEmpty && isURLBarFocused {
                            Button(action: {
                                editingText = ""
                                suggestions = []
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.textSecondary)
                                    .font(.system(size: 14))
                            }
                            .buttonStyle(.plain)
                            .transition(.scale.combined(with: .opacity))
                        }
                        
                        // Navigation and action controls
                        HStack(spacing: 6) {
                            // Navigation controls
                            if tabManager.activeTab != nil {
                                SimpleActionButton(icon: "chevron.left", action: {
                                    NotificationCenter.default.post(name: .navigateBack, object: nil)
                                })
                                
                                SimpleActionButton(icon: "chevron.right", action: {
                                    NotificationCenter.default.post(name: .navigateForward, object: nil)
                                })
                                
                                SimpleActionButton(icon: "arrow.clockwise", action: {
                                    NotificationCenter.default.post(name: .reloadRequested, object: nil)
                                })
                                
                                // Separator
                                Rectangle()
                                    .fill(Color.borderGlass)
                                    .frame(width: 1, height: 16)
                                    .opacity(0.5)
                            }
                            
                            // Quick actions
                            SimpleActionButton(icon: "plus", action: {
                                _ = tabManager.createNewTab()
                            })
                            
                            SimpleActionButton(icon: "arrow.down.circle", action: {
                                NotificationCenter.default.post(name: .showDownloadsRequested, object: nil)
                            })
                            
                            AIToggleButton()
                            BookmarkButton()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(hoverableURLBarBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                Spacer()
            }
            .padding(.top, 12)
            
            // Search suggestions (if any)
            if !suggestions.isEmpty && isURLBarFocused {
                VStack {
                    Spacer().frame(height: 8)
                    
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
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                    .frame(maxWidth: 500)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    
                    Spacer()
                }
            }
            
            Spacer()
        }
        .onHover { hovering in
            handleHover(hovering)
        }
        .onAppear {
            syncWithURLSynchronizer()
            setupNotificationHandlers()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dismissHoverableURLBar)) { _ in
            handleDismissRequest()
        }
        // Removed complex focus coordinator - using native SwiftUI focus
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isVisible)
    }
    
    private var hoverableURLBarBackground: some View {
        ZStack {
            // Glass morphism background
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .opacity(0.9)
            
            // Theme color integration
            if themeColor != nil && swiftUIThemeColor != .clear {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        EllipticalGradient(
                            colors: [
                                swiftUIThemeColor.opacity(0.06),
                                swiftUIThemeColor.opacity(0.03),
                                Color.clear
                            ],
                            center: .center,
                            startRadiusFraction: 0.3,
                            endRadiusFraction: 1.0
                        )
                    )
                    .animation(.easeInOut(duration: 0.4), value: themeColor)
            }
            
            // Subtle border
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.borderGlass.opacity(0.2), lineWidth: 0.5)
        }
    }
    
    private func handleHover(_ hovering: Bool) {
        if hovering {
            cancelAllTimers()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isVisible = true
            }
        } else {
            // Only hide if not focused
            if !isURLBarFocused {
                scheduleHide()
            }
        }
    }
    
    private func scheduleHide() {
        cancelAllTimers()
        // Use DispatchQueue to prevent main thread blocking
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard !isURLBarFocused else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isVisible = false
            }
        }
    }
    
    private func cancelHideTimer() {
        // Dispatch timer invalidation to prevent main thread blocking  
        DispatchQueue.main.async {
            hideTimer?.invalidate()
            hideTimer = nil
        }
    }
    
    private func startInitialShowTimer() {
        // Cancel any existing timers
        cancelAllTimers()
        
        // Show immediately
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isVisible = true
        }
        
        // Hide after 2 seconds if not interacting
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            guard !isURLBarFocused else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isVisible = false
            }
        }
    }
    
    private func cancelAllTimers() {
        DispatchQueue.main.async {
            hideTimer?.invalidate()
            hideTimer = nil
            initialShowTimer?.invalidate()
            initialShowTimer = nil
        }
    }
    
    /// Setup notification handlers for ESCAPE key dismissal
    private func setupNotificationHandlers() {
        // Notification handlers are managed by onReceive in the body
        // This function is kept for consistency and future expansion
    }
    
    /// Handle dismiss request from ESCAPE key
    private func handleDismissRequest() {
        // Handle different states with priority: suggestions first, then URL bar
        if !suggestions.isEmpty && isURLBarFocused {
            // Clear suggestions first if they're visible
            suggestions = []
            // Post notification that HoverableURLBar handled the escape
            NotificationCenter.default.post(name: .hoverableURLBarDismissed, object: nil)
        } else if isVisible && isURLBarFocused {
            // Then dismiss URL bar if focused
            isURLBarFocused = false
            suggestions = []
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isVisible = false
            }
            // Post notification that HoverableURLBar handled the escape
            NotificationCenter.default.post(name: .hoverableURLBarDismissed, object: nil)
        }
    }
    
    private func navigateToURL() {
        let inputText = editingText.isEmpty ? urlSynchronizer.currentURL : editingText
        guard !inputText.isEmpty else { return }
        
        // Update URLSynchronizer with user input
        let finalURL: String
        if isValidURL(inputText) {
            finalURL = inputText.hasPrefix("http") ? inputText : "https://\(inputText)"
        } else {
            let searchQuery = inputText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            finalURL = "https://www.google.com/search?q=\(searchQuery)"
        }
        
        urlSynchronizer.updateFromUserInput(urlString: finalURL, tabID: tabID)
        
        // Navigate to URL or perform search
        if isValidURL(inputText) {
            navigateToURLString(inputText)
        } else {
            performGoogleSearch(inputText)
        }
        
        editingText = ""
        suggestions = []
        isURLBarFocused = false
        
        // Hide after navigation
        scheduleHide()
    }
    
    private func navigateToURLString(_ urlString: String) {
        let finalURL = urlString.hasPrefix("http") ? urlString : "https://\(urlString)"
        if let url = URL(string: finalURL) {
            if let activeTab = tabManager.activeTab {
                activeTab.navigate(to: url)
            } else {
                _ = tabManager.createNewTab(url: url)
            }
        }
    }
    
    private func performGoogleSearch(_ query: String) {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://www.google.com/search?q=\(encodedQuery)") {
            if let activeTab = tabManager.activeTab {
                activeTab.navigate(to: url)
            } else {
                _ = tabManager.createNewTab(url: url)
            }
        }
    }
    
    private func updateSuggestions(for query: String) {
        guard !query.isEmpty && isURLBarFocused else {
            suggestions = []
            return
        }
        // Use the shared AutofillService for suggestions
        Task {
            let autofillResults = await AutofillService.shared.getSuggestions(for: query)
            // Map AutofillSuggestion to local SearchSuggestion for display
            let mapped: [SearchSuggestion] = autofillResults.map { suggestion in
                let type: SearchSuggestion.SuggestionType
                switch suggestion.sourceType {
                case .history, .mostVisited:
                    type = .history
                case .bookmark:
                    type = .url
                case .searchSuggestion:
                    type = .search
                }
                return SearchSuggestion(text: suggestion.title, type: type)
            }
            // Prepend a Google search suggestion as first item
            let searchItem = SearchSuggestion(text: query, type: .search)
            await MainActor.run {
                suggestions = [searchItem] + mapped.prefix(5)
            }
        }
    }
    
    private func suggestionItem(_ suggestion: SearchSuggestion) -> some View {
        Button(action: {
            editingText = suggestion.text
            navigateToURL()
        }) {
            HStack(spacing: 12) {
                Image(systemName: suggestionIcon(for: suggestion.type))
                    .foregroundColor(.textSecondary)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 16)
                
                Text(suggestion.text)
                    .font(.webBody)
                    .foregroundColor(.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                if suggestion.type == .history {
                    Image(systemName: "clock")
                        .foregroundColor(.textSecondary)
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var suggestionBackground: some View {
        ZStack {
            // Enhanced glass background
            RoundedRectangle(cornerRadius: 12)
                .fill(.thickMaterial)
            
            // Theme color integration
            if themeColor != nil && swiftUIThemeColor != .clear {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        EllipticalGradient(
                            colors: [
                                swiftUIThemeColor.opacity(0.06),
                                swiftUIThemeColor.opacity(0.03),
                                Color.clear
                            ],
                            center: .center,
                            startRadiusFraction: 0.3,
                            endRadiusFraction: 1.0
                        )
                    )
                    .animation(.easeInOut(duration: 0.4), value: themeColor)
            }
            
            // Subtle border
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.borderGlass.opacity(0.2), lineWidth: 0.5)
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

// Simple action button component for hoverable URL bar
struct SimpleActionButton: View {
    let icon: String
    let action: () -> Void
    @State private var isHovered: Bool = false
    @State private var isPressed: Bool = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.textSecondary)
                .frame(width: 24, height: 24)
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

#Preview {
    HoverableURLBar(
        tabID: UUID(),
        themeColor: nil,
        onSubmit: { _ in },
        tabManager: TabManager()
    )
    .frame(width: 800, height: 600)
    .background(Color.bgSurface)
}