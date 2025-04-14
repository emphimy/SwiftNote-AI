import SwiftUI
import CoreData

@main
struct SwiftNote_AIApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var themeManager = ThemeManager()
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        // Restore notes from UserDefaults when app launches
        SimpleNotePersistence.shared.restoreNotes(
            context: persistenceController.container.viewContext
        )
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.currentTheme.colorScheme)
                .onChange(of: themeManager.currentTheme) { newTheme in
                    #if DEBUG
                    print("🎨 App: Theme changed to \(newTheme) with colorScheme: \(String(describing: newTheme.colorScheme))")
                    #endif
                }
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .background:
                #if DEBUG
                print("📱 App: Moving to background, saving context")
                #endif
                persistenceController.saveContext()
                
                // Also save all notes to UserDefaults
                saveAllNotesToUserDefaults()
                
                // Add a delay to ensure the save completes before app suspension
                let semaphore = DispatchSemaphore(value: 0)
                DispatchQueue.global().async {
                    // Give the save operation time to complete
                    Thread.sleep(forTimeInterval: 0.5)
                    semaphore.signal()
                }
                _ = semaphore.wait(timeout: .now() + 1.0)
                
            case .inactive:
                #if DEBUG
                print("📱 App: Becoming inactive, saving context")
                #endif
                persistenceController.saveContext()
                
                // Also save all notes to UserDefaults
                saveAllNotesToUserDefaults()
                
            case .active:
                #if DEBUG
                print("📱 App: Becoming active")
                #endif
                
                // Post notification to refresh notes when app becomes active
                NotificationCenter.default.post(name: .init("RefreshNotes"), object: nil)
                
            @unknown default:
                #if DEBUG
                print("📱 App: Unknown scene phase: \(newPhase)")
                #endif
            }
        }
    }
    
    // Helper function to save all notes to UserDefaults
    private func saveAllNotesToUserDefaults() {
        let context = persistenceController.container.viewContext
        let fetchRequest = NSFetchRequest<Note>(entityName: "Note")
        
        do {
            let notes = try context.fetch(fetchRequest)
            #if DEBUG
            print("📱 App: Saving \(notes.count) notes to UserDefaults")
            #endif
            
            for note in notes {
                SimpleNotePersistence.shared.saveNote(note)
            }
        } catch {
            #if DEBUG
            print("📱 App: Error fetching notes for UserDefaults backup - \(error)")
            #endif
        }
    }
}
