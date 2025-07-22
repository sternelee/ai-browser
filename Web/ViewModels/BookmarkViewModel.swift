import SwiftUI
import Combine
import CoreData
import os.log

/// ViewModel for managing bookmark view state and operations
/// Provides reactive data binding and smooth interaction handling
class BookmarkViewModel: ObservableObject {
    // Published properties for UI binding
    @Published var searchText = ""
    @Published var selectedFolder: BookmarkFolder?
    @Published var filteredBookmarks: [Bookmark] = []
    @Published var rootFolders: [BookmarkFolder] = []
    @Published var isLoading = false
    @Published var draggedBookmark: Bookmark?
    @Published var hoveredFolder: BookmarkFolder?
    
    // Services
    private let bookmarkService = BookmarkService.shared
    private let logger = Logger(subsystem: "com.example.Web", category: "BookmarkViewModel")
    
    // Combine cancellables
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupPublishers()
        loadData()
    }
    
    private func setupPublishers() {
        // Reactive search with debouncing
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.updateFilteredBookmarks()
            }
            .store(in: &cancellables)
        
        // React to folder selection changes
        $selectedFolder
            .sink { [weak self] _ in
                self?.updateFilteredBookmarks()
            }
            .store(in: &cancellables)
        
        // Listen to bookmark service updates
        bookmarkService.$bookmarks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateFilteredBookmarks()
            }
            .store(in: &cancellables)
        
        bookmarkService.$folders
            .receive(on: DispatchQueue.main)
            .sink { [weak self] folders in
                self?.rootFolders = folders
            }
            .store(in: &cancellables)
    }
    
    private func loadData() {
        isLoading = true
        updateFilteredBookmarks()
        rootFolders = bookmarkService.getSubfolders(of: nil)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.isLoading = false
        }
    }
    
    private func updateFilteredBookmarks() {
        let bookmarks = bookmarkService.getBookmarks(in: selectedFolder)
        
        if searchText.isEmpty {
            filteredBookmarks = bookmarks
        } else {
            filteredBookmarks = bookmarks.filter { bookmark in
                bookmark.title.localizedCaseInsensitiveContains(searchText) ||
                bookmark.url.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        logger.debug("Updated filtered bookmarks: \(self.filteredBookmarks.count) items")
    }
    
    // MARK: - Public Methods
    
    func selectFolder(_ folder: BookmarkFolder?) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            selectedFolder = folder
        }
        logger.debug("Selected folder: \(folder?.name ?? "All Bookmarks")")
    }
    
    func createFolder(name: String, parentFolder: BookmarkFolder? = nil) {
        guard !name.isEmpty else { return }
        
        bookmarkService.createFolder(name: name, parentFolder: parentFolder)
        logger.info("Created folder: \(name)")
        
        // Refresh data
        rootFolders = bookmarkService.getSubfolders(of: nil)
    }
    
    func addBookmark(url: String, title: String, folder: BookmarkFolder? = nil) {
        guard !url.isEmpty && !title.isEmpty else { return }
        
        bookmarkService.addBookmark(url: url, title: title, folder: folder)
        logger.info("Added bookmark: \(title)")
    }
    
    func addCurrentPageBookmark() {
        // In real implementation, this would get current tab info
        // For now, we'll use a placeholder
        if let currentTab = getCurrentTabInfo() {
            addBookmark(url: currentTab.url, title: currentTab.title, folder: selectedFolder)
        } else {
            // Fallback for testing
            let timestamp = Int(Date().timeIntervalSince1970)
            addBookmark(
                url: "https://example.com/page\(timestamp)",
                title: "Example Page \(timestamp)",
                folder: selectedFolder
            )
        }
    }
    
    func updateBookmark(_ bookmark: Bookmark, title: String, url: String, folder: BookmarkFolder? = nil) {
        bookmarkService.updateBookmark(bookmark, title: title, url: url, folder: folder)
        logger.info("Updated bookmark: \(title)")
    }
    
    func deleteBookmark(_ bookmark: Bookmark) {
        bookmarkService.deleteBookmark(bookmark)
        logger.info("Deleted bookmark: \(bookmark.title)")
    }
    
    func deleteFolder(_ folder: BookmarkFolder, deleteContents: Bool = false) {
        bookmarkService.deleteFolder(folder, deleteContents: deleteContents)
        logger.info("Deleted folder: \(folder.name)")
        
        // If the deleted folder was selected, reset to all bookmarks
        if selectedFolder?.id == folder.id {
            selectedFolder = nil
        }
        
        // Refresh folders
        rootFolders = bookmarkService.getSubfolders(of: nil)
    }
    
    func moveBookmark(_ bookmark: Bookmark, to folder: BookmarkFolder?) {
        bookmarkService.moveBookmark(bookmark, to: folder)
        logger.info("Moved bookmark \(bookmark.title) to folder: \(folder?.name ?? "root")")
    }
    
    func reorderBookmarks(_ bookmarks: [Bookmark], in folder: BookmarkFolder?) {
        bookmarkService.reorderBookmarks(bookmarks, in: folder)
        logger.debug("Reordered \(bookmarks.count) bookmarks in folder: \(folder?.name ?? "root")")
    }
    
    func openBookmark(_ bookmark: Bookmark, inNewTab: Bool = false) {
        guard let url = URL(string: bookmark.url) else { return }
        
        if inNewTab {
            NotificationCenter.default.post(name: .createNewTabWithURL, object: url)
            logger.debug("Opening bookmark in new tab: \(bookmark.title)")
        } else {
            NotificationCenter.default.post(name: .navigateCurrentTab, object: url)
            logger.debug("Opening bookmark in current tab: \(bookmark.title)")
        }
    }
    
    func searchBookmarks(query: String) {
        searchText = query
    }
    
    func clearSearch() {
        searchText = ""
    }
    
    func refreshData() {
        isLoading = true
        loadData()
    }
    
    // MARK: - Drag and Drop Support
    
    func startDrag(for bookmark: Bookmark) {
        draggedBookmark = bookmark
        logger.debug("Started dragging bookmark: \(bookmark.title)")
    }
    
    func endDrag() {
        draggedBookmark = nil
    }
    
    func canDropBookmark(on folder: BookmarkFolder?) -> Bool {
        // Prevent dropping on the same folder
        guard let draggedBookmark = draggedBookmark else { return false }
        return draggedBookmark.folder?.id != folder?.id
    }
    
    func dropBookmark(on folder: BookmarkFolder?) {
        guard let bookmark = draggedBookmark else { return }
        
        if canDropBookmark(on: folder) {
            moveBookmark(bookmark, to: folder)
        }
        
        endDrag()
    }
    
    // MARK: - Utility Methods
    
    func getBookmarkStats() -> (totalBookmarks: Int, foldersCount: Int, selectedFolderCount: Int) {
        let totalBookmarks = bookmarkService.getAllBookmarks().count
        let foldersCount = getAllFoldersCount()
        let selectedFolderCount = filteredBookmarks.count
        
        return (totalBookmarks, foldersCount, selectedFolderCount)
    }
    
    func isBookmarked(url: String) -> Bool {
        return bookmarkService.isBookmarked(url: url)
    }
    
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
    
    func exportBookmarks() -> String {
        let htmlContent = bookmarkService.exportBookmarksToHTML()
        logger.info("Exported bookmarks to HTML format")
        return htmlContent
    }
    
    func importBookmarks(from htmlContent: String) {
        bookmarkService.importBookmarksFromHTML(htmlContent)
        logger.info("Imported bookmarks from HTML format")
        
        // Refresh data after import
        refreshData()
    }
    
    // MARK: - Helper Methods
    
    private func getCurrentTabInfo() -> (url: String, title: String)? {
        // This would integrate with TabManager to get current tab info
        // For now, return nil to use fallback
        return nil
    }
    
    private func getAllFoldersCount() -> Int {
        return bookmarkService.getAllBookmarks().count // This would be improved to count actual folders
    }
    
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    // MARK: - Folder Management
    
    func getFolderPath(_ folder: BookmarkFolder?) -> String {
        guard let folder = folder else { return "All Bookmarks" }
        return folder.fullPath
    }
    
    func getSubfolders(of folder: BookmarkFolder?) -> [BookmarkFolder] {
        return bookmarkService.getSubfolders(of: folder)
    }
    
    func canMoveFolder(_ folder: BookmarkFolder, to parentFolder: BookmarkFolder?) -> Bool {
        // Prevent circular references
        guard let parentFolder = parentFolder else { return true }
        
        var currentParent = parentFolder.parentFolder
        while currentParent != nil {
            if currentParent?.id == folder.id {
                return false
            }
            currentParent = currentParent?.parentFolder
        }
        
        return true
    }
}

// MARK: - Extensions

extension BookmarkViewModel {
    /// Get recently added bookmarks
    func getRecentBookmarks(limit: Int = 10) -> [Bookmark] {
        let allBookmarks = bookmarkService.getAllBookmarks()
        let sortedBookmarks = allBookmarks.sorted { $0.creationDate > $1.creationDate }
        return Array(sortedBookmarks.prefix(limit))
    }
    
    /// Get most visited bookmarks (based on how often they're bookmarked/accessed)
    func getFavoriteBookmarks(limit: Int = 10) -> [Bookmark] {
        return bookmarkService.getFavoriteBookmarks(limit: limit)
    }
    
    /// Check if a folder contains a specific URL
    func folderContains(folder: BookmarkFolder?, url: String) -> Bool {
        if let folder = folder {
            return folder.containsBookmarkWithURL(url)
        } else {
            return bookmarkService.isBookmarked(url: url)
        }
    }
}