import Foundation

// MARK: - Token Estimation Utility

/// Utility class for accurate token estimation
class TokenEstimator {
    
    /// Estimate token count for given text using improved algorithms
    static func estimateTokens(for text: String) -> Int {
        if text.isEmpty { return 0 }
        
        // Try to use actual tokenizer if available
        if let tokenizer = getAvailableTokenizer() {
            do {
                let tokens = try tokenizer.encode(text)
                return tokens.count
            } catch {
                NSLog("⚠️ Tokenizer failed, using fallback estimation: \(error)")
            }
        }
        
        // Improved estimation based on actual language patterns
        return improvedTokenEstimation(for: text)
    }
    
    private static func getAvailableTokenizer() -> GemmaTokenizer? {
        // Try to get tokenizer from available service - will use REAL SentencePiece
        // This would ideally be injected as a dependency
        return nil // Will be connected when service architecture is updated
    }
    
    private static func improvedTokenEstimation(for text: String) -> Int {
        if text.isEmpty { return 0 }
        
        // More accurate estimation based on language characteristics
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        var tokenCount = 0
        
        for word in words {
            // Average English word is ~1.3 tokens based on empirical data
            let wordLength = word.count
            if wordLength <= 3 {
                tokenCount += 1 // Short words are usually 1 token
            } else if wordLength <= 8 {
                tokenCount += 2 // Medium words are ~1-2 tokens  
            } else {
                tokenCount += 3 // Long words get split into more tokens
            }
        }
        
        // Add tokens for punctuation and special characters
        let punctuationCount = text.filter { ".,!?;:'\"-()[]{}@#$%^&*+=|\\/<>~`".contains($0) }.count
        tokenCount += punctuationCount
        
        // Add some tokens for whitespace/formatting (newlines, tabs, etc.)
        let whitespaceTokens = max(1, words.count / 10)
        tokenCount += whitespaceTokens
        
        // Special tokens for start/end if this looks like a conversation
        if text.contains("user:") || text.contains("assistant:") {
            tokenCount += 2 // BOS/EOS tokens
        }
        
        return tokenCount
    }
}

