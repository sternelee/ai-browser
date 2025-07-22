# Phase 3: Advanced Features - Detailed Implementation ✅ MOSTLY COMPLETED

## Overview
This phase implements advanced user experience features including the minimal new tab experience, smart contextual status bar, and performance optimizations that create a next-generation browsing experience.

## ✅ IMPLEMENTATION STATUS
- **New Tab Experience**: ✅ COMPLETED (with enhanced design and functionality)
- **Smart Status Bar**: ✅ COMPLETED (basic contextual functionality, missing advanced features)
- **Tab Hibernation**: ✅ COMPLETED (basic implementation, missing advanced memory pressure monitoring) 
- **GPU-Accelerated Scrolling**: ❌ NOT IMPLEMENTED
- **Advanced Hibernation Manager**: ❌ NOT IMPLEMENTED

## 1. New Tab Experience

### Minimal New Tab Experience
```swift
// NewTabView.swift - Beautiful minimal new tab experience
import SwiftUI
import MarkdownUI

struct NewTabView: View {
    @State private var searchText: String = ""
    @State private var recentlyVisited: [HistoryItem] = []
    @State private var recentlyClosed: [Tab] = []
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 32) {
                    Spacer()
                        .frame(height: geometry.size.height * 0.15)
                    
                    // App logo with subtle animation
                    AnimatedWebLogo()
                        .frame(width: 80, height: 80)
                    
                    // Main search bar
                    NewTabSearchBar(text: $searchText, isFocused: $isSearchFocused)
                        .frame(maxWidth: 600)
                    
                    // Quick access grid
                    quickAccessGrid
                        .frame(maxWidth: 800)
                    
                    
                    Spacer()
                        .frame(height: 100)
                }
                .padding(.horizontal, 24)
            }
        }
        .background(adaptiveBackground)
        .onAppear {
            loadData()
        }
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
            
            // Floating particles effect (very subtle)
            FloatingParticlesView()
                .opacity(0.3)
        }
    }
    
    private var quickAccessGrid: some View {
        VStack(spacing: 24) {
            HStack(spacing: 24) {
                QuickAccessCard(
                    title: "Recently Visited",
                    icon: "clock.arrow.circlepath",
                    items: recentlyVisited.prefix(4).map { $0.title }
                ) {
                    // Handle recently visited tap
                }
                
                QuickAccessCard(
                    title: "Recently Closed",
                    icon: "arrow.uturn.left.circle",
                    items: recentlyClosed.prefix(4).map { $0.title }
                ) {
                    // Handle recently closed tap
                }
            }
            
            HStack(spacing: 24) {
                BookmarksCard()
                DownloadsCard()
            }
        }
    }
    
    
    private func loadData() {
        // Load recently visited sites
        recentlyVisited = HistoryManager.shared.getRecentlyVisited(limit: 8)
        
        // Load recently closed tabs
        recentlyClosed = Array(TabManager.shared.recentlyClosedTabs.prefix(8))
        
    }
    
}

struct NewTabSearchBar: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    @State private var isHovered: Bool = false
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 18, weight: .medium))
            
            TextField("Search or enter website", text: $text)
                .textFieldStyle(.plain)
                .font(.system(.title3, weight: .regular))
                .focused(isFocused)
                .onSubmit {
                    performSearch()
                }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .strokeBorder(
                    strokeColor, 
                    lineWidth: 1
                )
                .shadow(
                    color: .black.opacity(0.05),
                    radius: isHovered || isFocused.wrappedValue ? 8 : 4,
                    x: 0,
                    y: 2
                )
        )
        .scaleEffect(isHovered || isFocused.wrappedValue ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), 
                  value: isHovered || isFocused.wrappedValue)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private var strokeColor: Color {
        if isFocused.wrappedValue {
            return .blue
        } else if isHovered {
            return .primary.opacity(0.2)
        } else {
            return .clear
        }
    }
    
    private func performSearch() {
        guard !text.isEmpty else { return }
        
        // Navigate to URL or perform search
        if isValidURL(text) {
            navigateToURL(text)
        } else {
            performGoogleSearch(text)
        }
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
            _ = TabManager.shared.createNewTab(url: url)
        }
    }
    
    private func performGoogleSearch(_ query: String) {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://www.google.com/search?q=\(encodedQuery)") {
            _ = TabManager.shared.createNewTab(url: url)
        }
    }
}


struct QuickAccessCard: View {
    let title: String
    let icon: String
    let items: [String]
    let onTap: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.blue)
                    
                    Text(title)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .opacity(isHovered ? 1 : 0)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(items.prefix(3), id: \.self) { item in
                        Text(item)
                            .font(.system(.caption))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    if items.count > 3 {
                        Text("and \(items.count - 3) more...")
                            .font(.system(.caption))
                            .foregroundColor(.tertiary)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.ultraThinMaterial)
                    .strokeBorder(.primary.opacity(isHovered ? 0.2 : 0.1), lineWidth: 1)
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
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
        particles = (0..<20).map { _ in
            Particle(
                position: CGPoint(
                    x: CGFloat.random(in: 0...size.width),
                    y: CGFloat.random(in: 0...size.height)
                ),
                velocity: CGVector(
                    dx: CGFloat.random(in: -0.5...0.5),
                    dy: CGFloat.random(in: -0.5...0.5)
                ),
                size: CGFloat.random(in: 2...4),
                opacity: Double.random(in: 0.1...0.3),
                color: [.blue, .purple, .pink, .mint].randomElement() ?? .blue
            )
        }
    }
    
    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in
            withAnimation(.linear(duration: 0.016)) {
                for i in particles.indices {
                    particles[i].position.x += particles[i].velocity.dx
                    particles[i].position.y += particles[i].velocity.dy
                    
                    // Wrap around edges
                    if particles[i].position.x < 0 { particles[i].position.x = UIScreen.main.bounds.width }
                    if particles[i].position.x > UIScreen.main.bounds.width { particles[i].position.x = 0 }
                    if particles[i].position.y < 0 { particles[i].position.y = UIScreen.main.bounds.height }
                    if particles[i].position.y > UIScreen.main.bounds.height { particles[i].position.y = 0 }
                }
            }
        }
    }
}
```

