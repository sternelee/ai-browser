import Foundation
import NaturalLanguage

/// Summarization service for AI content processing
/// Handles content summarization, key point extraction, and context optimization
class SummarizationService: ObservableObject {
    
    // MARK: - Properties
    
    private let contextProcessor = ContextProcessor()
    @Published var isProcessing: Bool = false
    
    // MARK: - Configuration
    
    private let maxSummaryLength = 500
    private let minSummaryLength = 50
    private let keyPointsCount = 5
    
    // MARK: - Public Interface
    
    /// Summarize web page content for AI context
    func summarizeWebContent(_ content: String, maxTokens: Int = 200) async -> WebContentSummary {
        isProcessing = true
        defer { isProcessing = false }
        
        // Extract content information
        let contentSummary = contextProcessor.extractKeyInformation(content)
        
        // Generate different types of summaries
        let briefSummary = await generateBriefSummary(content, maxTokens: maxTokens / 2)
        let detailedSummary = await generateDetailedSummary(content, maxTokens: maxTokens)
        let keyPoints = extractKeyPoints(content)
        
        // Detect content type
        let contentType = detectContentType(content)
        
        return WebContentSummary(
            briefSummary: briefSummary,
            detailedSummary: detailedSummary,
            keyPoints: keyPoints,
            headings: contentSummary.headings,
            contentType: contentType,
            language: contentSummary.language,
            wordCount: contentSummary.wordCount,
            estimatedReadingTime: calculateReadingTime(contentSummary.wordCount)
        )
    }
    
    /// Summarize tab content for context window optimization
    func summarizeTabContent(_ tabContext: TabContext, maxTokens: Int = 150) async -> String {
        let content = tabContext.content
        
        if contextProcessor.estimateTokens(content) <= maxTokens {
            return content // No need to summarize
        }
        
        // Create a focused summary for AI context
        let summary = await generateContextualSummary(
            content: content,
            title: tabContext.title,
            url: tabContext.url,
            maxTokens: maxTokens
        )
        
        return summary
    }
    
    /// Summarize multiple tabs for cross-tab analysis
    func summarizeMultipleTabs(_ tabs: [TabContext], maxTokens: Int = 400) async -> MultiTabSummary {
        isProcessing = true
        defer { isProcessing = false }
        
        var tabSummaries: [SingleTabSummary] = []
        var commonThemes: [String] = []
        var relatedTabs: [(TabContext, TabContext, Double)] = []
        
        // Summarize each tab individually
        for tab in tabs {
            let summary = await summarizeTabContent(tab, maxTokens: maxTokens / tabs.count)
            let tabSummary = SingleTabSummary(
                tabId: tab.tabId,
                title: tab.title,
                url: tab.url,
                summary: summary,
                contentType: detectContentType(tab.content),
                tokenCount: contextProcessor.estimateTokens(summary)
            )
            tabSummaries.append(tabSummary)
        }
        
        // Find common themes
        commonThemes = findCommonThemes(in: tabs)
        
        // Find related tabs
        relatedTabs = findRelatedTabs(tabs)
        
        // Generate overall summary
        let overallSummary = generateOverallSummary(from: tabSummaries)
        
        return MultiTabSummary(
            overallSummary: overallSummary,
            tabSummaries: tabSummaries,
            commonThemes: commonThemes,
            relatedTabs: relatedTabs.map { (tab1, tab2, score) in
                TabRelation(tab1Id: tab1.tabId, tab2Id: tab2.tabId, relationScore: score)
            },
            totalTokens: tabSummaries.reduce(0) { $0 + $1.tokenCount }
        )
    }
    
    /// Generate conversation summary
    func summarizeConversation(_ messages: [ConversationMessage]) async -> ConversationSummary {
        let userMessages = messages.filter { $0.role == .user }
        let assistantMessages = messages.filter { $0.role == .assistant }
        
        // Extract topics discussed
        let allContent = messages.map { $0.content }.joined(separator: " ")
        let topics = extractTopicsFromText(allContent)
        
        // Analyze conversation flow
        let conversationFlow = analyzeConversationFlow(messages)
        
        return ConversationSummary(
            sessionId: UUID().uuidString,
            messageCount: messages.count,
            userMessages: userMessages.count,
            assistantMessages: assistantMessages.count,
            startTime: messages.first?.timestamp ?? Date(),
            endTime: messages.last?.timestamp ?? Date(),
            totalTokens: messages.reduce(0) { $0 + $1.estimatedTokens },
            topicsDiscussed: topics
        )
    }
    
    // MARK: - Private Methods
    
    private func generateBriefSummary(_ content: String, maxTokens: Int) async -> String {
        // Extract the most important sentences
        let sentences = content.components(separatedBy: .punctuationCharacters)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count > 20 && $0.count < 200 }
        
