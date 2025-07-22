import CoreData
import Foundation

/// Core Data entity for bookmark folders
@objc(BookmarkFolder)
public class BookmarkFolder: NSManagedObject {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<BookmarkFolder> {
        return NSFetchRequest<BookmarkFolder>(entityName: "BookmarkFolder")
    }
    
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var creationDate: Date
    @NSManaged public var sortOrder: Int32
    
    // Relationships
    @NSManaged public var bookmarks: NSSet?
    @NSManaged public var parentFolder: BookmarkFolder?
    @NSManaged public var subfolders: NSSet?
    
    /// Convenience initializer for creating new folders
    convenience init(context: NSManagedObjectContext, name: String, parentFolder: BookmarkFolder? = nil) {
        self.init(context: context)
        self.id = UUID()
        self.name = name
        self.creationDate = Date()
        self.sortOrder = BookmarkFolder.nextSortOrder(in: parentFolder, context: context)
        self.parentFolder = parentFolder
    }
    
    /// Get bookmarks array (typed convenience)
    var bookmarksArray: [Bookmark] {
        let set = bookmarks as? Set<Bookmark> ?? []
        return set.sorted { $0.sortOrder < $1.sortOrder || ($0.sortOrder == $1.sortOrder && $0.creationDate > $1.creationDate) }
    }
    
    /// Get subfolders array (typed convenience)
    var subfoldersArray: [BookmarkFolder] {
        let set = subfolders as? Set<BookmarkFolder> ?? []
        return set.sorted { $0.sortOrder < $1.sortOrder || ($0.sortOrder == $1.sortOrder && $0.creationDate > $1.creationDate) }
    }
    
    /// Get total item count (bookmarks + subfolders)
    var totalItemCount: Int {
        return bookmarksArray.count + subfoldersArray.count
    }
    
    /// Check if folder is root level
    var isRootLevel: Bool {
        return parentFolder == nil
    }
    
    /// Get folder depth level
    var depthLevel: Int {
        var level = 0
        var currentFolder = parentFolder
        while currentFolder != nil {
            level += 1
            currentFolder = currentFolder?.parentFolder
        }
        return level
    }
    
    /// Get full path (for display)
    var fullPath: String {
        if let parent = parentFolder {
            return "\(parent.fullPath) > \(name)"
        }
        return name
    }
    
    /// Add bookmark to folder
    func addBookmark(_ bookmark: Bookmark) {
        bookmark.folder = self
        bookmark.sortOrder = Bookmark.nextSortOrder(in: self, context: managedObjectContext!)
    }
    
    /// Remove bookmark from folder
    func removeBookmark(_ bookmark: Bookmark) {
        bookmark.folder = nil
    }
    
    /// Add subfolder
    func addSubfolder(_ subfolder: BookmarkFolder) {
        subfolder.parentFolder = self
        subfolder.sortOrder = BookmarkFolder.nextSortOrder(in: self, context: managedObjectContext!)
    }
    
    /// Remove subfolder
    func removeSubfolder(_ subfolder: BookmarkFolder) {
        subfolder.parentFolder = nil
    }
}

extension BookmarkFolder {
    /// Fetch all root folders sorted by sort order
    static func fetchRootFolders(context: NSManagedObjectContext) -> NSFetchRequest<BookmarkFolder> {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "parentFolder == nil")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \BookmarkFolder.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \BookmarkFolder.creationDate, ascending: false)
        ]
        return request
    }
    
    /// Fetch subfolders of a specific folder
    static func fetchSubfolders(of parentFolder: BookmarkFolder, context: NSManagedObjectContext) -> NSFetchRequest<BookmarkFolder> {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "parentFolder == %@", parentFolder)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \BookmarkFolder.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \BookmarkFolder.creationDate, ascending: false)
        ]
        return request
    }
    
    /// Fetch folders matching search query
    static func fetchMatching(query: String, context: NSManagedObjectContext) -> NSFetchRequest<BookmarkFolder> {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "name CONTAINS[cd] %@", query)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \BookmarkFolder.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \BookmarkFolder.creationDate, ascending: false)
        ]
        return request
    }
    
    /// Find folder by name in specific parent (or root)
    static func findByName(_ name: String, in parentFolder: BookmarkFolder?, context: NSManagedObjectContext) -> BookmarkFolder? {
        let request = fetchRequest()
        if let parentFolder = parentFolder {
            request.predicate = NSPredicate(format: "name == %@ AND parentFolder == %@", name, parentFolder)
        } else {
            request.predicate = NSPredicate(format: "name == %@ AND parentFolder == nil", name)
        }
        request.fetchLimit = 1
        
        do {
            return try context.fetch(request).first
        } catch {
            return nil
        }
    }
    
    /// Get next sort order for a parent folder
    static func nextSortOrder(in parentFolder: BookmarkFolder?, context: NSManagedObjectContext) -> Int32 {
        let request: NSFetchRequest<BookmarkFolder>
        
        if let parentFolder = parentFolder {
            request = fetchSubfolders(of: parentFolder, context: context)
        } else {
            request = fetchRootFolders(context: context)
        }
        
        request.sortDescriptors = [NSSortDescriptor(keyPath: \BookmarkFolder.sortOrder, ascending: false)]
        request.fetchLimit = 1
        
        do {
            if let lastFolder = try context.fetch(request).first {
                return lastFolder.sortOrder + 1
            }
            return 0
        } catch {
            return 0
        }
    }
    
    /// Check if folder contains a specific bookmark URL (recursively)
    func containsBookmarkWithURL(_ url: String) -> Bool {
        // Check direct bookmarks
        for bookmark in bookmarksArray {
            if bookmark.url == url {
                return true
            }
        }
        
        // Check subfolders recursively
        for subfolder in subfoldersArray {
            if subfolder.containsBookmarkWithURL(url) {
                return true
            }
        }
        
        return false
    }
}