import CoreData
import SwiftUI
import os.log

/// Core Data stack manager for the Web browser
/// Provides shared instance with lazy-loaded persistent container
class CoreDataStack: ObservableObject {
    static let shared = CoreDataStack()
    
    private let logger = Logger(subsystem: "com.example.Web", category: "CoreData")
    
    /// Main managed object context for UI operations
    lazy var viewContext: NSManagedObjectContext = {
        let context = persistentContainer.viewContext
        context.automaticallyMergesChangesFromParent = true
        return context
    }()
    
    /// Background context for heavy operations
    lazy var backgroundContext: NSManagedObjectContext = {
        let context = persistentContainer.newBackgroundContext()
        context.automaticallyMergesChangesFromParent = true
        return context
    }()
    
    /// Persistent container with programmatic model creation
    lazy var persistentContainer: NSPersistentContainer = {
        let model = createManagedObjectModel()
        let container = NSPersistentContainer(name: "Web", managedObjectModel: model)
        
        container.loadPersistentStores { storeDescription, error in
            if let error = error {
                self.logger.error("Core Data failed to load store: \(error.localizedDescription)")
                // In production, you might want to handle this more gracefully
                fatalError("Core Data error: \(error)")
            } else {
                self.logger.info("Core Data store loaded successfully: \(storeDescription.url?.lastPathComponent ?? "unknown")")
            }
        }
        
        // Enable automatic merging of changes
        container.viewContext.automaticallyMergesChangesFromParent = true
        
        return container
    }()
    
    /// Create managed object model programmatically
    private func createManagedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        
        // Create HistoryItem entity
        let historyEntity = NSEntityDescription()
        historyEntity.name = "HistoryItem"
        historyEntity.managedObjectClassName = "HistoryItem"
        
        let historyIdAttribute = NSAttributeDescription()
        historyIdAttribute.name = "id"
        historyIdAttribute.attributeType = .UUIDAttributeType
        historyIdAttribute.isOptional = false
        
        let historyUrlAttribute = NSAttributeDescription()
        historyUrlAttribute.name = "url"
        historyUrlAttribute.attributeType = .stringAttributeType
        historyUrlAttribute.isOptional = false
        
        let historyTitleAttribute = NSAttributeDescription()
        historyTitleAttribute.name = "title"
        historyTitleAttribute.attributeType = .stringAttributeType
        historyTitleAttribute.isOptional = true
        
        let historyLastVisitDateAttribute = NSAttributeDescription()
        historyLastVisitDateAttribute.name = "lastVisitDate"
        historyLastVisitDateAttribute.attributeType = .dateAttributeType
        historyLastVisitDateAttribute.isOptional = false
        
        let historyVisitCountAttribute = NSAttributeDescription()
        historyVisitCountAttribute.name = "visitCount"
        historyVisitCountAttribute.attributeType = .integer32AttributeType
        historyVisitCountAttribute.defaultValue = 1
        historyVisitCountAttribute.isOptional = false
        
        let historyFaviconDataAttribute = NSAttributeDescription()
        historyFaviconDataAttribute.name = "faviconData"
        historyFaviconDataAttribute.attributeType = .binaryDataAttributeType
        historyFaviconDataAttribute.isOptional = true
        
        historyEntity.properties = [
            historyIdAttribute,
            historyUrlAttribute,
            historyTitleAttribute,
            historyLastVisitDateAttribute,
            historyVisitCountAttribute,
            historyFaviconDataAttribute
        ]
        
        // Create BookmarkFolder entity
        let folderEntity = NSEntityDescription()
        folderEntity.name = "BookmarkFolder"
        folderEntity.managedObjectClassName = "BookmarkFolder"
        
        let folderIdAttribute = NSAttributeDescription()
        folderIdAttribute.name = "id"
        folderIdAttribute.attributeType = .UUIDAttributeType
        folderIdAttribute.isOptional = false
        
        let folderNameAttribute = NSAttributeDescription()
        folderNameAttribute.name = "name"
        folderNameAttribute.attributeType = .stringAttributeType
        folderNameAttribute.isOptional = false
        
        let folderCreationDateAttribute = NSAttributeDescription()
        folderCreationDateAttribute.name = "creationDate"
        folderCreationDateAttribute.attributeType = .dateAttributeType
        folderCreationDateAttribute.isOptional = false
        
        let folderSortOrderAttribute = NSAttributeDescription()
        folderSortOrderAttribute.name = "sortOrder"
        folderSortOrderAttribute.attributeType = .integer32AttributeType
        folderSortOrderAttribute.defaultValue = 0
        folderSortOrderAttribute.isOptional = false
        
        folderEntity.properties = [
            folderIdAttribute,
            folderNameAttribute,
            folderCreationDateAttribute,
            folderSortOrderAttribute
        ]
        
        // Create Bookmark entity
        let bookmarkEntity = NSEntityDescription()
        bookmarkEntity.name = "Bookmark"
        bookmarkEntity.managedObjectClassName = "Bookmark"
        
        let bookmarkIdAttribute = NSAttributeDescription()
        bookmarkIdAttribute.name = "id"
        bookmarkIdAttribute.attributeType = .UUIDAttributeType
        bookmarkIdAttribute.isOptional = false
        
        let bookmarkUrlAttribute = NSAttributeDescription()
        bookmarkUrlAttribute.name = "url"
        bookmarkUrlAttribute.attributeType = .stringAttributeType
        bookmarkUrlAttribute.isOptional = false
        
        let bookmarkTitleAttribute = NSAttributeDescription()
        bookmarkTitleAttribute.name = "title"
        bookmarkTitleAttribute.attributeType = .stringAttributeType
        bookmarkTitleAttribute.isOptional = false
        
