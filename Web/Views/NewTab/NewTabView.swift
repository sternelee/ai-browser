import SwiftUI

// Enhanced new tab view with Web logo and next-gen design
struct NewTabView: View {
    @State private var searchText: String = ""
    @State private var quickNotes: String = ""
    @State private var showQuickNotes: Bool = false
    @State private var recentlyVisited: [String] = []
    @State private var recentlyClosed: [String] = []
    @State private var isNotesPreviewMode: Bool = true
    @FocusState private var isSearchFocused: Bool
    @State private var isSearchHovered: Bool = false
    
    var body: some View {
        GeometryReader { geometry in
            VStack {
                Spacer()
                
                VStack(spacing: 32) {
                    // App logo with subtle animation
                    AnimatedWebLogo()
                        .frame(width: 80, height: 80)
                    
                    // Main search bar
                    enhancedSearchBar
                        .frame(maxWidth: 600)
                    
                    // Quick access grid
                    quickAccessGrid
                        .frame(maxWidth: 800)
                    
                    // Quick notes section
                    quickNotesSection
                        .frame(maxWidth: 600)
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
        .onChange(of: quickNotes) {
            saveQuickNotes()
        }
    }
    
    // MARK: - View Components
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
                // Handle recently visited tap
            }
            
            MinimalActionCard(
                icon: "arrow.uturn.left.circle",
                title: "Recently Closed"
            ) {
                // Handle recently closed tap
            }
            
            MinimalActionCard(
                icon: "star.fill",
                title: "Bookmarks"
            ) {
                // Handle bookmarks tap
            }
            
            MinimalActionCard(
                icon: "arrow.down.circle.fill",
                title: "Downloads"
            ) {
                // Handle downloads tap
            }
        }
    }
    
    private var quickNotesSection: some View {
        VStack(spacing: 16) {
            // Quick notes toggle
            Button(action: { 
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showQuickNotes.toggle()
                }
            }) {
                HStack {
                    Image(systemName: "note.text")
                        .font(.system(size: 16, weight: .medium))
                    Text("Quick Notes")
                        .font(.system(.subheadline, weight: .medium))
                    Spacer()
                    Image(systemName: showQuickNotes ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                )
            }
            .buttonStyle(.plain)
            
            // Quick notes editor
            if showQuickNotes {
                QuickNotesEditor(notes: $quickNotes, isPreviewMode: $isNotesPreviewMode)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
    
    // MARK: - Methods
    private func loadData() {
        // Load recently visited sites (mock data for now)
        recentlyVisited = ["Apple.com", "GitHub.com", "Google.com", "Stack Overflow"]
        
        // Load recently closed tabs (mock data for now)
        recentlyClosed = ["Documentation", "Tutorial", "News Article"]
        
        // Load quick notes
        loadQuickNotes()
    }
    
    private func loadQuickNotes() {
        if let data = UserDefaults.standard.data(forKey: "quickNotes"),
           let notes = String(data: data, encoding: .utf8) {
            quickNotes = notes
        }
    }
    
    private func saveQuickNotes() {
        UserDefaults.standard.set(quickNotes.data(using: .utf8), forKey: "quickNotes")
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

struct QuickNotesEditor: View {
    @Binding var notes: String
    @Binding var isPreviewMode: Bool
    @State private var isEditing: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with mode toggle
            HStack {
                Text("Quick Notes")
                    .font(.system(.headline, weight: .semibold))
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button(action: { 
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isPreviewMode = true
                        }
                    }) {
                        Text("Preview")
                            .font(.system(.caption, weight: .medium))
                            .foregroundColor(isPreviewMode ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { 
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isPreviewMode = false
                        }
                    }) {
                        Text("Edit")
                            .font(.system(.caption, weight: .medium))
                            .foregroundColor(!isPreviewMode ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Content area
            Group {
                if isPreviewMode {
                    if notes.isEmpty {
                        Text("*No notes yet. Click edit to start writing.*")
                            .font(.system(.body))
                            .foregroundColor(.secondary)
                            .italic()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    } else {
                        // Simple text display for now
                        Text(notes)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    TextEditor(text: $notes)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .background(.clear)
                        .frame(minHeight: 120)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .strokeBorder(.primary.opacity(0.1), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: isPreviewMode)
    }
}

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
        Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
            withAnimation(.linear(duration: 0.08)) {
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
}


struct MinimalActionCard: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isHovered ? .primary : .secondary)
                
                Text(title)
                    .font(.system(.caption2, weight: .medium))
                    .foregroundColor(isHovered ? .primary : .secondary)
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
    NewTabView()
        .frame(width: 1200, height: 800)
}