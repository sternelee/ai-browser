# URL Bar Autofill System - Technical Specification

## Overview

The URL Bar Autofill System provides intelligent, real-time suggestions as users type in the address bar. It combines history, bookmarks, and browsing patterns to deliver the most relevant suggestions with a minimal, next-gen UX that rivals Safari and Arc Browser.

## Core Features

### 1. Data Sources & Prioritization
- **History Items**: URLs and page titles from browsing history
- **Bookmarks**: Saved bookmarks with titles and URLs  
- **Most Visited**: Sites with high visit frequency
- **Recent Sites**: Recently visited pages (last 7 days prioritized)
- **Search Suggestions**: Google search suggestions (Phase 2)

### 2. Smart Ranking Algorithm
```
Score = (frequency_score * 0.4) + (recency_score * 0.3) + (match_quality * 0.3)

Where:
- frequency_score: Visit count normalized (0-1)
- recency_score: Time since last visit, exponential decay
- match_quality: String matching quality (exact > prefix > substring > fuzzy)
```

### 3. Real-Time Filtering
- **Instant Response**: < 50ms from keystroke to UI update
- **Fuzzy Matching**: Supports typos and partial matches
- **Multi-Field Search**: Searches both URL and page title
- **Smart Deduplication**: Eliminates duplicate URLs
- **Live Updates**: Results update as user continues typing

## Technical Architecture

### Data Models

```swift
// AutofillSuggestion.swift
struct AutofillSuggestion: Identifiable, Hashable {
    let id = UUID()
    let url: String
    let title: String
    let favicon: NSImage?
    let score: Double
    let sourceType: SuggestionSourceType
    let visitCount: Int
    let lastVisited: Date
}

enum SuggestionSourceType {
    case history
    case bookmark
    case mostVisited
    case searchSuggestion
}
```

### Core Services

```swift
// AutofillService.swift
class AutofillService: ObservableObject {
    // Core functionality
    func getSuggestions(for query: String) async -> [AutofillSuggestion]
    func recordVisit(url: String, title: String)
    func addBookmark(url: String, title: String)
    
    // Ranking & filtering
    private func calculateScore(for suggestion: AutofillSuggestion, query: String) -> Double
    private func fuzzyMatch(text: String, query: String) -> Double
}
```

## UI/UX Design

### Visual Design
- **Glass Morphism**: Matches browser's glass aesthetic
- **Smooth Animations**: 0.2s spring animations for appearance/dismissal
- **Minimal Typography**: SF Pro Text, 13pt regular, 11pt secondary
- **Subtle Hierarchy**: Primary text (title), secondary (URL)
- **Favicon Integration**: 16x16 favicons with 4pt corner radius

### Interaction Design
- **Keyboard Navigation**: ↑↓ arrows to navigate, Enter to select, Esc to dismiss
- **Mouse Support**: Hover states with subtle background highlighting
- **Smart Selection**: First result auto-selected for instant Enter navigation
- **Progressive Loading**: Show immediate results, enhance with slower searches

### Suggestion List Layout
```
┌─────────────────────────────────────────┐
│ 🌐 Apple                               │ <- Favicon + Title (bold)
│    https://apple.com                   │ <- URL (secondary color)
├─────────────────────────────────────────┤
│ 🔍 apple stock price                   │ <- Search suggestion
│    Search Google                       │
└─────────────────────────────────────────┘
```

## Implementation Phases

### Phase 1: Core Autofill (Week 4.1)
- [x] Create AutofillService with Core Data integration
- [x] Implement basic history and bookmark suggestions
- [x] Add fuzzy matching algorithm
- [x] Create suggestion UI component with glass design
- [x] Integrate with existing URLBar component
- [x] Add keyboard navigation support

### Phase 1.1: Smart Ranking (Week 4.2)
- [ ] Implement frequency + recency scoring algorithm
- [ ] Add visit count tracking to history
- [ ] Create most visited sites calculation
- [ ] Add deduplication logic
- [ ] Performance optimization for large datasets

### Phase 1.2: Enhanced UX (Week 4.3)  
- [ ] Add smooth animations and transitions
- [ ] Implement favicon loading and caching
- [ ] Add hover states and visual feedback
- [ ] Create loading states for slower operations
- [ ] Add accessibility support (VoiceOver)

