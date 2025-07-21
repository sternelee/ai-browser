import SwiftUI
import Foundation
import Combine

@MainActor
class AutofillService: ObservableObject {
    @Published private(set) var suggestions: [AutofillSuggestion] = []
    @Published private(set) var isLoading = false
    
    private var historyEntries: [HistoryEntry] = []
    private var bookmarkEntries: [BookmarkEntry] = []
    private var suggestionCache: [String: [AutofillSuggestion]] = [:]
    private let maxSuggestions = 8
    private let cacheTimeout: TimeInterval = 300
    private let cacheTimestamps: NSMutableDictionary = NSMutableDictionary()
    
    init() {
        loadMockData()
    }
    
    func getSuggestions(for query: String) async -> [AutofillSuggestion] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard trimmedQuery.count >= 1 else {
            return []
        }
        
        if let cachedSuggestions = getCachedSuggestions(for: trimmedQuery) {
            return cachedSuggestions
        }
        
        isLoading = true
        
        var allSuggestions: [AutofillSuggestion] = []
        
        let historySuggestions = getHistorySuggestions(for: trimmedQuery)
        allSuggestions.append(contentsOf: historySuggestions)
        
        let bookmarkSuggestions = getBookmarkSuggestions(for: trimmedQuery)
        allSuggestions.append(contentsOf: bookmarkSuggestions)
        
        let uniqueSuggestions = removeDuplicates(from: allSuggestions)
        let sortedSuggestions = uniqueSuggestions
            .sorted { $0.score > $1.score }
            .prefix(maxSuggestions)
            .map { $0 }
        
        cacheResults(query: trimmedQuery, suggestions: sortedSuggestions)
        
