import SwiftUI

@main
struct SwiftNote_AIApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var themeManager = ThemeManager()
    
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
    }
}


