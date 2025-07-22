import SwiftUI
import Combine

/// AI Assistant sidebar with collapsible right panel interface
/// Provides context-aware chat with glass morphism styling
struct AISidebar: View {
    @StateObject private var aiAssistant = AIAssistant()
    @State private var isExpanded: Bool = false
    @State private var chatInput: String = ""
    @State private var isHovering: Bool = false
    @State private var autoCollapseTimer: Timer?
    @FocusState private var isChatInputFocused: Bool
    
    // OPTIMIZATION: Fix initialization spinner animation
    @State private var initSpinnerRotation: Double = 0
    
    // Configuration
    private let collapsedWidth: CGFloat = 4
    private let expandedWidth: CGFloat = 320
    private let maxExpandedWidth: CGFloat = 480
    private let autoCollapseDelay: TimeInterval = 30.0
    
    var body: some View {
        HStack(spacing: 0) {
            // Main sidebar content
            sidebarContent()
                .frame(width: isExpanded ? expandedWidth : collapsedWidth)
                .background(sidebarBackground())
                .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 12 : 2))
                .overlay(
                    // Right edge activation zone when collapsed
                    rightEdgeActivationZone()
                )
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
                .onHover { hovering in
                    handleHover(hovering)
                }
                .onReceive(NotificationCenter.default.publisher(for: .toggleAISidebar)) { _ in
                    toggleSidebar()
                }
                .onReceive(NotificationCenter.default.publisher(for: .focusAIInput)) { _ in
                    expandAndFocusInput()
                }
                .onAppear {
                    // Initialize AI system on first appearance
                    Task {
                        await aiAssistant.initialize()
                    }
                }
        }
    }
    
    // MARK: - Sidebar Content
    
    @ViewBuilder
    private func sidebarContent() -> some View {
        if isExpanded {
            expandedSidebarView()
        } else {
            collapsedSidebarView()
        }
    }
    
    @ViewBuilder
    private func collapsedSidebarView() -> some View {
        // Minimal collapsed state with subtle indicator
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.1),
                        Color.accentColor.opacity(0.05)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: collapsedWidth)
    }
    
    @ViewBuilder 
    private func expandedSidebarView() -> some View {
        VStack(spacing: 0) {
            // Header with AI status
            sidebarHeader()
            
            Divider()
                .opacity(0.3)
            
            // Chat messages area
            chatMessagesArea()
            
            // Input area
            chatInputArea()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // MARK: - Header
    
    @ViewBuilder
    private func sidebarHeader() -> some View {
        HStack {
            // AI status indicator
            AIStatusIndicator(
                isInitialized: aiAssistant.isInitialized,
                isProcessing: aiAssistant.isProcessing,
                status: aiAssistant.initializationStatus
            )
            
            Spacer()
            
            // Collapse button
            Button(action: {
                collapseSidebar()
            }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .opacity(0.7)
            .onHover { hovering in
                // Reset auto-collapse timer on interaction
                resetAutoCollapseTimer()
            }
        }
        .frame(height: 40)
        .padding(.bottom, 8)
    }
    
    // MARK: - Chat Messages Area
    
    @ViewBuilder
    private func chatMessagesArea() -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if !aiAssistant.isInitialized {
                        // Initialization status
                        aiInitializationView()
                    } else if aiAssistant.messages.isEmpty {
                        // Show placeholder when no messages
                        chatMessagesPlaceholder()
                    } else {
                        // Display actual chat messages
                        ForEach(aiAssistant.messages) { message in
                            ChatBubbleView(message: message)
                                .id(message.id)
                        }
                    }
                }
                .padding(.vertical, 16)
            }
            .onReceive(aiAssistant.$isProcessing) { _ in
                // Auto-scroll to bottom when new messages arrive
                if let lastMessage = aiAssistant.messages.last {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private func aiInitializationView() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Modern loading header
            HStack(spacing: 12) {
                ZStack {
                    if aiAssistant.isInitialized {
                        // Success state
                        Circle()
                            .fill(.green.opacity(0.1))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.green)
                            )
                    } else {
                        // Loading state with subtle animation
                        Circle()
                            .fill(.blue.opacity(0.08))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle()
                                    .trim(from: 0, to: 0.7)
                                    .stroke(
                                        LinearGradient(
                                            colors: [.blue.opacity(0.8), .blue.opacity(0.3)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                                    )
                                    .rotationEffect(.degrees(initSpinnerRotation))
                                    .onAppear {
                                        if !aiAssistant.isInitialized {
                                            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                                                initSpinnerRotation = 360
                                            }
                                        }
                                    }
                                    .onChange(of: aiAssistant.isInitialized) { _, isInitialized in
                                        if !isInitialized {
                                            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                                                initSpinnerRotation = 360
                                            }
                                        } else {
                                            withAnimation(.easeOut(duration: 0.5)) {
                                                initSpinnerRotation = 0
                                            }
                                        }
                                    }
                            )
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(aiAssistant.isInitialized ? "AI Ready" : "Preparing AI")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text(aiAssistant.initializationStatus)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
            }
            
            // Progress indicator for non-initialized state
            if !aiAssistant.isInitialized {
                VStack(spacing: 8) {
                    // Subtle progress bar
                    HStack(spacing: 4) {
                        ForEach(0..<4, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(.blue.opacity(progressDotOpacity(for: index)))
                                .frame(width: 24, height: 2)
                                .animation(
                                    .easeInOut(duration: 0.8)
                                        .repeatForever(autoreverses: true)
                                        .delay(Double(index) * 0.2),
                                    value: aiAssistant.isInitialized
                                )
                        }
                    }
                    
                    Text("Downloading and optimizing model...")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            
            if let error = aiAssistant.lastError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                    
                    Text(error)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.leading)
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.quaternary, lineWidth: 0.5)
                )
        )
    }
    
    private func progressDotOpacity(for index: Int) -> Double {
        let time = Date().timeIntervalSince1970
        let offset = Double(index) * 0.5
        return 0.3 + 0.7 * abs(sin(time * 2 + offset))
    }
    
    @ViewBuilder
    private func chatMessagesPlaceholder() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.green.opacity(0.2), .green.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "brain")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.green)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Ready")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text("Local AI • Private & Secure")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Ask me anything about:")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                
                VStack(alignment: .leading, spacing: 4) {
                    suggestionRow(icon: "doc.text", text: "Current page content")
                    suggestionRow(icon: "clock", text: "Browsing history")
                    suggestionRow(icon: "magnifyingglass", text: "Web search help")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.quaternary, lineWidth: 0.5)
                )
        )
    }
    
    @ViewBuilder
    private func suggestionRow(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary.opacity(0.6))
                .frame(width: 12)
            
            Text(text)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Chat Input Area
    
    @ViewBuilder
    private func chatInputArea() -> some View {
        HStack(spacing: 8) {
            TextField("Ask about this page...", text: $chatInput, axis: .vertical)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 14))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .opacity(0.6)
                )
                .focused($isChatInputFocused)
                .onSubmit {
                    sendMessage()
                }
                .disabled(!aiAssistant.isInitialized)
            
            // Send button
            Button(action: {
                sendMessage()
            }) {
                Image(systemName: aiAssistant.isProcessing ? "stop.circle" : "arrow.up.circle.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(chatInput.isEmpty ? .secondary : .accentColor)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(chatInput.isEmpty || !aiAssistant.isInitialized)
        }
        .frame(minHeight: 44)
        .padding(.top, 12)
        .onTapGesture {
            // Reset auto-collapse timer on interaction
            resetAutoCollapseTimer()
        }
    }
    
    // MARK: - Background Styling
    
    @ViewBuilder
    private func sidebarBackground() -> some View {
        ZStack {
            // Base glass material
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.8)
            
            // Subtle gradient overlay
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.02),
                            Color.accentColor.opacity(0.01),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Inner glow
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.02),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }
    
    // MARK: - Right Edge Activation Zone
    
    @ViewBuilder
    private func rightEdgeActivationZone() -> some View {
        if !isExpanded {
            HStack {
                Spacer()
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 20) // 20pt hover zone
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering {
                            expandSidebar()
                        }
                    }
            }
        }
    }
    
    // MARK: - Interaction Methods
    
    private func toggleSidebar() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isExpanded.toggle()
        }
        
        if isExpanded {
            startAutoCollapseTimer()
            // Focus input after animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                isChatInputFocused = true
            }
        } else {
            stopAutoCollapseTimer()
            isChatInputFocused = false
        }
    }
    
    private func expandSidebar() {
        guard !isExpanded else { return }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isExpanded = true
        }
        
        startAutoCollapseTimer()
        
        // Focus input after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isChatInputFocused = true
        }
    }
    
    private func collapseSidebar() {
        guard isExpanded else { return }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isExpanded = false
        }
        
        stopAutoCollapseTimer()
        isChatInputFocused = false
    }
    
    private func expandAndFocusInput() {
        expandSidebar()
    }
    
    private func handleHover(_ hovering: Bool) {
        isHovering = hovering
        
        if hovering && isExpanded {
            // Reset auto-collapse timer when hovering over expanded sidebar
            resetAutoCollapseTimer()
        }
    }
    
    private func sendMessage() {
        guard !chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let message = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        chatInput = ""
        
        // Reset auto-collapse timer on interaction
        resetAutoCollapseTimer()
        
        // Process message with AI Assistant
        Task {
            do {
                let _ = try await aiAssistant.processQuery(message, includeContext: true)
                // UI updates will be handled by ChatBubbleView in next phase
            } catch {
                NSLog("❌ Chat message processing failed: \(error)")
            }
        }
    }
    
    // MARK: - Auto-collapse Timer Management
    
    private func startAutoCollapseTimer() {
        stopAutoCollapseTimer()
        autoCollapseTimer = Timer.scheduledTimer(withTimeInterval: autoCollapseDelay, repeats: false) { _ in
            if isExpanded && !isHovering && !isChatInputFocused {
                collapseSidebar()
            }
        }
    }
    
    private func resetAutoCollapseTimer() {
        if isExpanded {
            startAutoCollapseTimer()
        }
    }
    
    private func stopAutoCollapseTimer() {
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = nil
    }
}

