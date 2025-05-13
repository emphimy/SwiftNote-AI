import Foundation
import Supabase
import Combine
import AuthenticationServices

/// Manages authentication state and operations
@MainActor
class AuthenticationManager: ObservableObject {
    // MARK: - Published Properties

    /// Current authentication state
    @Published var authState: AuthState = .initializing

    /// Current user profile
    @Published var userProfile: SupabaseUserProfile?

    /// Error message to display
    @Published var errorMessage: String?

    /// Loading state
    @Published var isLoading = false

    // MARK: - Private Properties
    private let supabaseService = SupabaseService.shared
    private var cancellables = Set<AnyCancellable>()

    /// Last email used for signup or signin
    private var lastEmail: String?

    // MARK: - Initialization
    init() {
        #if DEBUG
        print("🔐 AuthenticationManager: Initializing")
        #endif

        // Check authentication state when app starts
        Task {
            await checkAuthState()
        }

        // Listen for auth code notifications from deep links
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAuthCode(_:)),
            name: Notification.Name("AuthCodeReceived"),
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleAuthCode(_ notification: Notification) {
        guard let code = notification.userInfo?["code"] as? String else {
            #if DEBUG
            print("🔐 AuthenticationManager: Received auth code notification but no code was found")
            #endif
            return
        }

        #if DEBUG
        print("🔐 AuthenticationManager: Received auth code: \(code)")
        #endif

        Task {
            await verifyEmailWithCode(code)
        }
    }

    /// Verify email with confirmation code
    private func verifyEmailWithCode(_ code: String) async {
        #if DEBUG
        print("🔐 AuthenticationManager: Verifying email with code: \(code)")
        #endif

        isLoading = true
        errorMessage = nil

        do {
            // Use the stored email for verification
            guard let email = lastEmail else {
                throw NSError(domain: "AuthenticationManager", code: 400, userInfo: [
                    NSLocalizedDescriptionKey: "No email available for verification"
                ])
            }

            // Verify the email with Supabase
            try await supabaseService.verifyEmail(email: email, token: code)

            // Fetch user profile
            try await fetchUserProfile()

            // Update auth state
            authState = .signedIn

            #if DEBUG
            print("🔐 AuthenticationManager: Email verification successful")
            #endif
        } catch {
            errorMessage = "Failed to verify email: \(error.localizedDescription)"

            #if DEBUG
            print("🔐 AuthenticationManager: Email verification failed - \(error)")
            #endif
        }

        isLoading = false
    }

    // MARK: - Authentication State

    /// Check the current authentication state
    func checkAuthState() async {
        #if DEBUG
        print("🔐 AuthenticationManager: Checking auth state")
        #endif

        authState = .initializing
        isLoading = true

        do {
            let isSignedIn = await supabaseService.isSignedIn()

            if isSignedIn {
                // User is signed in, fetch their profile
                try await fetchUserProfile()
                authState = .signedIn

                #if DEBUG
                print("🔐 AuthenticationManager: User is signed in")
                #endif
            } else {
                // User is not signed in
                authState = .signedOut
                userProfile = nil

                #if DEBUG
                print("🔐 AuthenticationManager: User is signed out")
                #endif
            }
        } catch {
            // Error occurred, assume user is signed out
            authState = .signedOut
            userProfile = nil
            errorMessage = "Failed to check authentication state: \(error.localizedDescription)"

            #if DEBUG
            print("🔐 AuthenticationManager: Error checking auth state - \(error)")
            #endif
        }

        isLoading = false
    }

    // MARK: - User Profile

    /// Fetch the current user's profile
    private func fetchUserProfile() async throws {
        #if DEBUG
        print("🔐 AuthenticationManager: Fetching user profile")
        #endif

        do {
            // Get the current session
            let session = try await supabaseService.getSession()

            // Fetch the user profile from the profiles table
            let profiles: [SupabaseUserProfile] = try await supabaseService.fetch(
                from: "profiles",
                filters: { query in
                    query.eq("id", value: session.user.id.uuidString)
                }
            )

            if let profile = profiles.first {
                userProfile = profile

                #if DEBUG
                print("🔐 AuthenticationManager: User profile fetched successfully")
                #endif
            } else {
                throw NSError(domain: "AuthenticationManager", code: 404, userInfo: [
                    NSLocalizedDescriptionKey: "User profile not found"
                ])
            }
        } catch {
            #if DEBUG
            print("🔐 AuthenticationManager: Error fetching user profile - \(error)")
            #endif

            throw error
        }
    }

