import CoreData
import CloudKit

// MARK: - Persistence Controller
final class PersistenceController: NSObject {
    // MARK: - Static Properties
    static let shared = PersistenceController()
    static let modelName = "SwiftNote_AI"
    
    // MARK: - Preview Support
    #if DEBUG
    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let viewContext = controller.container.viewContext
        
        // Create sample data
        let sampleNote = Note(context: viewContext)
        sampleNote.id = UUID()
        sampleNote.timestamp = Date()
        sampleNote.lastModified = Date()
        sampleNote.title = "Sample Note"
        sampleNote.originalContent = "This is a sample note".data(using: .utf8)
        sampleNote.sourceType = "text"
        sampleNote.isFavorite = false
        sampleNote.processingStatus = "completed"
        
        let sampleFolder = Folder(context: viewContext)
        sampleFolder.id = UUID()
        sampleFolder.name = "Sample Folder"
        sampleFolder.timestamp = Date()
        sampleFolder.color = "blue"
        
        do {
            try viewContext.save()
            print("🗄️ Persistence: Preview context populated successfully")
        } catch {
            let nsError = error as NSError
            print("🗄️ Persistence: Error creating preview data - \(nsError), \(nsError.userInfo)")
            fatalError("Failed to create preview data: \(nsError)")
        }
        
        return controller
    }()
    #endif
    
    // MARK: - Properties
    let container: NSPersistentCloudKitContainer
    private let storeDescription: NSPersistentStoreDescription
    
    // MARK: - Initialization
    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: Self.modelName)
        
        // Configure store description
        storeDescription = container.persistentStoreDescriptions.first!
        
        // In-memory store configuration
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
            #if DEBUG
            print("🗄️ Persistence: Initializing in-memory store")
            #endif
        }
        
        // Call super.init before any instance methods
        super.init()
        
        // Now we can safely call instance methods
        configureStoreDescription()
        configureMigration()
        
        // Load persistent stores
        container.loadPersistentStores { description, error in
            if let error = error as NSError? {
                #if DEBUG
                print("🗄️ Persistence: Failed to load persistent stores - \(error), \(error.userInfo)")
                #endif
                fatalError("Failed to load persistent stores: \(error)")
            }
            #if DEBUG
            print("🗄️ Persistence: Successfully loaded persistent store at: \(description.url?.absoluteString ?? "unknown")")
            #endif
        }
        
        setupContainer()
    }
    
    // MARK: - Store Configuration
    private func configureStoreDescription() {
        // Enable remote notifications
        storeDescription.setOption(true as NSNumber,
                                 forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        // Enable history tracking for cross-device sync
        storeDescription.setOption(true as NSNumber,
                                 forKey: NSPersistentHistoryTrackingKey)
        
        // Configure automatic cloud sync
        storeDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: "iCloud.com.yourapp.swiftnote"
        )
        
        print("🗄️ Persistence: Store description configured with CloudKit support")
    }
    
    // MARK: - Container Setup
    private func setupContainer() {
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        // Enable automatic cloud sync
        container.viewContext.automaticallyMergesChangesFromParent = true
        
        // Set up fetch batch size
        if let store = container.persistentStoreCoordinator.persistentStores.first {
            #if DEBUG
            print("🗄️ Persistence: Setting batch size metadata for store")
            #endif
            
            // Get existing metadata
            var metadata = store.metadata ?? [:]
            // Update batch size
            metadata["NSBatchSize"] = 100
            
            container.persistentStoreCoordinator.setMetadata(metadata, for: store)
            
            #if DEBUG
            print("🗄️ Persistence: Successfully set batch size metadata")
            #endif
        } else {
            #if DEBUG
            print("🗄️ Persistence: No persistent store found to set batch size")
            #endif
        }
        
        setupNotificationHandling()
        print("🗄️ Persistence: Container setup completed")
    }
    
    // MARK: - Background Context
    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }
    
    // MARK: - Notification Handling
    private func setupNotificationHandling() {
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: .main
        ) { notification in
            print("🗄️ Persistence: Remote change notification received")
            self.handleStoreRemoteChange(notification)
        }
    }
    
    private func handleStoreRemoteChange(_ notification: Notification) {
        container.viewContext.perform {
            self.container.viewContext.refreshAllObjects()
            print("🗄️ Persistence: Context refreshed after remote change")
        }
    }
    
    // MARK: - Save Context
    func saveContext() {
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
                print("🗄️ Persistence: Context saved successfully")
            } catch {
                let nsError = error as NSError
                print("🗄️ Persistence: Error saving context - \(nsError), \(nsError.userInfo)")
            }
        }
    }
    
    // MARK: - Error Handling
    private func handleError(_ error: Error, context: String) {
        print("🗄️ Persistence: Error in \(context) - \(error.localizedDescription)")
        
        if let nsError = error as NSError? {
            print("🗄️ Persistence: Detailed error info - \(nsError.userInfo)")
            
            // Handle specific error cases
            switch nsError.code {
            case NSPersistentStoreIncompatibleVersionHashError:
                handleIncompatibleStoreVersion()
            case NSMigrationMissingSourceModelError:
                handleMissingSourceModel()
            case NSPersistentStoreTimeoutError:
                handleStoreTimeout()
            default:
                break
            }
        }
    }
    
    // MARK: - Error Recovery
    private func handleIncompatibleStoreVersion() {
        print("🗄️ Persistence: Handling incompatible store version")
        // Implementation for store version recovery
    }
    
    private func handleMissingSourceModel() {
        print("🗄️ Persistence: Handling missing source model")
        // Implementation for missing model recovery
    }
    
    private func handleStoreTimeout() {
        print("🗄️ Persistence: Handling store timeout")
        // Implementation for timeout recovery
    }
}

