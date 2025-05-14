import Foundation
import Supabase
import Combine
import PostgREST

/// Service class for interacting with Supabase
class SupabaseService {
    // MARK: - Singleton
    static let shared = SupabaseService()

    // MARK: - Properties
    private let client: SupabaseClient

    // MARK: - Initialization
    private init() {
        client = SupabaseConfig.shared.client

        #if DEBUG
        print("🔌 SupabaseService: Initializing")
        #endif
    }

    /// Initialize the Supabase client
    /// Call this method when your app starts
    func initialize() async {
        #if DEBUG
        print("🔌 SupabaseService: Initializing Supabase client")
        #endif

        // Check if user is signed in by trying to get the session
        // This will handle the refresh token not found error gracefully
        let isUserSignedIn = await isSignedIn()

        #if DEBUG
        if isUserSignedIn {
            print("🔌 SupabaseService: User is signed in")
        } else {
            // This is normal for a fresh install or when no user is logged in
            print("🔌 SupabaseService: No user is signed in")
        }
        #endif
    }

    // MARK: - Authentication Methods

    /// Sign up a new user with email and password
    /// - Parameters:
    ///   - email: User's email
    ///   - password: User's password
    /// - Returns: AuthResponse containing the user and session
    func signUp(email: String, password: String) async throws -> AuthResponse {
        #if DEBUG
        print("🔌 SupabaseService: Signing up user with email: \(email)")
        #endif

        // In newer versions, the parameter labels might be different
        return try await client.auth.signUp(email: email, password: password)
    }

    /// Sign in a user with email and password
    /// - Parameters:
    ///   - email: User's email
    ///   - password: User's password
    /// - Returns: Session for the authenticated user
    func signIn(email: String, password: String) async throws -> Session {
        #if DEBUG
        print("🔌 SupabaseService: Signing in user with email: \(email)")
        #endif

        // In newer versions, signIn returns a Session directly, not an AuthResponse
        return try await client.auth.signIn(email: email, password: password)
    }

    /// Sign out the current user
    func signOut() async throws {
        #if DEBUG
        print("🔌 SupabaseService: Signing out user")
        #endif

        try await client.auth.signOut()
    }

    /// Get the current session
    /// - Returns: Current session if available
    func getSession() async throws -> Session {
        #if DEBUG
        print("🔌 SupabaseService: Getting current session")
        #endif

        do {
            // In newer versions of the SDK, session is an async property that throws
            return try await client.auth.session
        } catch let error as AuthError {
            // Check if this is a refresh token not found error, which is expected when no user is logged in
            if case .api(_, let errorCode, _, _) = error,
               errorCode.rawValue == "refresh_token_not_found" {
                #if DEBUG
                print("🔌 SupabaseService: No active session found (refresh token not found)")
                #endif
            } else {
                #if DEBUG
                print("🔌 SupabaseService: Error getting session - \(error)")
                #endif
            }
            throw error
        } catch {
            #if DEBUG
            print("🔌 SupabaseService: Error getting session - \(error)")
            #endif
            throw error
        }
    }

    /// Check if a user is currently signed in
    /// - Returns: Boolean indicating if a user is signed in
    func isSignedIn() async -> Bool {
        do {
            _ = try await getSession()
            return true
        } catch let error as AuthError {
            // Check if this is a refresh token not found error, which is expected when no user is logged in
            if case .api(_, let errorCode, _, _) = error,
               errorCode.rawValue == "refresh_token_not_found" {
                #if DEBUG
                print("🔌 SupabaseService: No user is signed in (refresh token not found)")
                #endif
            } else {
                #if DEBUG
                print("🔌 SupabaseService: Error checking if user is signed in - \(error)")
                #endif
            }
            return false
        } catch {
            #if DEBUG
            print("🔌 SupabaseService: Error checking if user is signed in - \(error)")
            #endif
            return false
        }
    }

    /// Verify email with confirmation token
    /// - Parameters:
    ///   - email: User's email
    ///   - token: The confirmation token from the email link
    func verifyEmail(email: String, token: String) async throws {
        #if DEBUG
        print("🔌 SupabaseService: Verifying email: \(email) with token: \(token)")
        #endif

        try await client.auth.verifyOTP(
            email: email,
            token: token,
            type: .signup
        )
    }

    /// Resend confirmation email
    /// - Parameter email: User's email
    func resendConfirmationEmail(email: String) async throws {
        #if DEBUG
        print("🔌 SupabaseService: Resending confirmation email to: \(email)")
        #endif

        // Use the OTP method to resend the confirmation email
        try await client.auth.resend(
            email: email,
            type: .signup
        )

        #if DEBUG
        print("🔌 SupabaseService: Confirmation email resent successfully")
        #endif
    }

