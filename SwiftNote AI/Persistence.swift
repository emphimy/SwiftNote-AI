import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        for _ in 0..<10 {
            let newItem = Item(context: viewContext)
            newItem.timestamp = Date()
        }
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            #if DEBUG
            print("🗄️ Persistence: Failed to save preview context - \(nsError), \(nsError.userInfo)")
            #endif
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "SwiftNote_AI")
        
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        
        #if DEBUG
        print("🗄️ Persistence: Initializing persistent container")
        #endif
        
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                #if DEBUG
                print("🗄️ Persistence: Failed to load persistent stores - \(error), \(error.userInfo)")
                #endif
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
            #if DEBUG
            print("🗄️ Persistence: Successfully loaded persistent stores")
            #endif
        })
        
        setupDefaultValues()
        container.viewContext.automaticallyMergesChangesFromParent = true
        
        #if DEBUG
        print("🗄️ Persistence: Container setup completed")
        #endif
    }
    
    // MARK: - Property Setup Methods
    private func setupDefaultValues() {
        let context = container.viewContext
        
        // Check if default values are already set
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "QuizAnalytics")
        fetchRequest.predicate = NSPredicate(format: "id != nil")
        fetchRequest.fetchLimit = 1
        
        do {
            let count = try context.count(for: fetchRequest)
            guard count == 0 else {
                #if DEBUG
                print("🗄️ Persistence: Default values already set")
                #endif
                return
            }
            
            // Create default QuizAnalytics entity
            let analytics = NSEntityDescription.insertNewObject(forEntityName: "QuizAnalytics", into: context) // Fixed parameter label
            analytics.setValue(UUID(), forKey: "id")
            analytics.setValue(UUID(), forKey: "noteId")
            analytics.setValue(0, forKey: "completedQuizzes")
            analytics.setValue(0, forKey: "correctAnswers")
            analytics.setValue(0, forKey: "totalQuestions")
            analytics.setValue(0.0, forKey: "averageScore")
            
            // Create default QuizProgress entity
            let progress = NSEntityDescription.insertNewObject(forEntityName: "QuizProgress", into: context) // Fixed parameter label
            progress.setValue(UUID(), forKey: "id")
            progress.setValue(UUID(), forKey: "noteId")
            progress.setValue(Data(), forKey: "answers")
            progress.setValue(Date(), forKey: "timestamp")
            
            try context.save()
            
            #if DEBUG
            print("🗄️ Persistence: Successfully created default entities")
            #endif
        } catch {
            #if DEBUG
            print("🗄️ Persistence: Failed to setup default values - \(error)")
            #endif
        }
    }
}
