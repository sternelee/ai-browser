import CoreData
import Foundation

/// Core Data entity for browser history items
@objc(HistoryItem)
public class HistoryItem: NSManagedObject {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<HistoryItem> {
        return NSFetchRequest<HistoryItem>(entityName: "HistoryItem")
    }
    
    @NSManaged public var id: UUID
    @NSManaged public var url: String
    @NSManaged public var title: String?
    @NSManaged public var lastVisitDate: Date
    @NSManaged public var visitCount: Int32
    @NSManaged public var faviconData: Data?
    
    /// Convenience initializer for creating new history items
    convenience init(context: NSManagedObjectContext, url: String, title: String?) {
        self.init(context: context)
        self.id = UUID()
        self.url = url
        self.title = title
        self.lastVisitDate = Date()
        self.visitCount = 1
    }
    
    /// Increment visit count and update last visit date
    func recordVisit() {
        visitCount += 1
        lastVisitDate = Date()
    }
    
    /// Get display title (uses title if available, otherwise URL)
    var displayTitle: String {
        return title?.isEmpty == false ? title! : url
    }
    
    /// Check if this history item is from today
    var isFromToday: Bool {
        Calendar.current.isDateInToday(lastVisitDate)
    }
    
    /// Get relative date string (Today, Yesterday, etc.)
    var relativeDateString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: lastVisitDate, relativeTo: Date())
    }
}

extension HistoryItem {
    /// Fetch all history items sorted by last visit date (most recent first)
    static func fetchAllSorted(context: NSManagedObjectContext) -> NSFetchRequest<HistoryItem> {
        let request = fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \HistoryItem.lastVisitDate, ascending: false)]
        return request
    }
    
    /// Fetch history items matching search query
    static func fetchMatching(query: String, context: NSManagedObjectContext) -> NSFetchRequest<HistoryItem> {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "title CONTAINS[cd] %@ OR url CONTAINS[cd] %@", query, query)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \HistoryItem.lastVisitDate, ascending: false)]
        return request
    }
    
    /// Fetch history items from a specific date range
    static func fetchFromDateRange(from startDate: Date, to endDate: Date, context: NSManagedObjectContext) -> NSFetchRequest<HistoryItem> {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "lastVisitDate >= %@ AND lastVisitDate <= %@", startDate as NSDate, endDate as NSDate)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \HistoryItem.lastVisitDate, ascending: false)]
        return request
    }
    
    /// Find existing history item by URL
    static func findByURL(_ url: String, context: NSManagedObjectContext) -> HistoryItem? {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "url == %@", url)
        request.fetchLimit = 1
        
        do {
            return try context.fetch(request).first
        } catch {
            return nil
        }
    }
}