// MARK: - CRUD Operations
extension PersistenceController {
    // Create
    func createNote(title: String, content: String, sourceType: String) throws -> Note {
        let context = container.viewContext
        
        #if DEBUG
        print("🗄️ CRUD: Creating new note with title: \(title)")
        #endif
        
        let note = Note(context: context)
        note.title = title
        note.originalContent = content.data(using: .utf8) // Convert String to Data
        note.sourceType = sourceType
        note.timestamp = Date()
        note.lastModified = Date()
        
        try context.save()
        
        #if DEBUG
        print("🗄️ CRUD: Successfully created note with title: \(title)")
        #endif
        
        return note
    }
    
    // Read
    func fetchNotes(matching predicate: NSPredicate? = nil) throws -> [Note] {
        let context = container.viewContext
        let request = Note.fetchRequest()
        request.predicate = predicate
        
        #if DEBUG
        print("🗄️ CRUD: Fetching notes with predicate: \(String(describing: predicate))")
        #endif
        
        return try context.fetch(request)
    }
    
    func updateNote(_ note: Note, title: String? = nil, content: String? = nil) throws {
        let context = container.viewContext
        
        #if DEBUG
        print("🗄️ CRUD: Updating note: \(note.title ?? "")")
        #endif
        
        if let title = title {
            note.title = title
        }
        if let content = content {
            note.originalContent = content.data(using: .utf8)
        }
        note.lastModified = Date()
        
        try context.save()
    }
    
    // Delete
    func deleteNote(_ note: Note) throws {
        let context = container.viewContext
        
        #if DEBUG
        print("🗄️ CRUD: Deleting note: \(note.title ?? "")")
        #endif
        
        context.delete(note)
        try context.save()
    }
    
    // Batch operations for performance
    func deleteNotes(matching predicate: NSPredicate) throws -> Int {
        let context = container.viewContext
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Note")
        fetchRequest.predicate = predicate
        
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        deleteRequest.resultType = .resultTypeObjectIDs
        
        #if DEBUG
        print("🗄️ CRUD: Executing batch delete with predicate: \(predicate)")
        #endif
        
        let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
        let objectIDArray = result?.result as? [NSManagedObjectID] ?? []
        
        // Sync changes with context
        let changes = [NSDeletedObjectsKey: objectIDArray]
        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
        
        #if DEBUG
        print("🗄️ CRUD: Successfully deleted \(objectIDArray.count) notes")
        #endif
        
        return objectIDArray.count
    }
    
