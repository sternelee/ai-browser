import SwiftUI

/// Individual chat message bubble for AI conversations
/// Supports both user and assistant messages with contextual styling
struct ChatBubbleView: View {
    let message: ConversationMessage
    let isStreaming: Bool
    let streamingText: String
    
    // Computed properties
    private var isUserMessage: Bool {
        message.role == .user
    }
    
    private var displayText: String {
        if isStreaming && !isUserMessage {
            return streamingText
        }
        return message.content
    }
    
    // Configuration
    private let maxBubbleWidth: CGFloat = 280
    private let bubblePadding: CGFloat = 12
    private let bubbleSpacing: CGFloat = 8
    
    init(message: ConversationMessage, isStreaming: Bool = false, streamingText: String = "") {
        self.message = message
        self.isStreaming = isStreaming
        self.streamingText = streamingText
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: bubbleSpacing) {
            if isUserMessage {
                Spacer(minLength: 40) // Right-align user messages
                userMessageBubble()
            } else {
                assistantMessageBubble()
                Spacer(minLength: 40) // Left-align assistant messages
            }
        }
        .padding(.horizontal, 4)
        .animation(.easeInOut(duration: 0.2), value: displayText)
    }
    
    // MARK: - User Message Bubble
    
    @ViewBuilder
    private func userMessageBubble() -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(alignment: .bottom, spacing: 6) {
                // Message content
                Text(displayText)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, bubblePadding)
                    .padding(.vertical, 10)
                    .background(userBubbleBackground())
                    .clipShape(ChatBubbleShape(isUserMessage: true))
                
                // User avatar
                userAvatar()
            }
            
            // Timestamp
            messageTimestamp()
        }
    }
    
    @ViewBuilder
    private func userBubbleBackground() -> some View {
        ZStack {
            // Primary blue gradient
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.9),
                    Color.accentColor.opacity(0.7)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Subtle highlight
            LinearGradient(
                colors: [
                    Color.white.opacity(0.15),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    @ViewBuilder
    private func userAvatar() -> some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.3),
                        Color.accentColor.opacity(0.1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 24, height: 24)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.accentColor)
            )
    }
    
    // MARK: - Assistant Message Bubble
    
    @ViewBuilder
    private func assistantMessageBubble() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 6) {
                // AI avatar
                aiAvatar()
                
                // Message content
                VStack(alignment: .leading, spacing: 0) {
                    messageContentView()
                    
                    // Context references (if any)
                    if let contextData = message.contextData, !contextData.isEmpty {
                        contextReferences()
                    }
                }
            }
            
            // Timestamp and metadata
            HStack(spacing: 8) {
                messageTimestamp()
                
                if let metadata = message.metadata {
                    messageMetadata(metadata)
                }
            }
        }
    }
    
    @ViewBuilder
    private func messageContentView() -> some View {
        Text(displayText)
            .font(.system(size: 14))
            .foregroundColor(.primary)
            .padding(.horizontal, bubblePadding)
            .padding(.vertical, 10)
            .frame(maxWidth: maxBubbleWidth, alignment: .leading)
            .background(assistantBubbleBackground())
            .clipShape(ChatBubbleShape(isUserMessage: false))
            .overlay(
                // Streaming indicator
                streamingIndicator()
            )
    }
    
    @ViewBuilder
    private func assistantBubbleBackground() -> some View {
        ZStack {
            // Base glass material
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.8)
            
            // Subtle ambient glow
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.green.opacity(0.05),
                            Color.green.opacity(0.02),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Surface highlight
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.1),
                            Color.white.opacity(0.02),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }
    
    @ViewBuilder
    private func aiAvatar() -> some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.green.opacity(0.2),
                        Color.green.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 24, height: 24)
            .overlay(
                Image(systemName: "brain")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.green)
            )
    }
    
    // MARK: - Streaming Indicator
    
    @ViewBuilder
    private func streamingIndicator() -> some View {
        if isStreaming && !isUserMessage {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .fill(Color.green.opacity(0.6))
                                .frame(width: 4, height: 4)
                                .scaleEffect(streamingDotScale(for: index))
                                .animation(
                                    .easeInOut(duration: 0.6)
                                        .repeatForever()
                                        .delay(Double(index) * 0.2),
                                    value: isStreaming
                                )
                        }
                    }
                    .padding(.trailing, 8)
                    .padding(.bottom, 6)
                }
            }
        }
    }
    
    private func streamingDotScale(for index: Int) -> CGFloat {
        return isStreaming ? (1.0 + sin(Date().timeIntervalSince1970 * 3 + Double(index)) * 0.5) : 1.0
    }
    
    // MARK: - Context References
    
    @ViewBuilder
    private func contextReferences() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
                .opacity(0.3)
            
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Text("Referenced current page")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .padding(.horizontal, bubblePadding)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: maxBubbleWidth)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.3)
        )
        .clipShape(
            RoundedRectangle(cornerRadius: 8)
        )
    }
    
    // MARK: - Message Metadata
    
    @ViewBuilder
    private func messageTimestamp() -> some View {
        Text(formatTimestamp(message.timestamp))
            .font(.system(size: 10))
            .foregroundColor(.secondary)
    }
    
    @ViewBuilder
    private func messageMetadata(_ metadata: ResponseMetadata) -> some View {
        HStack(spacing: 4) {
            // Processing steps count
            if !metadata.processingSteps.isEmpty {
                HStack(spacing: 2) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                    Text("\(metadata.processingSteps.count) steps")
                        .font(.system(size: 10))
                }
                .foregroundColor(.secondary)
            }
            
            // Memory usage
            if metadata.memoryUsage > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "memorychip")
                        .font(.system(size: 9))
                    Text("\(metadata.memoryUsage / 1024 / 1024)MB")
                        .font(.system(size: 10))
                }
                .foregroundColor(.secondary)
            }
            
            // Energy impact
            HStack(spacing: 2) {
                Image(systemName: "bolt.circle")
                    .font(.system(size: 9))
                Text(metadata.energyImpact.rawValue)
                    .font(.system(size: 10))
            }
            .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.dateFormat = "MMM d, HH:mm"
        }
        
        return formatter.string(from: date)
    }
}