## 2. Smart Status Bar Implementation

### Dynamic Contextual Status Bar
```swift
// SmartStatusBar.swift - Context-aware floating status bar
import SwiftUI

struct SmartStatusBar: View {
    @ObservedObject var tab: Tab
    @State private var hoveredLink: URL?
    @State private var statusMessage: String = ""
    @State private var statusType: StatusType = .hidden
    @State private var progress: Double = 0
    @State private var contextualActions: [ContextualAction] = []
    
    enum StatusType {
        case hidden, loading, linkHover, download, security, error, success
    }
    
    struct ContextualAction {
        let icon: String
        let title: String
        let action: () -> Void
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Status icon with smooth animations
            statusIcon
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(statusColor)
                .scaleEffect(statusType == .loading ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: statusType)
            
            // Status text with typewriter effect for certain messages
            AnimatedText(text: statusMessage, shouldAnimate: statusType == .success)
                .font(.system(.caption, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
            
            Spacer()
            
            // Contextual actions
            if !contextualActions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(contextualActions.indices, id: \.self) { index in
                        let action = contextualActions[index]
                        Button(action: action.action) {
                            Image(systemName: action.icon)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(ContextualActionButtonStyle())
                        .help(action.title)
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }
            
            // Progress indicator with gradient animation
            if statusType == .loading || statusType == .download {
                ProgressView(value: progress)
                    .progressViewStyle(GradientProgressStyle())
                    .frame(width: 80)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(statusBarBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .opacity(statusType == .hidden ? 0 : 1)
        .offset(y: statusType == .hidden ? 10 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: statusType)
        .onReceive(tab.$isLoading) { isLoading in
            if isLoading {
                updateStatus(type: .loading, message: "Loading page...")
            } else {
                hideStatusWithDelay()
            }
        }
        .onReceive(tab.$estimatedProgress) { progress in
            self.progress = progress
        }
    }
    
    private var statusIcon: some View {
        Group {
            switch statusType {
            case .hidden:
                EmptyView()
            case .loading:
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(progress * 360))
            case .linkHover:
                Image(systemName: "link")
            case .download:
                Image(systemName: "arrow.down.circle")
            case .security:
                Image(systemName: "lock.shield")
            case .error:
                Image(systemName: "exclamationmark.triangle")
            case .success:
                Image(systemName: "checkmark.circle")
            }
        }
    }
    
    private var statusBarBackground: some View {
        ZStack {
            // Base material
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
            
            // Dynamic color overlay based on status type
            RoundedRectangle(cornerRadius: 8)
                .fill(statusOverlayColor.opacity(0.1))
                .animation(.easeInOut(duration: 0.3), value: statusType)
        }
    }
    
    private var statusColor: Color {
        switch statusType {
        case .hidden, .loading, .linkHover:
            return .primary
        case .download:
            return .blue
        case .security, .success:
            return .green
        case .error:
            return .red
        }
    }
    
    private var statusOverlayColor: Color {
        switch statusType {
        case .download:
            return .blue
        case .security, .success:
            return .green
        case .error:
            return .red
        default:
            return .clear
        }
    }
    
    // MARK: - Public Methods
    func showLinkHover(_ url: URL) {
        hoveredLink = url
        let host = url.host ?? url.absoluteString
        updateStatus(type: .linkHover, message: host)
        
        // Add contextual actions for links
        contextualActions = [
            ContextualAction(icon: "doc.on.doc", title: "Copy Link") {
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            },
            ContextualAction(icon: "safari", title: "Open in Safari") {
                NSWorkspace.shared.open(url)
            }
        ]
    }
    
    func hideLinkHover() {
        hoveredLink = nil
        contextualActions = []
        hideStatusWithDelay()
    }
    
    func showDownload(filename: String, progress: Double) {
        self.progress = progress
        updateStatus(type: .download, message: "Downloading \(filename)")
        
        // Add download-specific actions
        contextualActions = [
            ContextualAction(icon: "folder", title: "Show in Finder") {
                // Open downloads folder
            },
            ContextualAction(icon: "pause", title: "Pause Download") {
                // Pause download
            }
        ]
    }
    
    func showSecurity(message: String) {
        updateStatus(type: .security, message: message)
        
        contextualActions = [
            ContextualAction(icon: "info.circle", title: "Security Details") {
                // Show security details
            }
        ]
    }
    
    func showError(message: String) {
        updateStatus(type: .error, message: message)
        
        contextualActions = [
            ContextualAction(icon: "arrow.clockwise", title: "Retry") {
                // Retry action
            }
        ]
    }
    
    func showSuccess(message: String) {
        updateStatus(type: .success, message: message)
        hideStatusWithDelay(delay: 2.0)
    }
    
    // MARK: - Private Methods
    private func updateStatus(type: StatusType, message: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            statusType = type
            statusMessage = message
        }
    }
    
    private func hideStatusWithDelay(delay: TimeInterval = 3.0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.easeOut(duration: 0.3)) {
                statusType = .hidden
                contextualActions = []
            }
        }
    }
}

struct AnimatedText: View {
    let text: String
    let shouldAnimate: Bool
    @State private var visibleCount: Int = 0
    
    var body: some View {
        Text(String(text.prefix(visibleCount)))
            .onAppear {
                if shouldAnimate {
                    animateText()
                } else {
                    visibleCount = text.count
                }
            }
            .onChange(of: text) { newText in
                if shouldAnimate {
                    visibleCount = 0
                    animateText()
                } else {
                    visibleCount = newText.count
                }
            }
    }
    
    private func animateText() {
        let characters = Array(text)
        
        for index in 0..<characters.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.05) {
                withAnimation(.easeInOut(duration: 0.1)) {
                    visibleCount = index + 1
                }
            }
        }
    }
}

struct ContextualActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(4)
            .background(
                Circle()
                    .fill(.quaternary)
                    .opacity(configuration.isPressed ? 0.8 : 1.0)
            )
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// Custom gradient progress style
struct GradientProgressStyle: ProgressViewStyle {
    @State private var gradientOffset: CGFloat = -1
    
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 2)
                    .fill(.quaternary)
                    .frame(height: 4)
                
                // Progress with animated gradient
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple, .pink],
                            startPoint: UnitPoint(x: gradientOffset, y: 0),
                            endPoint: UnitPoint(x: gradientOffset + 0.3, y: 0)
                        )
                    )
                    .frame(
                        width: geometry.size.width * (configuration.fractionCompleted ?? 0),
                        height: 4
                    )
                    .animation(.easeInOut(duration: 0.2), value: configuration.fractionCompleted)
                    .onAppear {
                        withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                            gradientOffset = 1
                        }
                    }
            }
        }
    }
}
```

