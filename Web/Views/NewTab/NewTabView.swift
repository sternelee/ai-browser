import SwiftUI

// Enhanced new tab view with Web logo and next-gen design
struct NewTabView: View {
    let tab: Tab?
    
    @State private var searchText: String = ""
    @State private var recentlyVisited: [String] = []
    @State private var recentlyClosed: [String] = []
    @FocusState private var isSearchFocused: Bool
    @State private var isSearchHovered: Bool = false
    @State private var isAISidebarExpanded: Bool = false
    
    // Initialize with optional tab for incognito detection
    init(tab: Tab? = nil) {
        self.tab = tab
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack {
                Spacer()
                
                VStack(spacing: 32) {
                    VStack(spacing: 16) {
                        // App logo with subtle animation
                        AnimatedWebLogo()
                            .frame(width: 80, height: 80)
                        
                        // Incognito indicator (only shown for incognito tabs)
                        if tab?.isIncognito == true {
                            incognitoIndicator
                        }
                    }
                    
                    // Main search bar
                    enhancedSearchBar
                        .frame(maxWidth: 600)
                    
                    // Quick access grid
                    quickAccessGrid
                        .frame(maxWidth: 800)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                
                Spacer()
            }
        }
        .background(adaptiveBackground)
        .onAppear {
            loadData()
            // Auto-focus search bar when new tab opens
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
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
    
    // MARK: - View Components
    private var incognitoIndicator: some View {
        HStack(spacing: 8) {
            // Small purple dot matching sidebar indicators
            Circle()
                .fill(.purple.opacity(0.8))
                .frame(width: 6, height: 6)
            
            Text("Incognito")
                .font(.system(.caption, weight: .medium))
                .foregroundColor(.purple.opacity(0.8))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.purple.opacity(0.1))
                .stroke(.purple.opacity(0.2), lineWidth: 0.5)
        )
        .opacity(0.8)
    }
    
    private var adaptiveBackground: some View {
        ZStack {
            // Base background
            Color.clear
            
            // Subtle gradient overlay
            LinearGradient(
                colors: [
                    Color.primary.opacity(0.01),
                    Color.primary.opacity(0.02),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Subtle ambient particles (next-gen minimal)
            FloatingParticlesView()
                .opacity(0.15)
        }
    }
    
    private var enhancedSearchBar: some View {
        HStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 16, weight: .medium))
            
            TextField("Search or enter website", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(.body, weight: .regular))
                .focused($isSearchFocused)
                .onSubmit {
                    performSearch()
                }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            ZStack {
                // Base background
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
                    .opacity(0.6)
                
                // Subtle glow effect when focused
                if isSearchFocused {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .blue.opacity(0.3),
                                    .purple.opacity(0.2),
                                    .blue.opacity(0.3)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                        .blur(radius: 0.5)
                }
                
                // Minimal border
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        Color(NSColor.separatorColor).opacity(isSearchHovered ? 0.3 : 0.15),
                        lineWidth: 0.5
                    )
            }
        )
        .scaleEffect(isSearchHovered || isSearchFocused ? 1.01 : 1.0)
        .animation(.easeInOut(duration: 0.15), 
                  value: isSearchHovered || isSearchFocused)
        .onHover { hovering in
            isSearchHovered = hovering
        }
    }
    
    
    private var quickAccessGrid: some View {
        HStack(spacing: 16) {
            MinimalActionCard(
                icon: "clock.arrow.circlepath",
                title: "Recently Visited"
            ) {
                KeyboardShortcutHandler.shared.showHistoryPanel = true
            }
            
            MinimalActionCard(
                icon: "arrow.uturn.left.circle",
                title: "Recently Closed"
            ) {
                KeyboardShortcutHandler.shared.showHistoryPanel = true
            }
            
            MinimalActionCard(
                icon: "star.fill",
                title: "Bookmarks"
            ) {
                KeyboardShortcutHandler.shared.showBookmarksPanel = true
            }
            
            MinimalActionCard(
                icon: "arrow.down.circle.fill",
                title: "Downloads"
            ) {
                KeyboardShortcutHandler.shared.showDownloadsPanel = true
            }
            
            MinimalActionCard(
                icon: "sparkles",
                title: "AI Assistant",
                isActive: isAISidebarExpanded
            ) {
                NotificationCenter.default.post(name: .toggleAISidebar, object: nil)
            }
        }
    }
    
    
    // MARK: - Methods
    private func loadData() {
        // Load recently visited sites (mock data for now)
        recentlyVisited = ["Apple.com", "GitHub.com", "Google.com", "Stack Overflow"]
        
        // Load recently closed tabs (mock data for now)
        recentlyClosed = ["Documentation", "Tutorial", "News Article"]
        
    }
    
    
    private func performSearch() {
        guard !searchText.isEmpty else { return }
        
        // Navigate to URL or perform search
        if isValidURL(searchText) {
            navigateToURL(searchText)
        } else {
            performGoogleSearch(searchText)
        }
        
        searchText = ""
        isSearchFocused = false
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
            // Navigate in current tab instead of creating new one
            NotificationCenter.default.post(
                name: .navigateCurrentTab,
                object: url
            )
        }
    }
    
    private func performGoogleSearch(_ query: String) {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://www.google.com/search?q=\(encodedQuery)") {
            NotificationCenter.default.post(
                name: .navigateCurrentTab,
                object: url
            )
        }
    }
}

