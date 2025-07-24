import SwiftUI
import Combine
import os.log

/// Service for handling keyboard shortcuts for history, bookmarks, and downloads
/// Provides a centralized way to manage keyboard shortcuts without overloading views
class KeyboardShortcutHandler: ObservableObject {
    static let shared = KeyboardShortcutHandler()
    
    private let logger = Logger(subsystem: "com.example.Web", category: "KeyboardShortcutHandler")
    private var cancellables = Set<AnyCancellable>()
    
    // Published properties for UI state - simplified without focus coordination
    @Published var showHistoryPanel = false
    @Published var showBookmarksPanel = false
    @Published var showDownloadsPanel = false
    @Published var showSettingsPanel = false
    @Published var showAboutPanel = false
    
    // UI positioning for panels - using center-based coordinates that will be made safe by PanelManager
    @Published var historyPanelPosition = CGPoint(x: 400, y: 300)
    @Published var bookmarksPanelPosition = CGPoint(x: 450, y: 320)
    @Published var downloadsPanelPosition = CGPoint(x: 500, y: 340)
    @Published var settingsPanelPosition = CGPoint(x: 550, y: 360)
    @Published var aboutPanelPosition = CGPoint(x: 600, y: 380)
    
    // Dependencies
    private let historyService = HistoryService.shared
    private let bookmarkService = BookmarkService.shared
    private let downloadManager = DownloadManager.shared
    
    private init() {
        setupNotificationHandlers()
    }
    
    private func setupNotificationHandlers() {
        // History shortcut (Cmd+Y)
        NotificationCenter.default.publisher(for: .showHistoryRequested)
            .sink { [weak self] _ in
                self?.handleShowHistory()
            }
            .store(in: &cancellables)
        
        // Bookmark shortcut (Cmd+D)
        NotificationCenter.default.publisher(for: .bookmarkPageRequested)
            .sink { [weak self] _ in
                self?.handleBookmarkPage()
            }
            .store(in: &cancellables)
        
        // Downloads shortcut (Cmd+Shift+J)
        NotificationCenter.default.publisher(for: .showDownloadsRequested)
            .sink { [weak self] _ in
                self?.handleShowDownloads()
            }
            .store(in: &cancellables)
        
        // Settings shortcut (Cmd+,)
        NotificationCenter.default.publisher(for: .showSettingsRequested)
            .sink { [weak self] _ in
                self?.handleShowSettings()
            }
            .store(in: &cancellables)
        
        // About shortcut
        NotificationCenter.default.publisher(for: .showAboutRequested)
            .sink { [weak self] _ in
                self?.handleShowAbout()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Handler Methods
    
    /// Handle Cmd+Y - Show History
    private func handleShowHistory() {
        showHistoryPanel.toggle()
        logger.info("History panel toggled: \(self.showHistoryPanel)")
        
        // For now, just log recent history
        let recentHistory = historyService.recentHistory.prefix(5)
        for item in recentHistory {
            logger.debug("Recent: \(item.displayTitle) - \(item.url)")
        }
    }
    
    /// Handle Cmd+D - Bookmark Current Page
    private func handleBookmarkPage() {
        // Toggle bookmark panel instead of just bookmarking
        showBookmarksPanel.toggle()
        logger.info("Bookmarks panel toggled: \(self.showBookmarksPanel)")
        
        // If showing panel, try to bookmark current page as well
        if showBookmarksPanel {
            NotificationCenter.default.post(
                name: .bookmarkCurrentPageRequested,
                object: nil
            )
        }
    }
    
    /// Handle Cmd+Shift+J - Show Downloads
    private func handleShowDownloads() {
        showDownloadsPanel.toggle()
        self.downloadManager.isVisible = showDownloadsPanel
        logger.info("Downloads panel toggled: \(self.showDownloadsPanel)")
        
        // Log current downloads
        logger.debug("Active downloads: \(self.downloadManager.totalActiveDownloads)")
        logger.debug("Total downloads in history: \(self.downloadManager.downloadHistory.count)")
    }
    
    /// Handle Cmd+, - Show Settings
    private func handleShowSettings() {
        showSettingsPanel.toggle()
        logger.info("Settings panel toggled: \(self.showSettingsPanel)")
    }
    
    /// Handle About - Show About
    private func handleShowAbout() {
        showAboutPanel.toggle()
        logger.info("About panel toggled: \(self.showAboutPanel)")
    }
    
    // MARK: - Public Interface
    
    /// Bookmark the current page with explicit tab info
    func bookmarkCurrentPage(url: String, title: String) {
        bookmarkService.quickBookmark(url: url, title: title)
        logger.info("Bookmarked: \(title)")
    }
    
    /// Get autofill suggestions for URL bar
    func getAutofillSuggestions(for query: String, limit: Int = 10) -> [HistoryItem] {
        return historyService.getAutofillSuggestions(for: query, limit: limit)
    }
    
    /// Search history
    func searchHistory(query: String) -> [HistoryItem] {
        return historyService.searchHistory(query: query)
    }
    
    /// Search bookmarks
    func searchBookmarks(query: String) -> [Bookmark] {
        return bookmarkService.searchBookmarks(query: query)
    }
    
    /// Get recent downloads
    func getRecentDownloads() -> [DownloadHistoryItem] {
        return Array(downloadManager.downloadHistory.prefix(20))
    }
    
    /// Check if URL is bookmarked
    func isBookmarked(url: String) -> Bool {
        return bookmarkService.isBookmarked(url: url)
    }
    
    /// Toggle bookmark for URL
    func toggleBookmark(url: String, title: String) {
        if isBookmarked(url: url) {
            // Find and remove bookmark
            if let bookmark = bookmarkService.getAllBookmarks().first(where: { $0.url == url }) {
                bookmarkService.deleteBookmark(bookmark)
                logger.info("Removed bookmark: \(title)")
            }
        } else {
            bookmarkService.quickBookmark(url: url, title: title)
            logger.info("Added bookmark: \(title)")
        }
    }
}