## 3. Performance Features

### GPU-Accelerated Smooth Scrolling
```swift
// SmoothScrollingWebView.swift - Physics-based scrolling like iOS Safari
import SwiftUI
import WebKit

class SmoothScrollingWebView: WKWebView {
    private var scrollVelocity: CGPoint = .zero
    private var lastScrollTime: CFTimeInterval = 0
    private var scrollDecelerationTimer: Timer?
    private var momentumScrolling: Bool = false
    
    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        setupSmoothScrolling()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupSmoothScrolling()
    }
    
    private func setupSmoothScrolling() {
        // Enable GPU acceleration and optimization
        wantsLayer = true
        layer?.drawsAsynchronously = true
        layer?.shouldRasterize = false // Better for scrolling
        
        // Configure for optimal scrolling performance
        scrollView.delegate = self
        scrollView.decelerationRate = UIScrollView.DecelerationRate.fast
        
        // Inject enhanced JavaScript for ultra-smooth scrolling
        let smoothScrollScript = generateSmoothScrollScript()
        let script = WKUserScript(source: smoothScrollScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        configuration.userContentController.addUserScript(script)
        
        // Setup momentum scrolling
        setupMomentumScrolling()
    }
    
    private func generateSmoothScrollScript() -> String {
        return """
        (function() {
            let isScrolling = false;
            let scrollTimeout;
            let lastScrollTime = Date.now();
            let scrollVelocity = 0;
            
            // Enhanced easing functions
            const easing = {
                easeOutCubic: function(t) {
                    return 1 - Math.pow(1 - t, 3);
                },
                easeInOutQuart: function(t) {
                    return t < 0.5 ? 8 * t * t * t * t : 1 - 8 * (--t) * t * t * t;
                },
                springEasing: function(t) {
                    return 1 - Math.exp(-6 * t) * Math.cos(10 * t);
                }
            };
            
            function smoothScroll(element, deltaY, duration = 400) {
                if (!element) return;
                
                const start = element.scrollTop;
                const change = deltaY;
                const startTime = Date.now();
                
                function animateScroll() {
                    const elapsed = Date.now() - startTime;
                    const progress = Math.min(elapsed / duration, 1);
                    
                    // Use spring easing for natural feel
                    const easedProgress = easing.springEasing(progress);
                    const currentScroll = start + (change * easedProgress);
                    
                    element.scrollTop = currentScroll;
                    
                    if (progress < 1) {
                        requestAnimationFrame(animateScroll);
                    }
                }
                
                requestAnimationFrame(animateScroll);
            }
            
            // Enhanced wheel event handling
            function handleWheel(e) {
                e.preventDefault();
                
                const now = Date.now();
                const deltaTime = now - lastScrollTime;
                const element = document.documentElement || document.body;
                
                // Calculate velocity for momentum
                scrollVelocity = e.deltaY / Math.max(deltaTime, 16);
                lastScrollTime = now;
                
                // Smooth scroll with physics-based scaling
                const scrollDistance = e.deltaY * 2.5;
                const dynamicDuration = Math.min(400, Math.max(200, Math.abs(scrollDistance) * 0.8));
                
                smoothScroll(element, scrollDistance, dynamicDuration);
                
                // Clear existing timeout
                clearTimeout(scrollTimeout);
                
                // Set new timeout for momentum
                scrollTimeout = setTimeout(() => {
                    if (Math.abs(scrollVelocity) > 0.1) {
                        const momentumDistance = scrollVelocity * 200;
                        smoothScroll(element, momentumDistance, 600);
                    }
                }, 100);
            }
            
            // Attach enhanced wheel listener
            document.addEventListener('wheel', handleWheel, { passive: false });
            
            // Touch scrolling for trackpad gestures
            let touchStartY = 0;
            let touchVelocity = 0;
            
            document.addEventListener('touchstart', function(e) {
                touchStartY = e.touches[0].clientY;
            }, { passive: true });
            
            document.addEventListener('touchmove', function(e) {
                const touchY = e.touches[0].clientY;
                const deltaY = touchStartY - touchY;
                touchVelocity = deltaY * 0.5;
                
                const element = document.documentElement || document.body;
                smoothScroll(element, deltaY, 200);
                
                touchStartY = touchY;
            }, { passive: true });
            
            document.addEventListener('touchend', function(e) {
                if (Math.abs(touchVelocity) > 5) {
                    const element = document.documentElement || document.body;
                    const momentumDistance = touchVelocity * 10;
                    smoothScroll(element, momentumDistance, 800);
                }
            }, { passive: true });
            
            // Page visibility optimization
            document.addEventListener('visibilitychange', function() {
                if (document.hidden) {
                    clearTimeout(scrollTimeout);
                }
            });
            
        })();
        """
    }
    
    private func setupMomentumScrolling() {
        // Add gesture recognizers for enhanced scrolling
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        panGesture.delegate = self
        addGestureRecognizer(panGesture)
    }
    
    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        let velocity = gesture.velocity(in: self)
        let translation = gesture.translation(in: self)
        
        switch gesture.state {
        case .began:
            scrollDecelerationTimer?.invalidate()
            momentumScrolling = false
            
        case .changed:
            // Track velocity for momentum calculation
            scrollVelocity = CGPoint(x: velocity.x, y: velocity.y)
            
        case .ended, .cancelled:
            // Apply momentum scrolling if velocity is significant
            if abs(velocity.y) > 500 {
                startMomentumScrolling(initialVelocity: velocity.y)
            }
            
        default:
            break
        }
    }
    
    private func startMomentumScrolling(initialVelocity: CGFloat) {
        momentumScrolling = true
        var currentVelocity = initialVelocity
        let decelerationRate: CGFloat = 0.95
        let minVelocity: CGFloat = 50
        
        scrollDecelerationTimer = Timer.scheduledTimer(withTimeInterval: 1/120.0, repeats: true) { [weak self] timer in
            guard let self = self, self.momentumScrolling else {
                timer.invalidate()
                return
            }
            
            // Apply deceleration
            currentVelocity *= decelerationRate
            
            // Stop if velocity is too low
            if abs(currentVelocity) < minVelocity {
                timer.invalidate()
                self.momentumScrolling = false
                return
            }
            
            // Apply scroll offset with smooth animation
            let scrollDelta = currentVelocity / 60.0 // Convert to per-frame
            let currentOffset = self.scrollView.contentOffset
            let newOffset = CGPoint(
                x: currentOffset.x,
                y: currentOffset.y + scrollDelta
            )
            
            // Ensure we don't scroll beyond bounds
            let maxY = max(0, self.scrollView.contentSize.height - self.scrollView.bounds.height)
            let clampedY = max(0, min(maxY, newOffset.y))
            
            if clampedY != currentOffset.y {
                self.scrollView.setContentOffset(CGPoint(x: newOffset.x, y: clampedY), animated: false)
            } else {
                // Hit bounds, stop momentum
                timer.invalidate()
                self.momentumScrolling = false
            }
        }
    }
}

extension SmoothScrollingWebView: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // Track scroll velocity for enhanced momentum
        let currentTime = CACurrentMediaTime()
        let deltaTime = currentTime - lastScrollTime
        
        if deltaTime > 0 {
            let deltaY = scrollView.contentOffset.y - scrollVelocity.y
            scrollVelocity.y = deltaY / CGFloat(deltaTime)
        }
        
        lastScrollTime = currentTime
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // Cancel any ongoing momentum scrolling
        scrollDecelerationTimer?.invalidate()
        momentumScrolling = false
    }
    
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate && !momentumScrolling {
            startMomentumScrolling(initialVelocity: scrollVelocity.y * 100)
        }
    }
}

extension SmoothScrollingWebView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
```