// MARK: - Custom Chat Bubble Shape

struct ChatBubbleShape: Shape {
    let isUserMessage: Bool
    private let cornerRadius: CGFloat = 16
    private let tailSize: CGFloat = 8
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        if isUserMessage {
            // User message bubble (right-aligned with tail on bottom-right)
            path.addRoundedRect(
                in: CGRect(
                    x: 0,
                    y: 0,
                    width: rect.width - tailSize,
                    height: rect.height - tailSize
                ),
                cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
            )
            
            // Right tail
            let tailStart = CGPoint(x: rect.width - tailSize, y: rect.height - tailSize - cornerRadius)
            let tailMid = CGPoint(x: rect.width, y: rect.height - tailSize/2)
            let tailEnd = CGPoint(x: rect.width - tailSize, y: rect.height - tailSize)
            
            path.move(to: tailStart)
            path.addQuadCurve(to: tailEnd, control: tailMid)
            
        } else {
            // Assistant message bubble (left-aligned with tail on bottom-left)
            path.addRoundedRect(
                in: CGRect(
                    x: tailSize,
                    y: 0,
                    width: rect.width - tailSize,
                    height: rect.height - tailSize
                ),
                cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
            )
            
            // Left tail
            let tailStart = CGPoint(x: tailSize, y: rect.height - tailSize - cornerRadius)
            let tailMid = CGPoint(x: 0, y: rect.height - tailSize/2)
            let tailEnd = CGPoint(x: tailSize, y: rect.height - tailSize)
            
            path.move(to: tailStart)
            path.addQuadCurve(to: tailEnd, control: tailMid)
        }
        
        return path
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        // User message
        ChatBubbleView(
            message: ConversationMessage(
                role: .user,
                content: "Can you explain what this page is about?",
                timestamp: Date(),
                contextData: nil
            )
        )
        
        // Assistant message
        ChatBubbleView(
            message: ConversationMessage(
                role: .assistant,
                content: "This appears to be a search results page from Google. Based on the content I can see, it contains various search results and links related to your query.",
                timestamp: Date().addingTimeInterval(-60),
                contextData: "Page context data",
                metadata: ResponseMetadata(
                    contextUsed: true,
                    memoryUsage: 47 * 1024 * 1024, // 47MB
                    energyImpact: .low
                )
            )
        )
        
        // Streaming assistant message
        ChatBubbleView(
            message: ConversationMessage(
                role: .assistant,
                content: "",
                timestamp: Date(),
                contextData: nil
            ),
            isStreaming: true,
            streamingText: "I'm analyzing the current page content..."
        )
        
        Spacer()
    }
    .padding(16)
    .frame(width: 320, height: 600)
    .background(Color(.controlBackgroundColor))
}