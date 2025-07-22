import Foundation
import NaturalLanguage

/// Context processing utility for content summarization and token management
/// Handles text processing, summarization, and context optimization for AI input
class ContextProcessor {
    
    // MARK: - Properties
    
    private let tokenEstimator = TokenEstimator()
    private let contentCleaner = ContentCleaner()
    private let summarizer = TextSummarizer()
    
    // MARK: - Public Interface
    
    /// Process raw content for AI consumption with token limits
    func processContent(_ content: String, maxTokens: Int) async -> String {
        // Step 1: Clean and normalize content
        let cleanedContent = contentCleaner.cleanContent(content)
        
        // Step 2: Estimate tokens
        let currentTokens = estimateTokens(cleanedContent)
        
        // Step 3: Summarize if content exceeds token limit
        if currentTokens > maxTokens {
            return await summarizer.summarize(cleanedContent, targetTokens: maxTokens)
        }
        
        return cleanedContent
    }
    
    /// Extract key information from web content
    func extractKeyInformation(_ content: String) -> ContentSummary {
        let cleaned = contentCleaner.cleanContent(content)
        
        // Extract headings and structure
        let headings = extractHeadings(from: cleaned)
        
        // Extract key sentences
        let keySentences = extractKeySentences(from: cleaned, count: 5)
        
        // Detect language
        let language = detectLanguage(cleaned)
        
        // Extract entities
        let entities = extractEntities(from: cleaned)
        
        return ContentSummary(
            headings: headings,
            keySentences: keySentences,
            language: language,
            entities: entities,
            wordCount: cleaned.components(separatedBy: .whitespacesAndNewlines).count,
            tokenCount: estimateTokens(cleaned)
        )
    }
    
    /// Estimate token count for text
    func estimateTokens(_ text: String) -> Int {
        return tokenEstimator.estimate(text)
    }
    
    /// Optimize context for AI processing
    func optimizeContext(_ context: [String], maxTotalTokens: Int) -> [String] {
        var optimizedContext: [String] = []
        var currentTokens = 0
        
        // Sort by relevance/importance (simplified heuristic)
        let sortedContext = context.sorted { text1, text2 in
            let score1 = calculateRelevanceScore(text1)
            let score2 = calculateRelevanceScore(text2)
            return score1 > score2
        }
        
        for text in sortedContext {
            let tokens = estimateTokens(text)
            
            if currentTokens + tokens <= maxTotalTokens {
                optimizedContext.append(text)
                currentTokens += tokens
            } else {
                // Try to summarize and fit remaining content
                let remainingTokens = maxTotalTokens - currentTokens
                if remainingTokens > 100 { // Only summarize if we have reasonable space
                    // TODO: Fix async call when properly integrated
                    // let summarized = await summarizer.summarize(text, targetTokens: remainingTokens)
                    // if !summarized.isEmpty {
                    //     optimizedContext.append(summarized)
                    // }
                }
                break
            }
        }
        
        return optimizedContext
    }
    
    // MARK: - Private Methods
    
    private func extractHeadings(from text: String) -> [String] {
        let lines = text.components(separatedBy: .newlines)
        var headings: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Simple heuristics for heading detection
            if trimmed.count < 100 && // Not too long
               trimmed.count > 5 &&   // Not too short
               !trimmed.hasSuffix(".") && // Doesn't end with period
               !trimmed.contains(",") {   // Doesn't contain comma
                
                // Check if line has title case or ALL CAPS
                let words = trimmed.components(separatedBy: .whitespaces)
                let capitalizedWords = words.filter { word in
                    word.first?.isUppercase == true
                }
                
                if Double(capitalizedWords.count) / Double(words.count) > 0.6 {
                    headings.append(trimmed)
                }
            }
        }
        
        return Array(headings.prefix(10)) // Limit to top 10 headings
    }
    
    private func extractKeySentences(from text: String, count: Int) -> [String] {
        let sentences = text.components(separatedBy: .punctuationCharacters)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count > 20 && $0.count < 200 }
        
        // Score sentences by various factors
        let scoredSentences = sentences.map { sentence in
            (sentence: sentence, score: calculateSentenceScore(sentence))
        }
        
        return scoredSentences
            .sorted { $0.score > $1.score }
            .prefix(count)
            .map { $0.sentence }
    }
    
    private func calculateSentenceScore(_ sentence: String) -> Double {
        var score = 0.0
        
        // Length factor (prefer medium-length sentences)
        let length = sentence.count
        if length > 50 && length < 150 {
            score += 1.0
        }
        
        // Keyword density (look for informative words)
        let importantWords = ["important", "key", "main", "significant", "primary", "essential", "critical", "major"]
        let lowercased = sentence.lowercased()
        
        for word in importantWords {
            if lowercased.contains(word) {
                score += 0.5
            }
        }
        
        // Structural indicators
        if sentence.contains(":") { score += 0.3 }
        if sentence.contains("because") || sentence.contains("therefore") { score += 0.4 }
        
        return score
    }
    
    private func detectLanguage(_ text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        
        return recognizer.dominantLanguage?.rawValue ?? "unknown"
    }
    
    private func extractEntities(from text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        
        var entities: [String] = []
        
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: [.omitWhitespace, .omitPunctuation]) { tag, tokenRange in
            if let tag = tag {
                let entity = String(text[tokenRange])
                entities.append("\(entity) (\(tag.rawValue))")
            }
            return true
        }
        
        return Array(entities.prefix(10))
    }
    
    private func calculateRelevanceScore(_ text: String) -> Double {
        var score = 0.0
        
        // Length penalty/bonus (prefer medium length content)
        let wordCount = text.components(separatedBy: .whitespacesAndNewlines).count
        if wordCount > 50 && wordCount < 500 {
            score += 1.0
        } else if wordCount < 50 {
            score += 0.5
        }
        
        // Information density (look for varied vocabulary)
        let words = Set(text.lowercased().components(separatedBy: .whitespacesAndNewlines))
        let uniqueWordRatio = Double(words.count) / Double(wordCount)
        score += uniqueWordRatio * 0.5
        
        return score
    }
}

