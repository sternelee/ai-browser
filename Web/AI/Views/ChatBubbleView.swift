import SwiftUI

/// Individual chat message bubble for AI conversations
/// Supports both user and assistant messages with contextual styling
struct ChatBubbleView: View {
    let message: ConversationMessage
    let isStreaming: Bool
    let streamingText: String
    
    // REMOVED: Animation state - now using unified LoadingDotsView component
    
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

    /// Returns a SwiftUI `Text` view capable of rendering markdown while preserving line breaks.
    /// Falls back to plain text if markdown parsing fails or when streaming to avoid partial formatting.
    @ViewBuilder
    private func formattedText() -> some View {
        // Avoid markdown parsing while streaming to prevent crashes with incomplete syntax
        if isStreaming {
            Text(displayText)
        } else {
            // Preprocess text to fix missing spaces that break markdown
            let processedText = displayText
                .replacingOccurrences(of: "(?<=[.!?:])(?=[A-Z])", with: " ", options: .regularExpression)
                // Insert a line-break before list markers that are glued to a preceding colon, e.g. "We can:*" → "We can:\n* "
                // This avoids corrupting inline *italic* or **bold** markup because those usually have a space before the asterisk.
                .replacingOccurrences(of: "(?<=:)\\s*\\*", with: "\n* ", options: .regularExpression)
            
            // Use SwiftUI's native markdown renderer with AttributedString
            // This properly handles bold/italic/links while preserving line breaks
            if let attributedString = try? AttributedString(markdown: processedText, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                Text(attributedString)
                    .lineSpacing(2)
            } else {
                // Fallback to plain text if markdown parsing fails
                Text(processedText)
                    .lineSpacing(2)
            }
        }
    }
    
    // Configuration
    private let maxBubbleWidth: CGFloat = 260
    private let bubblePadding: EdgeInsets = EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
    private let bubbleSpacing: CGFloat = 12
    
    init(message: ConversationMessage, isStreaming: Bool = false, streamingText: String = "") {
        self.message = message
        self.isStreaming = isStreaming
        self.streamingText = streamingText
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: bubbleSpacing) {
            if isUserMessage {
                Spacer(minLength: 32) // Right-align user messages
                userMessageBubble()
            } else {
                assistantMessageBubble()
                Spacer(minLength: 32) // Left-align assistant messages
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        // REMOVED: .animation(.easeInOut(duration: 0.2), value: displayText) - caused flickering on every character change
        // REMOVED: Streaming animation management - now handled by unified LoadingDotsView
    }
    
    // MARK: - User Message Bubble
    
    @ViewBuilder
    private func userMessageBubble() -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(alignment: .bottom, spacing: 6) {
                // Message content
                formattedText()
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(bubblePadding)
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
            // Modern blue gradient with iOS 17 style
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.95),
                    Color.accentColor.opacity(0.85)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Inner glow for depth
            LinearGradient(
                colors: [
                    Color.white.opacity(0.2),
                    Color.white.opacity(0.08),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
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
        formattedText()
            .font(.system(size: 14, weight: .regular))
            .foregroundColor(.primary)
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .padding(bubblePadding)
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
            // Modern glass material with improved transparency
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.9)
            
            // Sophisticated ambient tint
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.green.opacity(0.04),
                            Color.blue.opacity(0.02),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Subtle surface reflection
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.06),
                            Color.white.opacity(0.01),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
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
    
    // MARK: - Unified Streaming Indicator
    
    @ViewBuilder
    private func streamingIndicator() -> some View {
        if isStreaming && !isUserMessage {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    LoadingDotsView(dotColor: .green.opacity(0.6), dotSize: 4, spacing: 3)
                        .padding(.trailing, 8)
                        .padding(.bottom, 6)
                }
            }
        }
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
            .padding(.horizontal, bubblePadding.leading)
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
    private let cornerRadius: CGFloat = 18
    private let tailSize: CGFloat = 6
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        if isUserMessage {
            // User message bubble with modern rounded rectangle
            // Slightly more rounded on the bottom-left to create iOS-style asymmetry
            path.addPath(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .path(in: CGRect(
                        x: 0,
                        y: 0,
                        width: rect.width,
                        height: rect.height
                    ))
            )
            
        } else {
            // Assistant message bubble with modern rounded rectangle
            // Slightly more rounded on the bottom-right for visual balance
            path.addPath(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .path(in: CGRect(
                        x: 0,
                        y: 0,
                        width: rect.width,
                        height: rect.height
                    ))
            )
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