        isLoading = false
        return sortedSuggestions
    }
    
    func recordVisit(url: String, title: String) {
        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let existingIndex = historyEntries.firstIndex(where: { $0.url == cleanURL }) {
            let existing = historyEntries[existingIndex]
            historyEntries[existingIndex] = HistoryEntry(
                url: existing.url,
                title: cleanTitle.isEmpty ? existing.title : cleanTitle,
                visitCount: existing.visitCount + 1,
                lastVisited: Date(),
                firstVisited: existing.firstVisited
            )
        } else {
            historyEntries.append(HistoryEntry(
                url: cleanURL,
                title: cleanTitle.isEmpty ? cleanURL : cleanTitle,
                visitCount: 1,
                lastVisited: Date(),
                firstVisited: Date()
            ))
        }
        
        clearCache()
    }
    
    func addBookmark(url: String, title: String, favicon: NSImage? = nil) {
        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !bookmarkEntries.contains(where: { $0.url == cleanURL }) {
            bookmarkEntries.append(BookmarkEntry(
                url: cleanURL,
                title: cleanTitle.isEmpty ? cleanURL : cleanTitle,
                favicon: favicon,
                dateAdded: Date()
            ))
            
            clearCache()
        }
    }
    
    func removeBookmark(url: String) {
        bookmarkEntries.removeAll { $0.url == url }
        clearCache()
    }
    
    private func getHistorySuggestions(for query: String) -> [AutofillSuggestion] {
        return historyEntries.compactMap { entry in
            let urlMatch = fuzzyMatch(text: entry.url, query: query)
            let titleMatch = fuzzyMatch(text: entry.title, query: query)
            let matchScore = max(urlMatch, titleMatch)
            
            guard matchScore > 0.1 else { return nil }
            
            let score = calculateScore(
                visitCount: entry.visitCount,
                lastVisited: entry.lastVisited,
                matchQuality: matchScore,
                sourceType: .history
            )
            
            return AutofillSuggestion(
                url: entry.url,
                title: entry.title,
                favicon: nil,
                score: score,
                sourceType: .history,
                visitCount: entry.visitCount,
                lastVisited: entry.lastVisited
            )
        }
    }
    
    private func getBookmarkSuggestions(for query: String) -> [AutofillSuggestion] {
        return bookmarkEntries.compactMap { entry in
            let urlMatch = fuzzyMatch(text: entry.url, query: query)
            let titleMatch = fuzzyMatch(text: entry.title, query: query)
            let matchScore = max(urlMatch, titleMatch)
            
            guard matchScore > 0.1 else { return nil }
            
            let score = calculateScore(
                visitCount: 1,
                lastVisited: entry.dateAdded,
                matchQuality: matchScore,
                sourceType: .bookmark
            )
            
            return AutofillSuggestion(
                url: entry.url,
                title: entry.title,
                favicon: entry.favicon,
                score: score,
                sourceType: .bookmark,
                visitCount: 1,
                lastVisited: entry.dateAdded
            )
        }
    }
    
    private func calculateScore(visitCount: Int, lastVisited: Date, matchQuality: Double, sourceType: SuggestionSourceType) -> Double {
        let frequencyScore = min(1.0, log(Double(visitCount) + 1) / log(100.0))
        let daysSinceVisit = Date().timeIntervalSince(lastVisited) / (24 * 60 * 60)
        let recencyScore = exp(-daysSinceVisit / 30.0)
        let baseScore = (frequencyScore * 0.4) + (recencyScore * 0.3) + (matchQuality * 0.3)
        return baseScore * sourceType.basePriority
    }
    
    private func fuzzyMatch(text: String, query: String) -> Double {
        let lowercaseText = text.lowercased()
        let lowercaseQuery = query.lowercased()
        
        if lowercaseText == lowercaseQuery { return 1.0 }
        if lowercaseText.hasPrefix(lowercaseQuery) { return 0.9 }
        if lowercaseText.contains(lowercaseQuery) { return 0.7 }
        
        let queryChars = Set(lowercaseQuery)
        let textChars = Set(lowercaseText)
        let intersection = queryChars.intersection(textChars)
        
        if intersection.count == queryChars.count {
            let matchRatio = Double(intersection.count) / Double(queryChars.count)
            let lengthPenalty = Double(lowercaseQuery.count) / Double(lowercaseText.count)
            return matchRatio * lengthPenalty * 0.5
        }
        
        return 0.0
    }
    
    private func removeDuplicates(from suggestions: [AutofillSuggestion]) -> [AutofillSuggestion] {
        var seen = Set<String>()
        return suggestions.filter { suggestion in
            let key = suggestion.url
            if seen.contains(key) {
                return false
            } else {
                seen.insert(key)
                return true
            }
        }
    }
    
    private func getCachedSuggestions(for query: String) -> [AutofillSuggestion]? {
        guard let timestamp = cacheTimestamps[query] as? Date,
              Date().timeIntervalSince(timestamp) < cacheTimeout,
              let cachedSuggestions = suggestionCache[query] else {
            return nil
        }
        return cachedSuggestions
    }
    
    private func cacheResults(query: String, suggestions: [AutofillSuggestion]) {
        suggestionCache[query] = suggestions
        cacheTimestamps[query] = Date()
        
        if suggestionCache.count > 100 {
            cleanupCache()
        }
    }
    
    private func cleanupCache() {
        let now = Date()
        let keysToRemove = cacheTimestamps.allKeys.compactMap { key -> String? in
            guard let timestamp = cacheTimestamps[key] as? Date,
                  now.timeIntervalSince(timestamp) > cacheTimeout else {
                return nil
            }
            return key as? String
        }
        
        for key in keysToRemove {
            suggestionCache.removeValue(forKey: key)
            cacheTimestamps.removeObject(forKey: key)
        }
    }
    
    private func clearCache() {
        suggestionCache.removeAll()
        cacheTimestamps.removeAllObjects()
    }
    
    private func loadMockData() {
        historyEntries = [
            HistoryEntry(url: "https://github.com", title: "GitHub", visitCount: 25, lastVisited: Date().addingTimeInterval(-3600), firstVisited: Date().addingTimeInterval(-86400 * 30)),
            HistoryEntry(url: "https://apple.com", title: "Apple", visitCount: 18, lastVisited: Date().addingTimeInterval(-7200), firstVisited: Date().addingTimeInterval(-86400 * 20)),
            HistoryEntry(url: "https://stackoverflow.com", title: "Stack Overflow", visitCount: 45, lastVisited: Date().addingTimeInterval(-1800), firstVisited: Date().addingTimeInterval(-86400 * 60)),
            HistoryEntry(url: "https://developer.apple.com", title: "Apple Developer", visitCount: 12, lastVisited: Date().addingTimeInterval(-14400), firstVisited: Date().addingTimeInterval(-86400 * 15)),
            HistoryEntry(url: "https://google.com", title: "Google", visitCount: 67, lastVisited: Date().addingTimeInterval(-900), firstVisited: Date().addingTimeInterval(-86400 * 90))
        ]
        
        bookmarkEntries = [
            BookmarkEntry(url: "https://github.com", title: "GitHub", dateAdded: Date().addingTimeInterval(-86400 * 10)),
            BookmarkEntry(url: "https://apple.com", title: "Apple", dateAdded: Date().addingTimeInterval(-86400 * 5)),
            BookmarkEntry(url: "https://developer.apple.com", title: "Apple Developer Documentation", dateAdded: Date().addingTimeInterval(-86400 * 3))
        ]
    }
}