    // Manages Core Data migrations and versioning
    private func configureMigration() {
        let options = NSPersistentStoreDescription()
        options.shouldMigrateStoreAutomatically = true
        options.shouldInferMappingModelAutomatically = true
        
        #if DEBUG
        print("🗄️ Migration: Configuring automatic migration options")
        #endif
        
        // Update notification name
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMigrationProgress(_:)),
            name: NSNotification.Name.NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator
        )
        
        container.persistentStoreDescriptions = [options]
    }
        
        /// Handles manual migration if needed
        private func performManualMigration() throws {
            guard let sourceModel = NSManagedObjectModel.mergedModel(from: nil) else {
                #if DEBUG
                print("🗄️ Migration: Failed to create source model")
                #endif
                throw MigrationError.sourceModelNotFound
            }
            
            let destinationModel = container.managedObjectModel
            
            guard let mapping = NSMappingModel(from: nil,
                                             forSourceModel: sourceModel,
                                             destinationModel: destinationModel) else {
                #if DEBUG
                print("🗄️ Migration: Failed to create mapping model")
                #endif
                throw MigrationError.mappingModelNotFound
            }
            
            let migrationManager = NSMigrationManager(sourceModel: sourceModel,
                                                    destinationModel: destinationModel)
            migrationManager.addObserver(self,
                                       forKeyPath: #keyPath(NSMigrationManager.migrationProgress),
                                       options: [.new],
                                       context: nil)
            
            #if DEBUG
            print("🗄️ Migration: Starting manual migration")
            #endif
            
            try migrationManager.migrateStore(
                from: storeDescription.url!,
                sourceType: NSSQLiteStoreType,
                options: nil,
                with: mapping,
                toDestinationURL: storeDescription.url!,
                destinationType: NSSQLiteStoreType,
                destinationOptions: nil
            )
            
            #if DEBUG
            print("🗄️ Migration: Manual migration completed successfully")
            #endif
        }
        
    @objc private func handleMigrationProgress(_ notification: Notification) {
        #if DEBUG
        print("""
        🗄️ Migration: Store change notification received
        - Name: \(notification.name)
        - User Info: \(String(describing: notification.userInfo))
        - Store Coordinator: \(String(describing: notification.object))
        - Thread: \(Thread.current.isMainThread ? "Main" : "Background")
        """)
        #endif
        
        DispatchQueue.main.async { [weak self] in
            self?.container.viewContext.refreshAllObjects()
            
            #if DEBUG
            print("🗄️ Migration: Context refreshed after store change")
            #endif
        }
    }
        
    override func observeValue(forKeyPath keyPath: String?,
                             of object: Any?,
                             change: [NSKeyValueChangeKey : Any]?,
                             context: UnsafeMutableRawPointer?) {
        if keyPath == #keyPath(NSMigrationManager.migrationProgress),
           let progress = change?[.newKey] as? Float {
            #if DEBUG
            print("🗄️ Migration: Progress updated: \(progress * 100)%")
            #endif
        }
    }
    
}

// MARK: - Migration Errors
private enum MigrationError: LocalizedError {
    case sourceModelNotFound
    case mappingModelNotFound
    case migrationFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .sourceModelNotFound:
            return "Failed to create source managed object model"
        case .mappingModelNotFound:
            return "Failed to create mapping model"
        case .migrationFailed(let error):
            return "Migration failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Context Extensions
extension NSManagedObjectContext {
    func safeSave() throws {
        if hasChanges {
            print("🗄️ Context: Attempting to save changes")
            try save()
            print("🗄️ Context: Changes saved successfully")
        }
    }
    
    func performAndWait<T>(_ block: () throws -> T) throws -> T {
        var result: Result<T, Error>!
        performAndWait {
            result = Result { try block() }
        }
        return try result.get()
    }
}