        let bookmarkCreationDateAttribute = NSAttributeDescription()
        bookmarkCreationDateAttribute.name = "creationDate"
        bookmarkCreationDateAttribute.attributeType = .dateAttributeType
        bookmarkCreationDateAttribute.isOptional = false
        
        let bookmarkSortOrderAttribute = NSAttributeDescription()
        bookmarkSortOrderAttribute.name = "sortOrder"
        bookmarkSortOrderAttribute.attributeType = .integer32AttributeType
        bookmarkSortOrderAttribute.defaultValue = 0
        bookmarkSortOrderAttribute.isOptional = false
        
        let bookmarkFaviconDataAttribute = NSAttributeDescription()
        bookmarkFaviconDataAttribute.name = "faviconData"
        bookmarkFaviconDataAttribute.attributeType = .binaryDataAttributeType
        bookmarkFaviconDataAttribute.isOptional = true
        
        bookmarkEntity.properties = [
            bookmarkIdAttribute,
            bookmarkUrlAttribute,
            bookmarkTitleAttribute,
            bookmarkCreationDateAttribute,
            bookmarkSortOrderAttribute,
            bookmarkFaviconDataAttribute
        ]
        
        // Create relationships
        let folderBookmarksRelationship = NSRelationshipDescription()
        folderBookmarksRelationship.name = "bookmarks"
        folderBookmarksRelationship.destinationEntity = bookmarkEntity
        folderBookmarksRelationship.minCount = 0
        folderBookmarksRelationship.maxCount = 0 // To many
        folderBookmarksRelationship.deleteRule = .cascadeDeleteRule
        
        let bookmarkFolderRelationship = NSRelationshipDescription()
        bookmarkFolderRelationship.name = "folder"
        bookmarkFolderRelationship.destinationEntity = folderEntity
        bookmarkFolderRelationship.minCount = 0
        bookmarkFolderRelationship.maxCount = 1
        bookmarkFolderRelationship.deleteRule = .nullifyDeleteRule
        
        let folderParentRelationship = NSRelationshipDescription()
        folderParentRelationship.name = "parentFolder"
        folderParentRelationship.destinationEntity = folderEntity
        folderParentRelationship.minCount = 0
        folderParentRelationship.maxCount = 1
        folderParentRelationship.deleteRule = .nullifyDeleteRule
        
        let folderSubfoldersRelationship = NSRelationshipDescription()
        folderSubfoldersRelationship.name = "subfolders"
        folderSubfoldersRelationship.destinationEntity = folderEntity
        folderSubfoldersRelationship.minCount = 0
        folderSubfoldersRelationship.maxCount = 0 // To many
        folderSubfoldersRelationship.deleteRule = .cascadeDeleteRule
        
        // Set inverse relationships
        folderBookmarksRelationship.inverseRelationship = bookmarkFolderRelationship
        bookmarkFolderRelationship.inverseRelationship = folderBookmarksRelationship
        folderParentRelationship.inverseRelationship = folderSubfoldersRelationship
        folderSubfoldersRelationship.inverseRelationship = folderParentRelationship
        
        // Add relationships to entities
        folderEntity.properties.append(contentsOf: [folderBookmarksRelationship, folderParentRelationship, folderSubfoldersRelationship])
        bookmarkEntity.properties.append(bookmarkFolderRelationship)
        
        model.entities = [historyEntity, folderEntity, bookmarkEntity]
        
        return model
    }
    
    private init() {}
    
    /// Save the view context with error handling
    func save() {
        guard viewContext.hasChanges else { return }
        
        do {
            try viewContext.save()
            logger.debug("Core Data context saved successfully")
        } catch {
            logger.error("Failed to save Core Data context: \(error.localizedDescription)")
        }
    }
    
    /// Save a specific context with error handling
    func save(context: NSManagedObjectContext) {
        guard context.hasChanges else { return }
        
        do {
            try context.save()
            logger.debug("Core Data context saved successfully")
        } catch {
            logger.error("Failed to save Core Data context: \(error.localizedDescription)")
        }
    }
    
    /// Perform background task with automatic saving
    func performBackgroundTask<T>(_ block: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            backgroundContext.perform {
                do {
                    let result = try block(self.backgroundContext)
                    
                    if self.backgroundContext.hasChanges {
                        try self.backgroundContext.save()
                    }
                    
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Delete and recreate the persistent store (for development/testing)
    func resetStore() {
        guard let storeURL = persistentContainer.persistentStoreDescriptions.first?.url else {
            logger.error("Cannot reset store: no store URL found")
            return
        }
        
        do {
            try persistentContainer.persistentStoreCoordinator.destroyPersistentStore(
                at: storeURL,
                ofType: NSSQLiteStoreType,
                options: nil
            )
            
            // Recreate the store
            persistentContainer.loadPersistentStores { _, error in
                if let error = error {
                    self.logger.error("Failed to recreate store: \(error.localizedDescription)")
                } else {
                    self.logger.info("Store reset successfully")
                }
            }
        } catch {
            logger.error("Failed to reset store: \(error.localizedDescription)")
        }
    }
}

/// SwiftUI environment key for Core Data context
struct CoreDataContextKey: EnvironmentKey {
    static let defaultValue: NSManagedObjectContext = CoreDataStack.shared.viewContext
}

extension EnvironmentValues {
    var managedObjectContext: NSManagedObjectContext {
        get { self[CoreDataContextKey.self] }
        set { self[CoreDataContextKey.self] = newValue }
    }
}