    // MARK: - Authentication Methods

    /// Sign in with email and password
    func signInWithEmail(email: String, password: String) async {
        #if DEBUG
        print("🔐 AuthenticationManager: Signing in with email: \(email)")
        #endif

        isLoading = true
        errorMessage = nil

        // Store the email for later use
        lastEmail = email

        do {
            // Sign in with Supabase
            _ = try await supabaseService.signIn(email: email, password: password)

            // Fetch user profile
            try await fetchUserProfile()

            // Update auth state
            authState = .signedIn

            #if DEBUG
            print("🔐 AuthenticationManager: Sign in successful")
            #endif
        } catch {
            errorMessage = "Failed to sign in: \(error.localizedDescription)"
            authState = .signedOut

            #if DEBUG
            print("🔐 AuthenticationManager: Sign in failed - \(error)")
            #endif
        }

        isLoading = false
    }

    /// Sign up with email and password
    func signUpWithEmail(email: String, password: String) async {
        #if DEBUG
        print("🔐 AuthenticationManager: Signing up with email: \(email)")
        #endif

        isLoading = true
        errorMessage = nil

        // Store the email for later use in email verification
        lastEmail = email

        do {
            // Sign up with Supabase
            let response = try await supabaseService.signUp(email: email, password: password)

            // Check if sign up was successful
            if response.session != nil {
                // Fetch user profile
                try await fetchUserProfile()

                // Update auth state
                authState = .signedIn

                #if DEBUG
                print("🔐 AuthenticationManager: Sign up successful")
                #endif
            } else {
                // Email confirmation required
                authState = .confirmationRequired

                #if DEBUG
                print("🔐 AuthenticationManager: Email confirmation required")
                #endif
            }
        } catch {
            errorMessage = "Failed to sign up: \(error.localizedDescription)"
            authState = .signedOut

            #if DEBUG
            print("🔐 AuthenticationManager: Sign up failed - \(error)")
            #endif
        }

        isLoading = false
    }

    /// Sign in with Apple
    func signInWithApple() {
        #if DEBUG
        print("🔐 AuthenticationManager: Starting Apple sign in")
        #endif

        isLoading = true
        errorMessage = nil

        // This will be implemented with ASAuthorizationController
        // For now, we'll just show an error message
        errorMessage = "Apple sign in is not yet implemented"
        isLoading = false
    }

    /// Sign in with Google
    func signInWithGoogle() {
        #if DEBUG
        print("🔐 AuthenticationManager: Starting Google sign in")
        #endif

        isLoading = true
        errorMessage = nil

        // This will be implemented with GoogleSignIn SDK
        // For now, we'll just show an error message
        errorMessage = "Google sign in is not yet implemented"
        isLoading = false
    }

    /// Sign in with Facebook
    func signInWithFacebook() {
        #if DEBUG
        print("🔐 AuthenticationManager: Starting Facebook sign in")
        #endif

        isLoading = true
        errorMessage = nil

        // This will be implemented with Facebook SDK
        // For now, we'll just show an error message
        errorMessage = "Facebook sign in is not yet implemented"
        isLoading = false
    }

    /// Sign out the current user
    func signOut() async {
        #if DEBUG
        print("🔐 AuthenticationManager: Signing out")
        #endif

        isLoading = true
        errorMessage = nil

        do {
            // Sign out with Supabase
            try await supabaseService.signOut()

            // Update auth state
            authState = .signedOut
            userProfile = nil

            #if DEBUG
            print("🔐 AuthenticationManager: Sign out successful")
            #endif
        } catch {
            errorMessage = "Failed to sign out: \(error.localizedDescription)"

            #if DEBUG
            print("🔐 AuthenticationManager: Sign out failed - \(error)")
            #endif
        }

        isLoading = false
    }
}

// MARK: - Authentication State Enum
enum AuthState {
    case initializing
    case signedOut
    case signedIn
    case confirmationRequired
}