        if sentences.isEmpty {
            return content.prefix(200).description
        }
        
        // Score and select top sentences
        let scoredSentences = sentences.map { sentence in
            (sentence: sentence, score: calculateSentenceImportance(sentence, in: content))
        }
        
        let topSentences = scoredSentences
            .sorted { $0.score > $1.score }
            .prefix(3)
            .map { $0.sentence }
        
        let summary = topSentences.joined(separator: ". ") + "."
        
        // Ensure we don't exceed token limit
        if contextProcessor.estimateTokens(summary) > maxTokens {
            let words = summary.components(separatedBy: .whitespaces)
            let targetWords = (maxTokens * 4) // Rough conversion
            let truncated = words.prefix(targetWords).joined(separator: " ")
            return truncated + "..."
        }
        
        return summary
    }
    
    private func generateDetailedSummary(_ content: String, maxTokens: Int) async -> String {
        // More comprehensive summary including structure
        let contentSummary = contextProcessor.extractKeyInformation(content)
        
        var summaryParts: [String] = []
        
        // Add main headings if available
        if !contentSummary.headings.isEmpty {
            summaryParts.append("Main topics: " + contentSummary.headings.prefix(3).joined(separator: ", "))
        }
        
        // Add key sentences
        if !contentSummary.keySentences.isEmpty {
            summaryParts.append("Key points: " + contentSummary.keySentences.prefix(3).joined(separator: " "))
        }
        
        let summary = summaryParts.joined(separator: "\n\n")
        
        // Trim if too long
        if contextProcessor.estimateTokens(summary) > maxTokens {
            return await generateBriefSummary(content, maxTokens: maxTokens)
        }
        
        return summary
    }
    
    private func generateContextualSummary(content: String, title: String, url: URL, maxTokens: Int) async -> String {
        // Create a summary that includes context about the page
        let contentType = detectContentType(content)
        let domain = url.host ?? "unknown"
        
        var contextualInfo = "Page: \(title) (\(domain))"
        
        if contentType != .unknown {
            contextualInfo += " - \(contentType.description)"
        }
        
        let contentSummary = await generateBriefSummary(content, maxTokens: maxTokens - contextProcessor.estimateTokens(contextualInfo))
        
        return "\(contextualInfo)\n\(contentSummary)"
    }
    
    private func extractKeyPoints(_ content: String) -> [String] {
        let sentences = content.components(separatedBy: .punctuationCharacters)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count > 30 && $0.count < 150 }
        
        // Look for sentences with key indicators
        let keyIndicators = ["key", "important", "main", "significant", "primary", "essential", "critical", "note", "remember"]
        
        let keyPoints = sentences.filter { sentence in
            let lowercased = sentence.lowercased()
            return keyIndicators.contains { indicator in
                lowercased.contains(indicator)
            }
        }
        
        return Array(keyPoints.prefix(keyPointsCount))
    }
    
    private func detectContentType(_ content: String) -> ContentType {
        let lowercased = content.lowercased()
        
        // Check for various content types
        if lowercased.contains("recipe") || lowercased.contains("ingredients") || lowercased.contains("instructions") {
            return .recipe
        }
        
        if lowercased.contains("news") || lowercased.contains("breaking") || lowercased.contains("reported") {
            return .news
        }
        
        if lowercased.contains("research") || lowercased.contains("study") || lowercased.contains("analysis") {
            return .research
        }
        
        if lowercased.contains("tutorial") || lowercased.contains("how to") || lowercased.contains("step") {
            return .tutorial
        }
        
        if lowercased.contains("product") || lowercased.contains("buy") || lowercased.contains("price") || lowercased.contains("$") {
            return .product
        }
        
        if lowercased.contains("blog") || lowercased.contains("posted") || lowercased.contains("author") {
            return .blog
        }
        
        return .unknown
    }
    
    private func calculateSentenceImportance(_ sentence: String, in content: String) -> Double {
        var score = 0.0
        
        // Length factor (prefer medium-length sentences)
        let length = sentence.count
        if length > 50 && length < 150 {
            score += 1.0
        }
        
        // Position factor (first sentences often important)
        let sentenceIndex = content.range(of: sentence)?.lowerBound
        if let index = sentenceIndex, index < content.index(content.startIndex, offsetBy: content.count / 4) {
            score += 0.5
        }
        
        // Keyword density
        let importantWords = ["key", "important", "main", "significant", "result", "conclusion", "summary"]
        let lowercased = sentence.lowercased()
        
        for word in importantWords {
            if lowercased.contains(word) {
                score += 0.5
            }
        }
        
        // Structural indicators
        if sentence.contains(":") { score += 0.3 }
        if sentence.contains("because") || sentence.contains("therefore") || sentence.contains("however") { score += 0.4 }
        
        return score
    }
    
    private func calculateReadingTime(_ wordCount: Int) -> Int {
        // Average reading speed: 200-250 words per minute
        return max(1, wordCount / 225)
    }
    
    private func findCommonThemes(in tabs: [TabContext]) -> [String] {
        // Simple keyword extraction across all tabs
        let allContent = tabs.map { $0.content.lowercased() }.joined(separator: " ")
        let words = allContent.components(separatedBy: .whitespacesAndNewlines)
        
        // Count word frequency
        var wordFreq: [String: Int] = [:]
        let stopWords = Set(["the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by"])
        
        for word in words {
            let cleaned = word.trimmingCharacters(in: .punctuationCharacters)
            if cleaned.count > 3 && !stopWords.contains(cleaned) {
                wordFreq[cleaned, default: 0] += 1
            }
        }
        
        // Return most frequent words as themes
        return wordFreq
            .filter { $0.value >= tabs.count } // Word appears in multiple tabs
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key }
    }
    
    private func findRelatedTabs(_ tabs: [TabContext]) -> [(TabContext, TabContext, Double)] {
        var relations: [(TabContext, TabContext, Double)] = []
        
        for i in 0..<tabs.count {
            for j in (i+1)..<tabs.count {
                let similarity = calculateContentSimilarity(tabs[i].content, tabs[j].content)
                if similarity > 0.3 { // Threshold for relatedness
                    relations.append((tabs[i], tabs[j], similarity))
                }
            }
        }
        
        return relations.sorted { $0.2 > $1.2 } // Sort by similarity score
    }
    
    private func calculateContentSimilarity(_ content1: String, _ content2: String) -> Double {
        let words1 = Set(content1.lowercased().components(separatedBy: .whitespacesAndNewlines))
        let words2 = Set(content2.lowercased().components(separatedBy: .whitespacesAndNewlines))
        
        let intersection = words1.intersection(words2)
        let union = words1.union(words2)
        
        return union.isEmpty ? 0 : Double(intersection.count) / Double(union.count)
    }
    
    private func generateOverallSummary(from tabSummaries: [SingleTabSummary]) -> String {
        if tabSummaries.isEmpty {
            return "No tabs to summarize"
        }
        
        let domains = Set(tabSummaries.compactMap { $0.url.host }).joined(separator: ", ")
        let contentTypes = tabSummaries.map { $0.contentType.description }.joined(separator: ", ")
        
        return "Browsing session across \(tabSummaries.count) tabs from domains: \(domains). Content types: \(contentTypes)."
    }
    
    private func extractTopicsFromText(_ text: String) -> [String] {
        // Use NaturalLanguage framework for basic topic extraction
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        
        var topics: [String] = []
        
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: [.omitWhitespace, .omitPunctuation]) { tag, tokenRange in
            if let tag = tag, tag == .personalName || tag == .organizationName || tag == .placeName {
                let topic = String(text[tokenRange])
                topics.append(topic)
            }
            return true
        }
        
        return Array(Set(topics).prefix(10)) // Remove duplicates and limit
    }
    
    private func analyzeConversationFlow(_ messages: [ConversationMessage]) -> [String] {
        // Simple conversation flow analysis
        var flow: [String] = []
        
        let userQuestions = messages.filter { $0.role == .user && $0.content.contains("?") }
        let assistantResponses = messages.filter { $0.role == .assistant }
        
        if !userQuestions.isEmpty {
            flow.append("User asked \(userQuestions.count) questions")
        }
        
        if !assistantResponses.isEmpty {
            flow.append("Assistant provided \(assistantResponses.count) responses")
        }
        
        return flow
    }
}

// MARK: - Supporting Types

struct WebContentSummary {
    let briefSummary: String
    let detailedSummary: String
    let keyPoints: [String]
    let headings: [String]
    let contentType: ContentType
    let language: String
    let wordCount: Int
    let estimatedReadingTime: Int // minutes
}

struct SingleTabSummary {
    let tabId: String
    let title: String
    let url: URL
    let summary: String
    let contentType: ContentType
    let tokenCount: Int
}

struct MultiTabSummary {
    let overallSummary: String
    let tabSummaries: [SingleTabSummary]
    let commonThemes: [String]
    let relatedTabs: [TabRelation]
    let totalTokens: Int
}

struct TabRelation {
    let tab1Id: String
    let tab2Id: String
    let relationScore: Double // 0-1
}

enum ContentType {
    case news
    case blog
    case research
    case tutorial
    case product
    case recipe
    case documentation
    case unknown
    
    var description: String {
        switch self {
        case .news: return "News Article"
        case .blog: return "Blog Post"
        case .research: return "Research Paper"
        case .tutorial: return "Tutorial"
        case .product: return "Product Page"
        case .recipe: return "Recipe"
        case .documentation: return "Documentation"
        case .unknown: return "General Content"
        }
    }
}