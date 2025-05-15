import Foundation
import Supabase
import Combine
import PostgREST
import AuthenticationServices
import CryptoKit

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
    /// - Parameter scope: The scope of the sign out (.global or .local)
    func signOut(scope: SignOutScope) async {
        #if DEBUG
        print("🔌 SupabaseService: Signing out user with scope: \(scope)")
        #endif

        do {
            // Try to sign out with the specified scope
            try await client.auth.signOut(scope: scope)

            #if DEBUG
            print("🔌 SupabaseService: Sign out successful with scope: \(scope)")
            #endif
        } catch let error as AuthError {
            // Handle specific auth errors
            if case .sessionMissing = error {
                #if DEBUG
                print("🔌 SupabaseService: Session already missing, considering sign out successful")
                #endif
                // This is not a critical error - the user is effectively signed out
                return
            } else {
                #if DEBUG
                print("🔌 SupabaseService: Sign out failed with auth error - \(error)")
                #endif
                // For other auth errors, we'll still consider the user signed out locally
                return
            }
        } catch {
            // Handle network or other errors
            #if DEBUG
            print("🔌 SupabaseService: Sign out failed with error - \(error)")
            print("🔌 SupabaseService: Will try to clear local session data anyway")
            #endif

            // If this was a global sign-out and it failed, try a local sign-out as fallback
            if scope == .global {
                #if DEBUG
                print("🔌 SupabaseService: Attempting local sign-out as fallback")
                #endif

                do {
                    try await client.auth.signOut(scope: .local)
                    #if DEBUG
                    print("🔌 SupabaseService: Local sign-out successful")
                    #endif
                } catch {
                    #if DEBUG
                    print("🔌 SupabaseService: Local sign-out also failed - \(error)")
                    #endif
                }
            }
        }
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

        // Check if the new email is the same as the current email
        if newEmail.lowercased() == currentEmail.lowercased() {
            #if DEBUG
            print("🔌 SupabaseService: New email is the same as current email")
            #endif
            throw NSError(domain: "SupabaseService", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "New email is the same as your current email"
            ])
        }

        // Check if the new email already exists
        // Note: Supabase will handle this check server-side, but we can add additional checks here if needed

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

    /// Fetch minimal note data (without binary content) from a table
    /// - Parameters:
    ///   - userId: User ID to filter by
    /// - Returns: Array of notes with minimal data
    func fetchMinimalNotes(userId: UUID) async throws -> [SupabaseNote] {
        #if DEBUG
        print("🔌 SupabaseService: Fetching minimal notes for user: \(userId)")
        #endif

        // Fetch notes without binary content fields
        let query = client.from("notes")
            .select("id, title, source_type, timestamp, last_modified, is_favorite, processing_status, folder_id, user_id, summary, key_points, citations, duration, language_code, source_url, tags, transcript, video_id")
            .eq("user_id", value: userId.uuidString)

        let response = try await query.execute()
        let data = response.data

        // Check if data is empty
        if data.isEmpty {
            return [] // Return empty array instead of throwing an error
        }

        // Parse the JSON data manually to avoid decoding issues with binary content
        let decoder = JSONDecoder()

        // Create a custom date formatter that can handle Supabase's date format
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)

        // Set up a custom date decoding strategy
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try different date formats
            let formats = [
                "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ",
                "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
                "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
                "yyyy-MM-dd'T'HH:mm:ss'Z'"
            ]

            for format in formats {
                dateFormatter.dateFormat = format
                if let date = dateFormatter.date(from: dateString) {
                    return date
                }
            }

            #if DEBUG
            print("🔌 SupabaseService: Failed to parse date: \(dateString)")
            #endif

            // If all formats fail, return current date as fallback
            return Date()
        }

        do {
            let notes = try decoder.decode([MinimalSupabaseNote].self, from: data)

            // Convert to full SupabaseNote objects with nil binary content
            return notes.map { minimalNote in
                return SupabaseNote(
                    id: minimalNote.id,
                    title: minimalNote.title,
                    originalContent: nil,
                    aiGeneratedContent: nil,
                    sourceType: minimalNote.sourceType,
                    timestamp: minimalNote.timestamp,
                    lastModified: minimalNote.lastModified,
                    isFavorite: minimalNote.isFavorite,
                    processingStatus: minimalNote.processingStatus,
                    folderId: minimalNote.folderId,
                    userId: minimalNote.userId,
                    summary: minimalNote.summary,
                    keyPoints: minimalNote.keyPoints,
                    citations: minimalNote.citations,
                    duration: minimalNote.duration,
                    languageCode: minimalNote.languageCode,
                    sourceURL: minimalNote.sourceURL,
                    tags: minimalNote.tags,
                    transcript: minimalNote.transcript,
                    sections: nil,
                    supplementaryMaterials: nil,
                    mindMap: nil,
                    videoId: minimalNote.videoId
                )
            }
        } catch {
            #if DEBUG
            print("🔌 SupabaseService: Error decoding minimal notes: \(error)")
            #endif
            throw error
        }
    }

    /// Minimal version of SupabaseNote without binary content
    private struct MinimalSupabaseNote: Codable {
        let id: UUID
        var title: String
        var sourceType: String
        var timestamp: Date
        var lastModified: Date
        var isFavorite: Bool
        var processingStatus: String
        var folderId: UUID?
        var userId: UUID
        var summary: String?
        var keyPoints: String?
        var citations: String?
        var duration: Double?
        var languageCode: String?
        var sourceURL: String?
        var tags: String?
        var transcript: String?
        var videoId: String?

        enum CodingKeys: String, CodingKey {
            case id
            case title
            case sourceType = "source_type"
            case timestamp
            case lastModified = "last_modified"
            case isFavorite = "is_favorite"
            case processingStatus = "processing_status"
            case folderId = "folder_id"
            case userId = "user_id"
            case summary
            case keyPoints = "key_points"
            case citations
            case duration
            case languageCode = "language_code"
            case sourceURL = "source_url"
            case tags
            case transcript
            case videoId = "video_id"
        }
    }

    /// Fetch a complete note with all content including binary data
    /// - Parameters:
    ///   - noteId: The ID of the note to fetch
    ///   - userId: The user ID for security validation
    /// - Returns: A complete SupabaseNote with all data
    func fetchCompleteNote(noteId: UUID, userId: UUID) async throws -> SupabaseNote {
        #if DEBUG
        print("🔌 SupabaseService: Fetching complete note with ID: \(noteId)")
        #endif

        // Fetch the note with all fields
        let query = client.from("notes")
            .select("*")
            .eq("id", value: noteId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .single()

        let response = try await query.execute()
        let data = response.data

        // Parse the JSON data
        let decoder = JSONDecoder()

        // Set up date decoding strategy
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)

        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try different date formats
            let formats = [
                "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ",
                "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
                "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
                "yyyy-MM-dd'T'HH:mm:ss'Z'"
            ]

            for format in formats {
                dateFormatter.dateFormat = format
                if let date = dateFormatter.date(from: dateString) {
                    return date
                }
            }

            return Date()
        }

        do {
            return try decoder.decode(SupabaseNote.self, from: data)
        } catch {
            #if DEBUG
            print("🔌 SupabaseService: Error decoding complete note: \(error)")
            #endif
            throw error
        }
    }

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

    // MARK: - Social Login Methods

    /// Sign in with Apple
    /// - Parameters:
    ///   - idToken: ID token from Apple
    ///   - nonce: Nonce used for the request (original, unhashed)
    /// - Returns: Session for the authenticated user
    func signInWithApple(idToken: String, nonce: String) async throws -> Session {
        #if DEBUG
        print("🔌 SupabaseService: Signing in with Apple")
        print("🔌 SupabaseService: Using raw nonce: \(nonce)")
        // Print only the first 10 characters of the token for security
        let tokenPreview = String(idToken.prefix(10)) + "..."
        print("🔌 SupabaseService: ID token preview: \(tokenPreview)")
        #endif

        do {
            let session = try await client.auth.signInWithIdToken(
                credentials: .init(
                    provider: .apple,
                    idToken: idToken,
                    nonce: nonce // Supabase expects the original unhashed nonce
                )
            )

            #if DEBUG
            print("🔌 SupabaseService: Apple sign in successful")
            #endif

            return session
        } catch {
            #if DEBUG
            print("🔌 SupabaseService: Apple sign in failed - \(error)")
            if let authError = error as? AuthError {
                print("🔌 SupabaseService: Auth error details - \(authError)")
            }
            #endif
            throw error
        }
    }

    /// Sign in with Google
    /// - Parameters:
    ///   - idToken: ID token from Google
    /// - Returns: Session for the authenticated user
    func signInWithGoogle(idToken: String) async throws -> Session {
        #if DEBUG
        print("🔌 SupabaseService: Signing in with Google")
        #endif

        return try await client.auth.signInWithIdToken(
            credentials: .init(
                provider: .google,
                idToken: idToken
            )
        )
    }

    /// Generate a random nonce for authentication
    /// - Parameter length: Length of the nonce
    /// - Returns: A random nonce string
    func generateRandomNonce(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
                }
                return random
            }

            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }

                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    /// Compute the SHA256 hash of a string
    /// - Parameter input: Input string
    /// - Returns: SHA256 hash as a hex string
    func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()

        return hashString
    }
}