// MARK: - AI Status Indicator Component

struct AIStatusIndicator: View {
    let isInitialized: Bool
    let isProcessing: Bool
    let status: String
    
    // OPTIMIZATION: Fix spinner animation with proper state management
    @State private var rotationAngle: Double = 0
    
    var body: some View {
        HStack(spacing: 8) {
            // Modern status indicator
            ZStack {
                // Background circle
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 20, height: 20)
                
                // Status dot or processing indicator
                if isProcessing {
                    // FIXED: Elegant processing animation with proper state binding
                    Circle()
                        .trim(from: 0, to: 0.6)
                        .stroke(
                            AngularGradient(
                                colors: [statusColor.opacity(0.3), statusColor],
                                center: .center,
                                startAngle: .degrees(0),
                                endAngle: .degrees(360)
                            ),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .frame(width: 12, height: 12)
                        .rotationEffect(.degrees(rotationAngle))
                        .onAppear {
                            // Start continuous rotation when processing begins
                            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                                rotationAngle = 360
                            }
                        }
                        .onChange(of: isProcessing) { _, newValue in
                            if newValue {
                                // Start spinning when processing begins
                                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                                    rotationAngle = 360
                                }
                            } else {
                                // Stop spinning when processing ends
                                withAnimation(.easeOut(duration: 0.5)) {
                                    rotationAngle = 0
                                }
                            }
                        }
                } else {
                    // Solid status dot
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [statusColor, statusColor.opacity(0.8)],
                                center: .topLeading,
                                startRadius: 2,
                                endRadius: 8
                            )
                        )
                        .frame(width: 8, height: 8)
                        .scaleEffect(isInitialized ? 1.0 : 0.8)
                        .animation(.easeInOut(duration: 0.3), value: isInitialized)
                }
                
                // Pulse effect for ready state
                if isInitialized && !isProcessing {
                    Circle()
                        .stroke(statusColor.opacity(0.4), lineWidth: 1)
                        .frame(width: 16, height: 16)
                        .scaleEffect(1.2)
                        .opacity(0)
                        .animation(
                            .easeOut(duration: 2.0).repeatForever(autoreverses: false),
                            value: isInitialized
                        )
                        .onAppear {
                            withAnimation {
                                // Trigger pulse animation
                            }
                        }
                }
            }
            
            VStack(alignment: .leading, spacing: 1) {
                // Primary status
                Text(statusText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                
                // Secondary status
                if !status.isEmpty && status != statusText {
                    Text(status)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
    
    private var statusText: String {
        if isProcessing {
            return "Thinking..."  // OPTIMIZATION: Better user feedback
        } else if isInitialized {
            return "AI Ready"
        } else {
            return "Starting"
        }
    }
    
    private var statusColor: Color {
        if isProcessing {
            return .blue
        } else if isInitialized {
            return .green
        } else {
            return .orange
        }
    }
}

// MARK: - Notification Extensions
// Note: AI Assistant notification names are defined in WebApp.swift

// MARK: - Preview

#Preview {
    HStack {
        Rectangle()
            .fill(.gray.opacity(0.3))
            .frame(maxWidth: .infinity)
        
        AISidebar()
    }
    .frame(width: 800, height: 600)
}