## 4. Tab Hibernation System

### Memory-Efficient Tab Management
```swift
// TabHibernationManager.swift - Advanced tab hibernation for memory efficiency
import SwiftUI
import WebKit

class TabHibernationManager: ObservableObject {
    static let shared = TabHibernationManager()
    
    @Published var hibernatedTabs: Set<UUID> = []
    @Published var memoryPressureLevel: MemoryPressureLevel = .normal
    
    private let memoryThresholdMB: Int64 = 500 // 500MB threshold
    private let hibernationDelay: TimeInterval = 300 // 5 minutes
    private var memoryMonitorTimer: Timer?
    private var hibernationTimers: [UUID: Timer] = [:]
    
    enum MemoryPressureLevel {
        case normal, warning, critical
    }
    
    init() {
        startMemoryMonitoring()
        setupMemoryPressureSource()
    }
    
    // MARK: - Memory Monitoring
    private func startMemoryMonitoring() {
        memoryMonitorTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.checkMemoryPressure()
        }
    }
    
    private func checkMemoryPressure() {
        let memoryUsage = getCurrentMemoryUsage()
        
        let newPressureLevel: MemoryPressureLevel
        if memoryUsage > memoryThresholdMB * 2 {
            newPressureLevel = .critical
        } else if memoryUsage > memoryThresholdMB {
            newPressureLevel = .warning
        } else {
            newPressureLevel = .normal
        }
        
        if newPressureLevel != memoryPressureLevel {
            memoryPressureLevel = newPressureLevel
            handleMemoryPressureChange()
        }
    }
    
    private func getCurrentMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return result == KERN_SUCCESS ? Int64(info.resident_size) / 1024 / 1024 : 0
    }
    
    private func setupMemoryPressureSource() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: .all, queue: .main)
        
        source.setEventHandler { [weak self] in
            let event = source.mask
            
            if event.contains(.critical) {
                self?.memoryPressureLevel = .critical
                self?.handleMemoryPressureChange()
            } else if event.contains(.warning) {
                self?.memoryPressureLevel = .warning
                self?.handleMemoryPressureChange()
            }
        }
        
        source.resume()
    }
    
    private func handleMemoryPressureChange() {
        switch memoryPressureLevel {
        case .critical:
            hibernateOldestInactiveTabs(count: 5)
        case .warning:
            hibernateOldestInactiveTabs(count: 2)
        case .normal:
            // Don't force hibernation, let natural timers handle it
            break
        }
    }
    
    // MARK: - Tab Hibernation
    func scheduleHibernation(for tab: Tab) {
        // Cancel existing timer
        hibernationTimers[tab.id]?.invalidate()
        
        // Schedule new hibernation timer
        let timer = Timer.scheduledTimer(withTimeInterval: hibernationDelay, repeats: false) { [weak self] _ in
            self?.hibernateTab(tab)
        }
        
        hibernationTimers[tab.id] = timer
    }
    
    func cancelHibernation(for tab: Tab) {
        hibernationTimers[tab.id]?.invalidate()
        hibernationTimers.removeValue(forKey: tab.id)
    }
    
    func hibernateTab(_ tab: Tab) {
        guard !tab.isActive && !tab.isHibernated else { return }
        
        // Create snapshot before hibernating
        createTabSnapshot(tab) { [weak self] snapshot in
            DispatchQueue.main.async {
                tab.snapshot = snapshot
                tab.hibernate()
                self?.hibernatedTabs.insert(tab.id)
                
                // Clean up timer
                self?.hibernationTimers.removeValue(forKey: tab.id)
                
                print("Hibernated tab: \(tab.title)")
            }
        }
    }
    
    func wakeUpTab(_ tab: Tab) {
        guard tab.isHibernated else { return }
        
        tab.wakeUp()
        hibernatedTabs.remove(tab.id)
        
        // Recreate WebView when needed
        NotificationCenter.default.post(
            name: .recreateWebView,
            object: tab
        )
        
        print("Woke up tab: \(tab.title)")
    }
    
    private func hibernateOldestInactiveTabs(count: Int) {
        let inactiveTabs = TabManager.shared.tabs
            .filter { !$0.isActive && !$0.isHibernated }
            .sorted { $0.lastAccessed < $1.lastAccessed }
        
        for tab in inactiveTabs.prefix(count) {
            hibernateTab(tab)
        }
    }
    
    // MARK: - Snapshot Generation
    private func createTabSnapshot(_ tab: Tab, completion: @escaping (NSImage?) -> Void) {
        guard let webView = tab.webView else {
            completion(nil)
            return
        }
        
        let config = WKSnapshotConfiguration()
        config.rect = webView.bounds
        config.snapshotWidth = NSNumber(value: 300) // Thumbnail size
        
        webView.takeSnapshot(with: config) { image, error in
            if let error = error {
                print("Snapshot error: \(error)")
                completion(nil)
            } else {
                completion(image)
            }
        }
    }
    
    deinit {
        memoryMonitorTimer?.invalidate()
        hibernationTimers.values.forEach { $0.invalidate() }
    }
}

// Extension for notification names
extension Notification.Name {
    static let recreateWebView = Notification.Name("recreateWebView")
    static let memoryPressureChanged = Notification.Name("memoryPressureChanged")
}
```

## Implementation Notes

### Advanced Features
- **Typewriter text animation**: Smooth character-by-character text appearance
- **Floating particles**: Subtle background animation for visual appeal
- **Contextual status actions**: Smart actions based on current status
- **Physics-based scrolling**: 120fps smooth scrolling with momentum
- **Memory pressure monitoring**: Intelligent tab hibernation based on system resources

### Performance Optimizations
- GPU-accelerated rendering for all animations
- Efficient snapshot generation for hibernated tabs
- Memory pressure detection and response
- Optimized JavaScript injection for scrolling

### Next Phase
Phase 4 will implement security and privacy features including the native ad blocker and password manager.