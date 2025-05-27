import CoreData

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
    let container: NSPersistentContainer

    // MARK: - Initialization
    init(inMemory: Bool = false) {
        let storeURL: URL

        if inMemory {
            storeURL = URL(fileURLWithPath: "/dev/null")
            #if DEBUG
            print("🗄️ Persistence: Initializing in-memory store")
            #endif
        } else {
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            storeURL = documentsDirectory.appendingPathComponent("\(Self.modelName).sqlite")
            #if DEBUG
            print("🗄️ Persistence: Setting store URL to \(storeURL.path)")
            #endif
        }

        // Create store description with the URL
        let description = NSPersistentStoreDescription(url: storeURL)
        description.type = NSSQLiteStoreType
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.setOption(FileProtectionType.completeUntilFirstUserAuthentication as NSObject,
                            forKey: NSPersistentStoreFileProtectionKey)
        let pragmaOptions = ["journal_mode": "WAL" as NSObject]
        description.setOption(pragmaOptions as NSDictionary, forKey: NSSQLitePragmasOption)

        // Create container with the description
        container = NSPersistentContainer(name: Self.modelName)
        container.persistentStoreDescriptions = [description]

        // Call super.init
        super.init()

        // Load persistent stores
        container.loadPersistentStores { description, error in
            if let error = error as NSError? {
                #if DEBUG
                print("🗄️ Persistence: Failed to load persistent stores - \(error), \(error.userInfo)")
                #endif

                // Try to recover from common errors
                if error.domain == NSCocoaErrorDomain {
                    switch error.code {
                    case NSPersistentStoreIncompatibleVersionHashError,
                         NSMigrationMissingSourceModelError:
                        self.attemptStoreRecovery(at: description.url)
                    default:
                        fatalError("Unresolved error \(error), \(error.userInfo)")
                    }
                } else {
                    fatalError("Failed to load persistent stores: \(error)")
                }
            } else {
                #if DEBUG
                print("🗄️ Persistence: Successfully loaded persistent store at: \(description.url?.absoluteString ?? "unknown")")
                #endif
            }
        }

        // Setup container
        setupContainer()

        // Register for notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStoreRemoteChange(_:)),
            name: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator
        )
    }

    // Attempt to recover from store errors
    private func attemptStoreRecovery(at url: URL?) {
        guard let storeURL = url else { return }

        #if DEBUG
        print("🗄️ Persistence: Attempting to recover store at \(storeURL.path)")
        #endif

        let fileManager = FileManager.default

        do {
            // If the store exists, try to delete it
            if fileManager.fileExists(atPath: storeURL.path) {
                try fileManager.removeItem(at: storeURL)
                #if DEBUG
                print("🗄️ Persistence: Removed corrupted store")
                #endif
            }

            // Also remove -shm and -wal files if they exist (for SQLite WAL mode)
            let shmURL = storeURL.appendingPathExtension("sqlite-shm")
            if fileManager.fileExists(atPath: shmURL.path) {
                try fileManager.removeItem(at: shmURL)
            }

            let walURL = storeURL.appendingPathExtension("sqlite-wal")
            if fileManager.fileExists(atPath: walURL.path) {
                try fileManager.removeItem(at: walURL)
            }

            // Try to recreate the store
            container.loadPersistentStores { description, error in
                if let error = error {
                    #if DEBUG
                    print("🗄️ Persistence: Recovery failed - \(error)")
                    #endif
                    fatalError("Recovery failed: \(error)")
                } else {
                    #if DEBUG
                    print("🗄️ Persistence: Store recovery successful")
                    #endif
                }
            }
        } catch {
            #if DEBUG
            print("🗄️ Persistence: Error during recovery - \(error)")
            #endif
            fatalError("Recovery failed: \(error)")
        }
    }

    // MARK: - Container Setup
    private func setupContainer() {
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

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
    }

    // MARK: - Background Context
    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }

    // MARK: - Notification Handling
    @objc private func handleStoreRemoteChange(_ notification: Notification) {
        #if DEBUG
        print("🗄️ Persistence: Received store remote change notification")
        #endif

        // Ensure we're on the main thread for UI updates
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Refresh all objects in the view context
            self.container.viewContext.refreshAllObjects()

            // Post a notification for views to refresh their data
            NotificationCenter.default.post(name: .init("RefreshNotes"), object: nil)

            #if DEBUG
            print("🗄️ Persistence: Context refreshed after remote change")
            #endif
        }
    }

    // MARK: - Save Context
    func saveContext() {
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
                #if DEBUG
                print("🗄️ Persistence: Context saved successfully")
                #endif
            } catch {
                let nsError = error as NSError
                #if DEBUG
                print("🗄️ Persistence: Error saving context - \(nsError), \(nsError.userInfo)")
                #endif
            }
        } else {
            #if DEBUG
            print("🗄️ Persistence: No changes to save in context")
            #endif
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

    deinit {
        #if DEBUG
        print("🗄️ Persistence: Controller being deinitialized, saving context")
        #endif
        saveContext()
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
        note.syncStatus = "pending" // Mark new note for sync

        try context.save()

        #if DEBUG
        print("🗄️ CRUD: Successfully created note with title: \(title)")
        #endif

        return note
    }

    // Read
    func fetchNotes(matching predicate: NSPredicate? = nil, includeDeleted: Bool = false) throws -> [Note] {
        let context = container.viewContext
        let request = Note.fetchRequest()

        // Create predicate to exclude deleted notes unless specifically requested
        var finalPredicate: NSPredicate?

        if !includeDeleted {
            let notDeletedPredicate = NSPredicate(format: "deletedAt == nil")

            if let predicate = predicate {
                finalPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, notDeletedPredicate])
            } else {
                finalPredicate = notDeletedPredicate
            }
        } else {
            finalPredicate = predicate
        }

        request.predicate = finalPredicate

        #if DEBUG
        print("🗄️ CRUD: Fetching notes with predicate: \(String(describing: finalPredicate)), includeDeleted: \(includeDeleted)")
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
        note.syncStatus = "pending" // Mark for sync

        try context.save()
    }

    // Delete
    func deleteNote(_ note: Note) throws {
        let context = container.viewContext

        #if DEBUG
        print("🗄️ CRUD: Soft deleting note: \(note.title ?? "")")
        #endif

        // Delete associated files if they exist
        if let sourceURL = note.sourceURL {
            #if DEBUG
            print("🗄️ CRUD: Note has associated file at: \(sourceURL.path)")
            #endif

            do {
                if FileManager.default.fileExists(atPath: sourceURL.path) {
                    try FileManager.default.removeItem(at: sourceURL)

                    #if DEBUG
                    print("🗄️ CRUD: Successfully deleted associated file at: \(sourceURL.path)")
                    #endif
                } else {
                    #if DEBUG
                    print("🗄️ CRUD: Associated file not found at: \(sourceURL.path)")
                    #endif
                }
            } catch {
                #if DEBUG
                print("🗄️ CRUD: Error deleting associated file - \(error)")
                #endif
                // Continue with note deletion even if file deletion fails
            }
        }

        // Perform soft delete by setting deletedAt timestamp
        note.deletedAt = Date()
        note.lastModified = Date()
        note.syncStatus = "pending" // Mark for sync

        #if DEBUG
        print("🗄️ CRUD: Note soft deleted with deletedAt: \(note.deletedAt!)")
        #endif

        try context.save()
    }

    /// Permanently delete a note (hard delete)
    /// This should only be used for cleanup operations
    func permanentlyDeleteNote(_ note: Note) throws {
        let context = container.viewContext

        #if DEBUG
        print("🗄️ CRUD: Permanently deleting note: \(note.title ?? "")")
        #endif

        // Delete associated files if they exist
        if let sourceURL = note.sourceURL {
            do {
                if FileManager.default.fileExists(atPath: sourceURL.path) {
                    try FileManager.default.removeItem(at: sourceURL)
                    #if DEBUG
                    print("🗄️ CRUD: Successfully deleted associated file at: \(sourceURL.path)")
                    #endif
                }
            } catch {
                #if DEBUG
                print("🗄️ CRUD: Error deleting associated file - \(error)")
                #endif
            }
        }

        context.delete(note)
        try context.save()
    }

    // Batch operations for performance
    func deleteNotes(matching predicate: NSPredicate) throws -> Int {
        let context = container.viewContext

        // First, fetch the notes to get their associated files
        let fetchRequest = NSFetchRequest<Note>(entityName: "Note")
        fetchRequest.predicate = predicate

        #if DEBUG
        print("🗄️ CRUD: Fetching notes for batch delete with predicate: \(predicate)")
        #endif

        // Get the notes to delete their associated files
        let notesToDelete = try context.fetch(fetchRequest)

        // Delete associated files
        for note in notesToDelete {
            if let sourceURL = note.sourceURL {
                #if DEBUG
                print("🗄️ CRUD: Note has associated file at: \(sourceURL.path)")
                #endif

                do {
                    if FileManager.default.fileExists(atPath: sourceURL.path) {
                        try FileManager.default.removeItem(at: sourceURL)

                        #if DEBUG
                        print("🗄️ CRUD: Successfully deleted associated file at: \(sourceURL.path)")
                        #endif
                    }
                } catch {
                    #if DEBUG
                    print("🗄️ CRUD: Error deleting associated file - \(error)")
                    #endif
                    // Continue with note deletion even if file deletion fails
                }
            }
        }

        // Now perform the batch delete
        let batchFetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Note")
        batchFetchRequest.predicate = predicate

        let deleteRequest = NSBatchDeleteRequest(fetchRequest: batchFetchRequest)
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
        print("🗄️ CRUD: Successfully deleted \(objectIDArray.count) notes and their associated files")
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

            guard let storeURL = container.persistentStoreDescriptions.first?.url else {
                throw MigrationError.migrationFailed(NSError(domain: "PersistenceController",
                                                           code: -1,
                                                           userInfo: [NSLocalizedDescriptionKey: "Store URL not found"]))
            }

            try migrationManager.migrateStore(
                from: storeURL,
                sourceType: NSSQLiteStoreType,
                options: nil,
                with: mapping,
                toDestinationURL: storeURL,
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
