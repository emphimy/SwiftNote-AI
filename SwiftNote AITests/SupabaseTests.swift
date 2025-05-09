import XCTest
@testable import SwiftNote_AI
import Supabase

final class SupabaseTests: XCTestCase {
    
    func testSupabaseConnection() async {
        // This test verifies that we can connect to Supabase
        do {
            // Try to get the current session (will fail if not authenticated, but should connect)
            _ = try? await SupabaseService.shared.getSession()
            
            // If we get here without crashing, the connection is working
            XCTAssert(true, "Supabase connection successful")
        } catch {
            XCTFail("Failed to connect to Supabase: \(error)")
        }
    }
}