/// Conversation history manager for AI chat sessions
/// Handles message storage, retrieval, and conversation threading with privacy protection
class ConversationHistory: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var messageCount: Int = 0
    @Published var currentSessionTokens: Int = 0
    
    // MARK: - Storage
    
    private var messages: [ConversationMessage] = []
    private let maxMessages = 1000
    private let maxSessionTokens = 32000
    private var sessionId: String
    
    // MARK: - Initialization
    
    init() {
        self.sessionId = UUID().uuidString
        NSLog("💬 Conversation History initialized for session \(sessionId)")
    }
    
    // MARK: - Public Interface
    
    /// Add a new message to the conversation
    func addMessage(_ message: ConversationMessage) {
        messages.append(message)
        
        // Update metrics
        messageCount = messages.count
        currentSessionTokens = calculateTotalTokens()
        
        // Manage memory and token limits
        enforceTokenLimit()
        enforceMessageLimit()
        
        NSLog("💬 Added \(message.role.rawValue) message (\(message.estimatedTokens) tokens)")
    }
    
    /// Get recent messages up to a specified limit
    func getRecentMessages(limit: Int = 20) -> [ConversationMessage] {
        let recentMessages = Array(messages.suffix(limit))
        return recentMessages
    }
    
    /// Get messages for a specific time range
    func getMessages(from startDate: Date, to endDate: Date) -> [ConversationMessage] {
        return messages.filter { message in
            message.timestamp >= startDate && message.timestamp <= endDate
        }
    }
    
    /// Get messages by role
    func getMessages(by role: ConversationRole) -> [ConversationMessage] {
        return messages.filter { $0.role == role }
    }
    
    /// Get conversation summary
    func getSummary() -> ConversationSummary {
        let userMessages = getMessages(by: .user)
        let assistantMessages = getMessages(by: .assistant)
        
        return ConversationSummary(
            sessionId: sessionId,
            messageCount: messageCount,
            userMessages: userMessages.count,
            assistantMessages: assistantMessages.count,
            startTime: messages.first?.timestamp ?? Date(),
            endTime: messages.last?.timestamp ?? Date(),
            totalTokens: currentSessionTokens,
            topicsDiscussed: extractTopics()
        )
    }
    
    /// Search messages by content
    func searchMessages(query: String) -> [ConversationMessage] {
        let lowercaseQuery = query.lowercased()
        return messages.filter { message in
            message.content.lowercased().contains(lowercaseQuery)
        }
    }
    
    /// Get conversation context for AI processing
    func getContextForAI(maxTokens: Int = 8000) -> [ConversationMessage] {
        var contextMessages: [ConversationMessage] = []
        var tokenCount = 0
        
        // Start from most recent messages and work backwards
        for message in messages.reversed() {
            let messageTokens = message.estimatedTokens
            
            if tokenCount + messageTokens <= maxTokens {
                contextMessages.insert(message, at: 0) // Insert at beginning to maintain order
                tokenCount += messageTokens
            } else {
                break
            }
        }
        
        return contextMessages
    }
    
    /// Clear all conversation history
    func clear() {
        let previousCount = messages.count
        messages.removeAll()
        messageCount = 0
        currentSessionTokens = 0
        sessionId = UUID().uuidString
        
        NSLog("🗑️ Cleared \(previousCount) messages from conversation history")
    }
    
    /// Export conversation for backup/analysis
    func exportConversation() -> ConversationExport {
        return ConversationExport(
            sessionId: sessionId,
            exportedAt: Date(),
            messages: messages,
            summary: getSummary()
        )
    }
    
    /// Get conversation statistics
    func getStatistics() -> ConversationStatistics {
        let now = Date()
        let oneHourAgo = now.addingTimeInterval(-3600)
        let oneDayAgo = now.addingTimeInterval(-86400)
        
        return ConversationStatistics(
            totalMessages: messageCount,
            messagesLastHour: getMessages(from: oneHourAgo, to: now).count,
            messagesLastDay: getMessages(from: oneDayAgo, to: now).count,
            averageMessageLength: calculateAverageMessageLength(),
            longestMessage: messages.max(by: { $0.content.count < $1.content.count }),
            shortestMessage: messages.min(by: { $0.content.count < $1.content.count }),
            mostActiveHour: calculateMostActiveHour()
        )
    }
    
    // MARK: - Private Methods
    
    private func calculateTotalTokens() -> Int {
        return messages.reduce(0) { total, message in
            total + message.estimatedTokens
        }
    }
    
    private func enforceTokenLimit() {
        while currentSessionTokens > maxSessionTokens && !messages.isEmpty {
            // Remove oldest non-system messages
            if let index = messages.firstIndex(where: { $0.role != .system }) {
                let removedMessage = messages.remove(at: index)
                currentSessionTokens -= removedMessage.estimatedTokens
                NSLog("🗑️ Removed message to enforce token limit")
            } else {
                break
            }
        }
    }
    
    private func enforceMessageLimit() {
        while messages.count > maxMessages {
            let removedMessage = messages.removeFirst()
            currentSessionTokens -= removedMessage.estimatedTokens
            NSLog("🗑️ Removed oldest message to enforce message limit")
        }
        
        messageCount = messages.count
    }
    
    private func extractTopics() -> [String] {
        // Simple topic extraction based on common keywords
        let commonWords = Set(["the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by", "how", "what", "where", "when", "why", "who", "can", "could", "would", "should", "will", "do", "does", "did", "is", "are", "was", "were", "be", "been", "have", "has", "had", "get", "got", "make", "made", "take", "took", "go", "went", "come", "came", "see", "saw", "know", "knew", "think", "thought", "tell", "told", "say", "said", "give", "gave", "find", "found", "work", "worked", "call", "called", "try", "tried", "ask", "asked", "need", "needed", "feel", "felt", "become", "became", "leave", "left", "put", "let", "mean", "meant", "keep", "kept", "start", "started", "seem", "seemed", "help", "helped", "show", "showed", "hear", "heard", "play", "played", "run", "ran", "move", "moved", "live", "lived", "believe", "believed", "bring", "brought", "happen", "happened", "write", "wrote", "provide", "provided", "sit", "sat", "stand", "stood", "lose", "lost", "pay", "paid", "meet", "met", "include", "included", "continue", "continued", "set", "change", "changed", "lead", "led", "understand", "understood", "watch", "watched", "follow", "followed", "stop", "stopped", "create", "created", "speak", "spoke", "read", "allow", "allowed", "add", "added", "spend", "spent", "grow", "grew", "open", "opened", "walk", "walked", "win", "won", "offer", "offered", "remember", "remembered", "love", "loved", "consider", "considered", "appear", "appeared", "buy", "bought", "wait", "waited", "serve", "served", "die", "died", "send", "sent", "expect", "expected", "build", "built", "stay", "stayed", "fall", "fell", "cut", "reach", "reached", "kill", "killed", "remain", "remained", "suggest", "suggested", "raise", "raised", "pass", "passed", "sell", "sold", "require", "required", "report", "reported", "decide", "decided", "pull", "pulled"])
        
        var wordFrequency: [String: Int] = [:]
        
        // Count word frequency across all messages
        for message in messages {
            let words = message.content
                .lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .compactMap { word in
                    let cleaned = word.trimmingCharacters(in: .punctuationCharacters)
                    return cleaned.isEmpty || commonWords.contains(cleaned) ? nil : cleaned
                }
            
            for word in words {
                wordFrequency[word, default: 0] += 1
            }
        }
        
        // Return top topics
        return wordFrequency
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { $0.key }
    }
    
    private func calculateAverageMessageLength() -> Double {
        guard !messages.isEmpty else { return 0 }
        
        let totalLength = messages.reduce(0) { $0 + $1.content.count }
        return Double(totalLength) / Double(messages.count)
    }
    
    private func calculateMostActiveHour() -> Int? {
        guard !messages.isEmpty else { return nil }
        
        var hourFrequency: [Int: Int] = [:]
        let calendar = Calendar.current
        
        for message in messages {
            let hour = calendar.component(.hour, from: message.timestamp)
            hourFrequency[hour, default: 0] += 1
        }
        
        return hourFrequency.max(by: { $0.value < $1.value })?.key
    }
}

