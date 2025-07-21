import Foundation
import AppKit

/// A single suggestion item returned by ``AutofillService``.
/// Implements `Identifiable` and `Hashable` so the list views can diff quickly.
public struct AutofillSuggestion: Identifiable, Hashable {
    public let id = UUID()
    /// Full URL string for navigation
    public let url: String
    /// Human-readable page title (may be the domain for bare URLs)
    public let title: String
    /// Optional favicon already resolved by the caller
    public let favicon: NSImage?
    /// Overall relevance score (0…1)
    public let score: Double
    /// Where the suggestion came from (history, bookmark …)
    public let sourceType: SuggestionSourceType
    /// Number of visits recorded for this URL (history)
    public var visitCount: Int
    /// Last time the URL was visited – used for ranking.
    public var lastVisited: Date

    public init(url: String,
                title: String,
                favicon: NSImage? = nil,
                score: Double = 0,
                sourceType: SuggestionSourceType,
                visitCount: Int = 0,
                lastVisited: Date = .distantPast) {
        self.url = url
        self.title = title
        self.favicon = favicon
        self.score = score
        self.sourceType = sourceType
        self.visitCount = visitCount
        self.lastVisited = lastVisited
    }
}

public enum SuggestionSourceType {
    case history
    case bookmark
    case mostVisited
    case searchSuggestion
} 