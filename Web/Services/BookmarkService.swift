import CoreData
import SwiftUI
import Combine
import os.log

/// Service for managing bookmarks and bookmark folders
/// Handles CRUD operations, import/export, and organization
class BookmarkService: ObservableObject {
    static let shared = BookmarkService()
    
    private let logger = Logger(subsystem: "com.example.Web", category: "BookmarkService")
    private let coreDataStack = CoreDataStack.shared
    
    @Published var bookmarks: [Bookmark] = []
    @Published var folders: [BookmarkFolder] = []
    @Published var isLoading = false
    
    private init() {
        loadData()
    }
    
    // MARK: - Data Loading
    
    /// Load bookmarks and folders for UI
    private func loadData() {
        loadBookmarks()
        loadFolders()
    }
    
    private func loadBookmarks() {
        do {
            let request = Bookmark.fetchAllSorted(context: coreDataStack.viewContext)
            bookmarks = try coreDataStack.viewContext.fetch(request)
        } catch {
            logger.error("Failed to load bookmarks: \(error.localizedDescription)")
        }
    }
    
    private func loadFolders() {
        do {
            let request = BookmarkFolder.fetchRootFolders(context: coreDataStack.viewContext)
            folders = try coreDataStack.viewContext.fetch(request)
        } catch {
            logger.error("Failed to load folders: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Bookmark Management
    
    /// Add a new bookmark
    func addBookmark(url: String, title: String, folder: BookmarkFolder? = nil) {
        guard !url.isEmpty else { return }
        
        // Check if bookmark already exists
        if bookmarkExists(url: url) {
            logger.warning("Bookmark already exists: \(url)")
            return
        }
        
        Task {
            do {
                try await coreDataStack.performBackgroundTask { context in
                    let folderInContext = folder != nil ? context.object(with: folder!.objectID) as? BookmarkFolder : nil
                    let bookmark = Bookmark(context: context, url: url, title: title.isEmpty ? url : title, folder: folderInContext)
                    bookmark.sortOrder = Bookmark.nextSortOrder(in: folderInContext, context: context)
                    
                    self.logger.debug("Created bookmark: \(title) - \(url)")
                }
                
                await MainActor.run {
                    loadData()
                }
            } catch {
                logger.error("Failed to add bookmark: \(error.localizedDescription)")
            }
        }
    }
    
    /// Update an existing bookmark
    func updateBookmark(_ bookmark: Bookmark, title: String, url: String, folder: BookmarkFolder? = nil) {
        bookmark.title = title.isEmpty ? url : title
        bookmark.url = url
        bookmark.folder = folder
        
        coreDataStack.save()
        loadData()
        logger.debug("Updated bookmark: \(title)")
    }
    
    /// Delete a bookmark
    func deleteBookmark(_ bookmark: Bookmark) {
        coreDataStack.viewContext.delete(bookmark)
        coreDataStack.save()
        loadData()
        logger.debug("Deleted bookmark: \(bookmark.title)")
    }
    
    /// Move bookmark to different folder
    func moveBookmark(_ bookmark: Bookmark, to folder: BookmarkFolder?) {
        bookmark.folder = folder
        bookmark.sortOrder = Bookmark.nextSortOrder(in: folder, context: coreDataStack.viewContext)
        
        coreDataStack.save()
        loadData()
        logger.debug("Moved bookmark \(bookmark.title) to folder: \(folder?.name ?? "root")")
    }
    
    /// Reorder bookmarks within a folder
    func reorderBookmarks(_ bookmarks: [Bookmark], in folder: BookmarkFolder?) {
        for (index, bookmark) in bookmarks.enumerated() {
            bookmark.sortOrder = Int32(index)
        }
        
        coreDataStack.save()
        loadData()
        logger.debug("Reordered \(bookmarks.count) bookmarks in folder: \(folder?.name ?? "root")")
    }
    
    /// Update bookmark favicon
    func updateFavicon(for bookmark: Bookmark, data: Data) {
        bookmark.faviconData = data
        coreDataStack.save()
        logger.debug("Updated favicon for bookmark: \(bookmark.title)")
    }
    
    // MARK: - Folder Management
    
    /// Create a new folder
    func createFolder(name: String, parentFolder: BookmarkFolder? = nil) {
        guard !name.isEmpty else { return }
        
        // Check if folder already exists in the same parent
        if folderExists(name: name, in: parentFolder) {
            logger.warning("Folder already exists: \(name)")
            return
        }
        
        Task {
            do {
                try await coreDataStack.performBackgroundTask { context in
                    let parentInContext = parentFolder != nil ? context.object(with: parentFolder!.objectID) as? BookmarkFolder : nil
                    _ = BookmarkFolder(context: context, name: name, parentFolder: parentInContext)
                    
                    self.logger.debug("Created folder: \(name)")
                }
                
                await MainActor.run {
                    loadData()
                }
            } catch {
                logger.error("Failed to create folder: \(error.localizedDescription)")
            }
        }
    }
    
    /// Update folder name
    func updateFolder(_ folder: BookmarkFolder, name: String) {
        guard !name.isEmpty else { return }
        
        folder.name = name
        coreDataStack.save()
        loadData()
        logger.debug("Updated folder name to: \(name)")
    }
    
    /// Delete a folder (and optionally its contents)
    func deleteFolder(_ folder: BookmarkFolder, deleteContents: Bool = false) {
        if deleteContents {
            // Delete all bookmarks and subfolders
            for bookmark in folder.bookmarksArray {
                coreDataStack.viewContext.delete(bookmark)
            }
            for subfolder in folder.subfoldersArray {
                deleteFolder(subfolder, deleteContents: true)
            }
        } else {
            // Move contents to parent folder
            let parentFolder = folder.parentFolder
            for bookmark in folder.bookmarksArray {
                bookmark.folder = parentFolder
            }
            for subfolder in folder.subfoldersArray {
                subfolder.parentFolder = parentFolder
            }
        }
        
        coreDataStack.viewContext.delete(folder)
        coreDataStack.save()
        loadData()
        logger.debug("Deleted folder: \(folder.name)")
    }
    
    /// Move folder to different parent
    func moveFolder(_ folder: BookmarkFolder, to parentFolder: BookmarkFolder?) {
        folder.parentFolder = parentFolder
        folder.sortOrder = BookmarkFolder.nextSortOrder(in: parentFolder, context: coreDataStack.viewContext)
        
        coreDataStack.save()
        loadData()
        logger.debug("Moved folder \(folder.name) to: \(parentFolder?.name ?? "root")")
    }
    
    // MARK: - Search and Retrieval
    
    /// Search bookmarks by query
    func searchBookmarks(query: String) -> [Bookmark] {
        guard !query.isEmpty else { return bookmarks }
        
        do {
            let request = Bookmark.fetchMatching(query: query, context: coreDataStack.viewContext)
            return try coreDataStack.viewContext.fetch(request)
        } catch {
            logger.error("Failed to search bookmarks: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Get bookmarks in a specific folder
    func getBookmarks(in folder: BookmarkFolder?) -> [Bookmark] {
        do {
            let request = Bookmark.fetchInFolder(folder, context: coreDataStack.viewContext)
            return try coreDataStack.viewContext.fetch(request)
        } catch {
            logger.error("Failed to get bookmarks in folder: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Get subfolders of a folder
    func getSubfolders(of folder: BookmarkFolder?) -> [BookmarkFolder] {
        if let folder = folder {
            return folder.subfoldersArray
        } else {
            return folders
        }
    }
    
    /// Get all bookmarks (flat list for export/search)
    func getAllBookmarks() -> [Bookmark] {
        do {
            let request = Bookmark.fetchAllSorted(context: coreDataStack.viewContext)
            return try coreDataStack.viewContext.fetch(request)
        } catch {
            logger.error("Failed to get all bookmarks: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Get frequently accessed bookmarks
    func getFavoriteBookmarks(limit: Int = 10) -> [Bookmark] {
        // For now, return most recent bookmarks
        // In the future, could track access frequency
        let sortedBookmarks = bookmarks.sorted { $0.creationDate > $1.creationDate }
        return Array(sortedBookmarks.prefix(limit))
    }
    
    // MARK: - Import/Export
    
    /// Export bookmarks to HTML format (Netscape Bookmark File Format)
    func exportBookmarksToHTML() -> String {
        let allBookmarks = getAllBookmarks()
        let allFolders = getAllFolders()
        
        var html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>
        """
        
        // Export root bookmarks
        let rootBookmarks = getBookmarks(in: nil)
        for bookmark in rootBookmarks {
            html += generateBookmarkHTML(bookmark)
        }
        
        // Export folders recursively
        let rootFolders = getSubfolders(of: nil)
        for folder in rootFolders {
            html += generateFolderHTML(folder)
        }
        
        html += "</DL><p>"
        
        logger.info("Exported \(allBookmarks.count) bookmarks and \(allFolders.count) folders to HTML")
        return html
    }
    
    private func generateBookmarkHTML(_ bookmark: Bookmark) -> String {
        let timestamp = Int(bookmark.creationDate.timeIntervalSince1970)
        return "    <DT><A HREF=\"\(bookmark.url)\" ADD_DATE=\"\(timestamp)\">\(bookmark.title)</A>\n"
    }
    
    private func generateFolderHTML(_ folder: BookmarkFolder, depth: Int = 1) -> String {
        let indent = String(repeating: "    ", count: depth)
        let timestamp = Int(folder.creationDate.timeIntervalSince1970)
        
        var html = "\(indent)<DT><H3 ADD_DATE=\"\(timestamp)\">\(folder.name)</H3>\n"
        html += "\(indent)<DL><p>\n"
        
        // Add bookmarks in folder
        let folderBookmarks = getBookmarks(in: folder)
        for bookmark in folderBookmarks {
            html += "\(indent)    <DT><A HREF=\"\(bookmark.url)\" ADD_DATE=\"\(Int(bookmark.creationDate.timeIntervalSince1970))\">\(bookmark.title)</A>\n"
        }
        
        // Add subfolders recursively
        let subfolders = getSubfolders(of: folder)
        for subfolder in subfolders {
            html += generateFolderHTML(subfolder, depth: depth + 1)
        }
        
        html += "\(indent)</DL><p>\n"
        return html
    }
    
    /// Import bookmarks from HTML format
    func importBookmarksFromHTML(_ htmlContent: String) {
        // Basic HTML bookmark parsing
        // This is a simplified implementation - full parsing would be more complex
        let lines = htmlContent.components(separatedBy: .newlines)
        var currentFolder: BookmarkFolder? = nil
        var folderStack: [BookmarkFolder] = []
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if trimmedLine.contains("<H3") {
                // Folder
                if let nameRange = trimmedLine.range(of: ">"),
                   let endRange = trimmedLine.range(of: "</H3>") {
                    let folderName = String(trimmedLine[nameRange.upperBound..<endRange.lowerBound])
                    createFolder(name: folderName, parentFolder: currentFolder)
                    
                    // Update current folder for nesting
                    if let newFolder = BookmarkFolder.findByName(folderName, in: currentFolder, context: coreDataStack.viewContext) {
                        folderStack.append(newFolder)
                        currentFolder = newFolder
                    }
                }
            } else if trimmedLine.contains("<A HREF=") {
                // Bookmark
                if let hrefStart = trimmedLine.range(of: "HREF=\""),
                   let hrefEnd = trimmedLine.range(of: "\"", range: hrefStart.upperBound..<trimmedLine.endIndex),
                   let titleStart = trimmedLine.range(of: ">", range: hrefEnd.upperBound..<trimmedLine.endIndex),
                   let titleEnd = trimmedLine.range(of: "</A>", range: titleStart.upperBound..<trimmedLine.endIndex) {
                    
                    let url = String(trimmedLine[hrefStart.upperBound..<hrefEnd.lowerBound])
                    let title = String(trimmedLine[titleStart.upperBound..<titleEnd.lowerBound])
                    
                    addBookmark(url: url, title: title, folder: currentFolder)
                }
            } else if trimmedLine.contains("</DL>") && !folderStack.isEmpty {
                // End of folder
                folderStack.removeLast()
                currentFolder = folderStack.last
            }
        }
        
        logger.info("Imported bookmarks from HTML")
    }
    
    // MARK: - Helper Methods
    
    private func bookmarkExists(url: String) -> Bool {
        return Bookmark.findByURL(url, context: coreDataStack.viewContext) != nil
    }
    
    private func folderExists(name: String, in parentFolder: BookmarkFolder?) -> Bool {
        return BookmarkFolder.findByName(name, in: parentFolder, context: coreDataStack.viewContext) != nil
    }
    
    private func getAllFolders() -> [BookmarkFolder] {
        do {
            let request = BookmarkFolder.fetchRequest()
            return try coreDataStack.viewContext.fetch(request)
        } catch {
            logger.error("Failed to get all folders: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Quick bookmark current page
    func quickBookmark(url: String, title: String?) {
        let bookmarkTitle = title?.isEmpty == false ? title! : url
        addBookmark(url: url, title: bookmarkTitle)
        logger.info("Quick bookmarked: \(bookmarkTitle)")
    }
    
    /// Check if URL is bookmarked
    func isBookmarked(url: String) -> Bool {
        return bookmarkExists(url: url)
    }
}