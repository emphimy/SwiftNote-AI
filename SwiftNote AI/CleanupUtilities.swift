// MARK: - Cleanup Utilities
import Foundation

actor AudioCleanupManager {
    static let shared = AudioCleanupManager()
    
    private init() {
        #if DEBUG
        print("🧹 AudioCleanupManager: Initializing singleton instance")
        #endif
    }
    
    func cleanup(url: URL?) {
        #if DEBUG
        print("🧹 AudioCleanupManager: Cleaning up temporary file at \(String(describing: url))")
        #endif
        
        if let url = url {
            do {
                try FileManager.default.removeItem(at: url)
                #if DEBUG
                print("🧹 AudioCleanupManager: Successfully removed file at \(url)")
                #endif
            } catch {
                #if DEBUG
                print("🧹 AudioCleanupManager: Failed to remove file - \(error)")
                #endif
            }
        }
    }
}