### Phase 2: Advanced Features (Future)
- [ ] Google search suggestions API integration
- [ ] Machine learning for personalized ranking
- [ ] Cross-device sync via iCloud
- [ ] Custom suggestion categories
- [ ] Advanced filtering options

## Data Storage

### Core Data Schema Extensions
```swift
// HistoryItem entity additions
@NSManaged public var visitCount: Int32
@NSManaged public var lastVisited: Date
@NSManaged public var searchableContent: String // title + url for indexing

// New AutofillCache entity for performance
@NSManaged public var query: String
@NSManaged public var cachedResults: Data // JSON encoded suggestions
@NSManaged public var cacheTimestamp: Date
```

### Performance Optimizations
- **Indexed Search**: Core Data NSFetchedResultsController with predicates
- **Result Caching**: Cache recent queries for 5 minutes
- **Background Processing**: Heavy ranking calculations off main thread
- **Lazy Loading**: Favicons loaded asynchronously
- **Memory Management**: LRU cache for suggestions (max 1000 items)

## Integration Points

### URLBar Component Updates
```swift
// URLBar.swift modifications needed
@State private var showingSuggestions = false
@State private var suggestions: [AutofillSuggestion] = []
@State private var selectedSuggestionIndex = 0

// New methods to add
private func handleTextChange()
private func handleKeyboardNavigation(key: KeyEquivalent)
private func selectSuggestion(at index: Int)
```

### BrowserView Integration
- Tab switching preserves autofill state
- Navigation events recorded for ranking
- Bookmark changes trigger suggestion updates

## Performance Requirements
- **Suggestion Display**: < 50ms from keystroke
- **Database Query**: < 20ms for typical datasets
- **Memory Usage**: < 10MB for suggestion system
- **Startup Impact**: < 100ms additional launch time

## Testing Strategy
- Unit tests for ranking algorithm accuracy
- UI tests for keyboard navigation flows  
- Performance tests for large history datasets
- Accessibility tests for VoiceOver support
- Integration tests with existing URLBar

## Security & Privacy
- No external API calls for basic functionality
- Local-only data processing and storage
- Respect private/incognito mode (no history recording)
- Secure handling of sensitive URLs
- User control over suggestion data retention

---

## Discovered During Work

### Issues Fixed (July 21, 2025)
- **Z-index/Layering Problem**: Fixed by using `.overlay()` with `.offset(y: 44)` and `.zIndex(1000)` directly on URLBar
- **Height Change Issues**: Previous wrapper approach caused top bar height changes. Fixed by using overlay positioning that doesn't affect parent layout
- **URL Navigation Broken**: Restored original URLBar navigation logic with proper autofill integration
- **Link Clicking Not Working**: Fixed by maintaining original suggestion selection flow within URLBar

### Technical Implementation Changes (Final)
- **Removed wrapper component**: Simplified back to single URLBar with overlay
- **Used proper SwiftUI overlay pattern**: `.overlay(alignment: .topLeading)` with `.offset(y: 44)`
- **Applied correct z-index**: `.zIndex(1000)` ensures suggestions appear above web content without layout impact
- **Fixed focus state handling**: `handleTextChange()` now only loads suggestions when `isURLBarFocused` is true
- **Corrected suggestion visibility**: Fixed `showingSuggestions` logic to properly show/hide dropdown
- **Maintained URL navigation**: Original `navigateToURL()` logic preserved with autofill recording

### Final Working Solution
The autofill system now works correctly with:
1. **URL Navigation**: Direct typing in URL bar navigates properly to URLs or performs Google search
2. **Autofill Visibility**: Suggestions appear when typing while focused, positioned below URLBar
3. **No Layout Issues**: Overlay positioning prevents height changes in parent container
4. **Proper Focus Management**: Suggestions only load and display when URL bar has focus

---

**Status:** Phase 1 Core Autofill Complete ✅
**Priority:** High (Essential browser feature)
**Estimated Duration:** 3 weeks (Phase 1 complete)
**Dependencies:** Existing URLBar, HistoryItem, Bookmark models