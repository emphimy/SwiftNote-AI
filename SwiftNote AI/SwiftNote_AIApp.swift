import SwiftUI
import CoreData

@main
struct SwiftNote_AIApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var themeManager = ThemeManager()
    @Environment(\.scenePhase) private var scenePhase
    @State private var supabaseInitialized = false

    init() {
        // Initialize app without UserDefaults restoration
    }

    // Initialize Supabase when the app starts
    private func initializeSupabase() async {
        if !supabaseInitialized {
            await SupabaseService.shared.initialize()
            supabaseInitialized = true

            #if DEBUG
            print("📱 App: Supabase initialized")
            #endif
        }
    }

    var body: some Scene {
        WindowGroup {
            AppLockWrapper {
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
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .background:
                #if DEBUG
                print("📱 App: Moving to background, saving context")
                #endif
                persistenceController.saveContext()

            case .inactive:
                #if DEBUG
                print("📱 App: Becoming inactive, saving context")
                #endif
                persistenceController.saveContext()

            case .active:
                #if DEBUG
                print("📱 App: Becoming active")
                #endif

                // Initialize Supabase
                Task {
                    await initializeSupabase()
                }

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
