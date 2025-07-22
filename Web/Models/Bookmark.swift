import CoreData
import Foundation

/// Core Data entity for bookmarks
@objc(Bookmark)
public class Bookmark: NSManagedObject {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Bookmark> {
        return NSFetchRequest<Bookmark>(entityName: "Bookmark")
    }
    
    @NSManaged public var id: UUID
    @NSManaged public var url: String
    @NSManaged public var title: String
    @NSManaged public var creationDate: Date
    @NSManaged public var sortOrder: Int32
    @NSManaged public var faviconData: Data?
    
    // Relationships
    @NSManaged public var folder: BookmarkFolder?
    
    /// Convenience initializer for creating new bookmarks
    convenience init(context: NSManagedObjectContext, url: String, title: String, folder: BookmarkFolder? = nil) {
        self.init(context: context)
        self.id = UUID()
        self.url = url
        self.title = title
        self.creationDate = Date()
        self.sortOrder = 0
        self.folder = folder
    }
    
    /// Get display title (fallback to URL if title is empty)
    var displayTitle: String {
        return title.isEmpty ? url : title
    }
    
    /// Check if bookmark is in root (no folder)
    var isInRoot: Bool {
        return folder == nil
    }
    
    /// Get folder name or "Bookmarks" for root
    var folderName: String {
        return folder?.name ?? "Bookmarks"
    }
    
    /// Update sort order for reordering
    func updateSortOrder(_ newOrder: Int32) {
        sortOrder = newOrder
    }
}

extension Bookmark {
    /// Fetch all bookmarks sorted by creation date
    static func fetchAllSorted(context: NSManagedObjectContext) -> NSFetchRequest<Bookmark> {
        let request = fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Bookmark.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \Bookmark.creationDate, ascending: false)
        ]
        return request
    }
    
    /// Fetch bookmarks in a specific folder
    static func fetchInFolder(_ folder: BookmarkFolder?, context: NSManagedObjectContext) -> NSFetchRequest<Bookmark> {
        let request = fetchRequest()
        if let folder = folder {
            request.predicate = NSPredicate(format: "folder == %@", folder)
        } else {
            request.predicate = NSPredicate(format: "folder == nil")
        }
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Bookmark.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \Bookmark.creationDate, ascending: false)
        ]
        return request
    }
    
    /// Fetch bookmarks matching search query
    static func fetchMatching(query: String, context: NSManagedObjectContext) -> NSFetchRequest<Bookmark> {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "title CONTAINS[cd] %@ OR url CONTAINS[cd] %@", query, query)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Bookmark.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \Bookmark.creationDate, ascending: false)
        ]
        return request
    }
    
    /// Find existing bookmark by URL
    static func findByURL(_ url: String, context: NSManagedObjectContext) -> Bookmark? {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "url == %@", url)
        request.fetchLimit = 1
        
        do {
            return try context.fetch(request).first
        } catch {
            return nil
        }
    }
    
    /// Get next sort order for a folder
    static func nextSortOrder(in folder: BookmarkFolder?, context: NSManagedObjectContext) -> Int32 {
        let request = fetchInFolder(folder, context: context)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Bookmark.sortOrder, ascending: false)]
        request.fetchLimit = 1
        
        do {
            if let lastBookmark = try context.fetch(request).first {
                return lastBookmark.sortOrder + 1
            }
            return 0
        } catch {
            return 0
        }
    }
}