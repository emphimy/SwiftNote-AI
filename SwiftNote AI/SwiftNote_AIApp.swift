import SwiftUI

@main
struct SwiftNote_AIApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var themeManager = ThemeManager()
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        // Restore notes from backup if needed when app launches
        NotePersistenceManager.shared.restoreNotesIfNeeded(
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
}
