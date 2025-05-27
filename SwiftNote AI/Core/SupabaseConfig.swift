import Foundation
import Supabase

/// Manages Supabase configuration and provides a shared client instance
class SupabaseConfig {
    // MARK: - Singleton
    static let shared = SupabaseConfig()

    // MARK: - Properties
    private(set) var client: SupabaseClient

    /// Google client ID for Google Sign In
    var googleClientID: String {
        return Secrets.googleClientID
    }

    // MARK: - Initialization
    private init() {
        #if DEBUG
        print("🔌 SupabaseConfig: Initializing Supabase client")
        #endif

        client = SupabaseClient(
            supabaseURL: Secrets.supabaseURL,
            supabaseKey: Secrets.supabaseAnonKey
        )
    }
}