// MARK: - Token Estimator

private class TokenEstimator {
    func estimate(_ text: String) -> Int {
        // GPT-style tokenization estimate: roughly 1 token per 4 characters
        // This is a simplified heuristic - real tokenization would be more accurate
        let baseTokens = text.count / 4
        
        // Adjust for special characters and spacing
        let specialCharCount = text.filter { ".,!?;:()[]{}\"'".contains($0) }.count
        let spaceCount = text.filter { $0.isWhitespace }.count
        
        // Special characters are often their own tokens
        let adjustedTokens = baseTokens + (specialCharCount / 2) + (spaceCount / 8)
        
        return max(1, adjustedTokens)
    }
}

// MARK: - Content Cleaner

private class ContentCleaner {
    func cleanContent(_ content: String) -> String {
        var cleaned = content
        
        // Remove excessive whitespace
        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        // Remove common web artifacts
        let webArtifacts = [
            "Cookie notice", "Accept cookies", "Privacy policy",
            "Subscribe to newsletter", "Sign up", "Login", "Register",
            "Advertisement", "Sponsored content", "Related articles"
        ]
        
        for artifact in webArtifacts {
            cleaned = cleaned.replacingOccurrences(of: artifact, with: "", options: .caseInsensitive)
        }
        
        // Remove repeated characters (more than 3 in a row)
        cleaned = cleaned.replacingOccurrences(of: "([.,!?;:]){3,}", with: "$1", options: .regularExpression)
        
        // Clean up line breaks
        cleaned = cleaned.replacingOccurrences(of: "\\n\\s*\\n\\s*\\n", with: "\\n\\n", options: .regularExpression)
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Text Summarizer

private class TextSummarizer {
    func summarize(_ content: String, targetTokens: Int) async -> String {
        // Simple extractive summarization
        let sentences = content.components(separatedBy: .punctuationCharacters)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count > 20 }
        
        if sentences.count <= 3 {
            return content // Too short to summarize meaningfully
        }
        
        // Score sentences and select top ones
        let processor = ContextProcessor()
        let scoredSentences = sentences.map { sentence in
            (sentence: sentence, score: calculateSummarizationScore(sentence))
        }
        
        let sortedSentences = scoredSentences.sorted { $0.score > $1.score }
        
        var summary = ""
        var currentTokens = 0
        
        for (sentence, _) in sortedSentences {
            let sentenceTokens = processor.estimateTokens(sentence)
            
            if currentTokens + sentenceTokens <= targetTokens {
                summary += sentence + ". "
                currentTokens += sentenceTokens
            } else {
                break
            }
        }
        
        return summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func calculateSummarizationScore(_ sentence: String) -> Double {
        var score = 0.0
        
        // Position bonus (first and last sentences often important)
        // This would be calculated relative to position in full text
        
        // Length factor
        let length = sentence.count
        if length > 50 && length < 200 {
            score += 1.0
        }
        
        // Keyword presence
        let importantWords = ["key", "important", "main", "significant", "however", "therefore", "because", "result"]
        let lowercased = sentence.lowercased()
        
        for word in importantWords {
            if lowercased.contains(word) {
                score += 0.5
            }
        }
        
        // Numeric data (often important)
        if sentence.range(of: "\\d+", options: .regularExpression) != nil {
            score += 0.3
        }
        
        return score
    }
}

// MARK: - Supporting Types

struct ContentSummary {
    let headings: [String]
    let keySentences: [String]
    let language: String
    let entities: [String]
    let wordCount: Int
    let tokenCount: Int
    
    var summary: String {
        var parts: [String] = []
        
        if !headings.isEmpty {
            parts.append("Headings: " + headings.prefix(3).joined(separator: ", "))
        }
        
        if !keySentences.isEmpty {
            parts.append("Key points: " + keySentences.prefix(2).joined(separator: " "))
        }
        
        return parts.joined(separator: "\n\n")
    }
}