// MARK: - Supporting Types

/// Individual conversation message
struct ConversationMessage: Identifiable {
    let id: String
    let role: ConversationRole
    let content: String
    let timestamp: Date
    let contextData: String? // Simplified context data
    let metadata: ResponseMetadata?
    
    init(
        role: ConversationRole,
        content: String,
        timestamp: Date,
        contextData: String? = nil,
        metadata: ResponseMetadata? = nil
    ) {
        self.id = UUID().uuidString
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.contextData = contextData
        self.metadata = metadata
    }
    
    /// Estimated token count for this message
    var estimatedTokens: Int {
        // Use proper token counting when available, fallback to improved estimation
        return TokenEstimator.estimateTokens(for: content) + 
               TokenEstimator.estimateTokens(for: metadata?.description ?? "")
    }
}

/// Conversation summary
struct ConversationSummary {
    let sessionId: String
    let messageCount: Int
    let userMessages: Int
    let assistantMessages: Int
    let startTime: Date
    let endTime: Date
    let totalTokens: Int
    let topicsDiscussed: [String]
    
    var duration: TimeInterval {
        return endTime.timeIntervalSince(startTime)
    }
}

/// Conversation export format
struct ConversationExport {
    let sessionId: String
    let exportedAt: Date
    let messages: [ConversationMessage]
    let summary: ConversationSummary
}

/// Conversation statistics
struct ConversationStatistics {
    let totalMessages: Int
    let messagesLastHour: Int
    let messagesLastDay: Int
    let averageMessageLength: Double
    let longestMessage: ConversationMessage?
    let shortestMessage: ConversationMessage?
    let mostActiveHour: Int?
}

// MARK: - Extensions

extension ConversationMessage {
    /// Check if message contains sensitive information
    var containsSensitiveInfo: Bool {
        let sensitiveKeywords = ["password", "credit card", "ssn", "social security", "api key", "token", "private key"]
        let lowercaseContent = content.lowercased()
        
        return sensitiveKeywords.contains { keyword in
            lowercaseContent.contains(keyword)
        }
    }
    
    /// Get formatted timestamp
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

extension ConversationRole: CustomStringConvertible {
    var description: String {
        switch self {
        case .user:
            return "User"
        case .assistant:
            return "Assistant"
        case .system:
            return "System"
        }
    }
}