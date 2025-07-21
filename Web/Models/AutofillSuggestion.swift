import SwiftUI
import Foundation

struct AutofillSuggestion: Identifiable, Hashable, Equatable {
    let id = UUID()
    let url: String
    let title: String
    let favicon: NSImage?
    let score: Double
    let sourceType: SuggestionSourceType
    let visitCount: Int
    let lastVisited: Date
    
    init(url: String, title: String, favicon: NSImage? = nil, score: Double, sourceType: SuggestionSourceType, visitCount: Int = 1, lastVisited: Date = Date()) {
        self.url = url
        self.title = title
        self.favicon = favicon
        self.score = score
        self.sourceType = sourceType
        self.visitCount = visitCount
        self.lastVisited = lastVisited
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
        hasher.combine(title)
        hasher.combine(sourceType)
    }
    
    static func == (lhs: AutofillSuggestion, rhs: AutofillSuggestion) -> Bool {
        return lhs.url == rhs.url && 
               lhs.title == rhs.title && 
               lhs.sourceType == rhs.sourceType
    }
}

enum SuggestionSourceType: String, CaseIterable, Hashable {
    case history = "history"
    case bookmark = "bookmark"
    case mostVisited = "mostVisited"
    case searchSuggestion = "searchSuggestion"
    
    var displayName: String {
        switch self {
        case .history: return "History"
        case .bookmark: return "Bookmark"
        case .mostVisited: return "Most Visited"
        case .searchSuggestion: return "Search"
        }
    }
    
    var iconName: String {
        switch self {
        case .history: return "clock.arrow.circlepath"
        case .bookmark: return "bookmark.fill"
        case .mostVisited: return "star.fill"
        case .searchSuggestion: return "magnifyingglass"
        }
    }
    
    var basePriority: Double {
        switch self {
        case .bookmark: return 1.0
        case .mostVisited: return 0.9
        case .history: return 0.7
        case .searchSuggestion: return 0.5
        }
    }
}

struct HistoryEntry: Identifiable, Hashable {
    let id = UUID()
    let url: String
    let title: String
    let visitCount: Int
    let lastVisited: Date
    let firstVisited: Date
    
    init(url: String, title: String, visitCount: Int = 1, lastVisited: Date = Date(), firstVisited: Date = Date()) {
        self.url = url
        self.title = title
        self.visitCount = visitCount
        self.lastVisited = lastVisited
        self.firstVisited = firstVisited
    }
}

struct BookmarkEntry: Identifiable, Hashable {
    let id = UUID()
    let url: String
    let title: String
    let favicon: NSImage?
    let dateAdded: Date
    
    init(url: String, title: String, favicon: NSImage? = nil, dateAdded: Date = Date()) {
        self.url = url
        self.title = title
        self.favicon = favicon
        self.dateAdded = dateAdded
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
        hasher.combine(title)
        hasher.combine(dateAdded)
    }
    
    static func == (lhs: BookmarkEntry, rhs: BookmarkEntry) -> Bool {
        return lhs.url == rhs.url && 
               lhs.title == rhs.title && 
               lhs.dateAdded == rhs.dateAdded
    }
}