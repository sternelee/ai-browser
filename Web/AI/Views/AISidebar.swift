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
            
            Divider()
                .opacity(0.3)
            
            // Input area
            chatInputArea()
        }
        .padding(16)
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
        .frame(height: 32)
    }
    
    // MARK: - Chat Messages Area
    
    @ViewBuilder
    private func chatMessagesArea() -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
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
                .padding(.vertical, 12)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if aiAssistant.isInitialized {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    ProgressView()
                        .scaleEffect(0.8)
                }
                
                Text(aiAssistant.initializationStatus)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
            }
            
            if let error = aiAssistant.lastError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .padding(.leading, 24)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .opacity(0.5)
        )
    }
    
    @ViewBuilder
    private func chatMessagesPlaceholder() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Assistant Ready")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
            
            Text("Start a conversation or ask about your current browsing session.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .opacity(0.3)
        )
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
        .frame(height: 44)
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
    
    var body: some View {
        HStack(spacing: 6) {
            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .overlay(
                    // Processing animation
                    Circle()
                        .stroke(statusColor, lineWidth: 1)
                        .scaleEffect(isProcessing ? 1.5 : 1.0)
                        .opacity(isProcessing ? 0 : 1)
                        .animation(
                            isProcessing ? 
                                .easeInOut(duration: 1.0).repeatForever(autoreverses: false) : 
                                .default,
                            value: isProcessing
                        )
                )
            
            // Status text
            Text(isProcessing ? "Processing..." : (isInitialized ? "AI Ready" : "Initializing..."))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
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