    /// Send password reset email
    /// - Parameter email: User's email
    func resetPassword(email: String) async throws {
        #if DEBUG
        print("🔌 SupabaseService: Sending password reset email to: \(email)")
        #endif

        // Use the resetPasswordForEmail method to send a password reset email
        try await client.auth.resetPasswordForEmail(email)

        #if DEBUG
        print("🔌 SupabaseService: Password reset email sent successfully")
        #endif
    }

    /// Change user's password
    /// - Parameters:
    ///   - currentPassword: Current password for verification
    ///   - newPassword: New password to set
    func changePassword(currentPassword: String, newPassword: String) async throws {
        #if DEBUG
        print("🔌 SupabaseService: Changing user password")
        #endif

        // First verify the current password by attempting to sign in
        let session = try await client.auth.session
        let email = session.user.email ?? ""

        // Verify current password by attempting to sign in
        do {
            _ = try await client.auth.signIn(email: email, password: currentPassword)
        } catch {
            #if DEBUG
            print("🔌 SupabaseService: Current password verification failed")
            #endif
            throw NSError(domain: "SupabaseService", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "Current password is incorrect"
            ])
        }

        // Update the password
        try await client.auth.update(user: UserAttributes(password: newPassword))

        #if DEBUG
        print("🔌 SupabaseService: Password changed successfully")
        #endif
    }

    /// Change user's email
    /// - Parameters:
    ///   - newEmail: New email address
    ///   - password: Current password for verification
    func changeEmail(newEmail: String, password: String) async throws {
        #if DEBUG
        print("🔌 SupabaseService: Changing user email to: \(newEmail)")
        #endif

        // First verify the password by attempting to sign in
        let session = try await client.auth.session
        let currentEmail = session.user.email ?? ""

        // Verify password by attempting to sign in
        do {
            _ = try await client.auth.signIn(email: currentEmail, password: password)
        } catch {
            #if DEBUG
            print("🔌 SupabaseService: Password verification failed")
            #endif
            throw NSError(domain: "SupabaseService", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "Password is incorrect"
            ])
        }

        // Update the email
        try await client.auth.update(user: UserAttributes(email: newEmail))

        #if DEBUG
        print("🔌 SupabaseService: Email change initiated, confirmation email sent")
        #endif
    }

    // MARK: - Database Methods

    /// Generic method to fetch data from a table
    /// - Parameters:
    ///   - table: Table name
    ///   - columns: Columns to select (default: "*")
    ///   - filters: Optional query filters
    /// - Returns: Array of decoded items
    func fetch<T: Decodable>(
        from table: String,
        columns: String = "*",
        filters: ((PostgrestFilterBuilder) -> PostgrestFilterBuilder)? = nil
    ) async throws -> [T] {
        #if DEBUG
        print("🔌 SupabaseService: Fetching data from table: \(table)")
        #endif

        var query = client.from(table)
            .select(columns)

        if let filters = filters {
            query = filters(query)
        }

        return try await query.execute().value
    }

    /// Generic method to insert data into a table
    /// - Parameters:
    ///   - table: Table name
    ///   - values: Values to insert
    /// - Returns: Array of inserted items
    func insert<T: Encodable, R: Decodable>(
        into table: String,
        values: T
    ) async throws -> [R] {
        #if DEBUG
        print("🔌 SupabaseService: Inserting data into table: \(table)")
        #endif

        let query = try client.from(table)
            .insert(values)
        return try await query.execute().value
    }

    /// Generic method to update data in a table
    /// - Parameters:
    ///   - table: Table name
    ///   - values: Values to update
    ///   - filters: Query filters to identify records to update
    /// - Returns: Array of updated items
    func update<T: Encodable, R: Decodable>(
        table: String,
        values: T,
        filters: (PostgrestFilterBuilder) -> PostgrestFilterBuilder
    ) async throws -> [R] {
        #if DEBUG
        print("🔌 SupabaseService: Updating data in table: \(table)")
        #endif

        let query = try client.from(table)
            .update(values)

        // Apply filters and execute the query
        let filteredQuery = filters(query)
        return try await filteredQuery.execute().value
    }

    /// Generic method to delete data from a table
    /// - Parameters:
    ///   - table: Table name
    ///   - filters: Query filters to identify records to delete
    /// - Returns: Array of deleted items
    func delete<R: Decodable>(
        from table: String,
        filters: (PostgrestFilterBuilder) -> PostgrestFilterBuilder
    ) async throws -> [R] {
        #if DEBUG
        print("🔌 SupabaseService: Deleting data from table: \(table)")
        #endif

        let query = client.from(table)
            .delete()

        // Apply filters and execute the query
        let filteredQuery = filters(query)
        return try await filteredQuery.execute().value
    }
}