// MARK: - Supporting Views

// Use AnimatedWebLogo from WebLogo.swift


struct FloatingParticlesView: View {
    @State private var particles: [Particle] = []
    
    struct Particle: Identifiable {
        let id = UUID()
        var position: CGPoint
        var velocity: CGVector
        var size: CGFloat
        var opacity: Double
        var color: Color
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(particles) { particle in
                    Circle()
                        .fill(particle.color)
                        .frame(width: particle.size, height: particle.size)
                        .opacity(particle.opacity)
                        .position(particle.position)
                }
            }
            .onAppear {
                generateParticles(in: geometry.size)
                startAnimation()
            }
        }
    }
    
    private func generateParticles(in size: CGSize) {
        particles = (0..<8).map { _ in
            Particle(
                position: CGPoint(
                    x: CGFloat.random(in: 0...size.width),
                    y: CGFloat.random(in: 0...size.height)
                ),
                velocity: CGVector(
                    dx: CGFloat.random(in: -0.15...0.15),
                    dy: CGFloat.random(in: -0.15...0.15)
                ),
                size: CGFloat.random(in: 1...2),
                opacity: Double.random(in: 0.08...0.15),
                color: [.blue.opacity(0.7), .purple.opacity(0.7), .mint.opacity(0.7)].randomElement() ?? .blue
            )
        }
    }
    
    private func startAnimation() {
        // CRITICAL FIX: Reduce animation frequency to prevent main thread saturation
        // Changed from 80ms (12.5 FPS) to 200ms (5 FPS) to reduce main thread load
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            // Remove withAnimation to reduce SwiftUI overhead during input handling
            for i in particles.indices {
                particles[i].position.x += particles[i].velocity.dx
                particles[i].position.y += particles[i].velocity.dy
                
                // Wrap around edges
                if particles[i].position.x < 0 { particles[i].position.x = 800 }
                if particles[i].position.x > 800 { particles[i].position.x = 0 }
                if particles[i].position.y < 0 { particles[i].position.y = 600 }
                if particles[i].position.y > 600 { particles[i].position.y = 0 }
            }
        }
    }
}


struct MinimalActionCard: View {
    let icon: String
    let title: String
    let action: () -> Void
    let isActive: Bool
    
    @State private var isHovered: Bool = false
    
    init(icon: String, title: String, isActive: Bool = false, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.action = action
        self.isActive = isActive
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isActive ? .accentColor : (isHovered ? .primary : .secondary))
                
                Text(title)
                    .font(.system(.caption2, weight: .medium))
                    .foregroundColor(isActive ? .accentColor : (isHovered ? .primary : .secondary))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .opacity(isHovered ? 1.0 : 0.8)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    NewTabView(tab: nil)
        .frame(width: 1200, height: 800)
}