import Foundation
import Supabase
import Combine
import AuthenticationServices
import PostgREST

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

    /// Timer for auto-dismissing error messages
    private var errorMessageTimer: Timer?

    /// Duration for error messages to be displayed (in seconds)
    private let errorMessageDuration: TimeInterval = 5.0

    /// Last email used for signup or signin
    private var lastEmail: String?

    /// Last password used for signup (stored temporarily for auto sign-in after confirmation)
    private var lastPassword: String?

    /// Key for storing confirmation data in UserDefaults
    private let confirmationDataKey = "com.kyb.SwiftNote-AI.confirmationData"

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

        // Listen for email confirmation success notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEmailConfirmationSuccess),
            name: Notification.Name("EmailConfirmationSuccess"),
            object: nil
        )

        // Listen for password reset redirect notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePasswordResetRedirect(_:)),
            name: Notification.Name("PasswordResetRedirect"),
            object: nil
        )

        // Listen for email change success notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEmailChangeSuccess),
            name: Notification.Name("EmailChangeSuccess"),
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        errorMessageTimer?.invalidate()
    }

    // MARK: - Error Message Handling

    /// Set an error message with auto-dismissal
    func setErrorMessage(_ message: String?) {
        // Cancel any existing timer
        errorMessageTimer?.invalidate()

        // Set the new error message
        errorMessage = message

        // If there's a message, start a timer to clear it
        if message != nil {
            errorMessageTimer = Timer.scheduledTimer(withTimeInterval: errorMessageDuration, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.errorMessage = nil
                }
            }
        }
    }

    /// Dismiss the current error message
    func dismissErrorMessage() {
        errorMessageTimer?.invalidate()
        errorMessage = nil
    }

    // MARK: - Confirmation Data Management

    /// Save confirmation data for later use
    private func saveConfirmationData(email: String, password: String) {
        // Store in memory
        lastEmail = email
        lastPassword = password

        // Also store in UserDefaults in case app is terminated during confirmation
        let data = ["email": email, "password": password]
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: confirmationDataKey)

            #if DEBUG
            print("🔐 AuthenticationManager: Saved confirmation data for email: \(email)")
            #endif
        }
    }

    /// Retrieve confirmation data
    private func retrieveConfirmationData() -> (email: String?, password: String?)? {
        // First try memory
        if let email = lastEmail, let password = lastPassword {
            return (email, password)
        }

        // Fall back to UserDefaults
        if let data = UserDefaults.standard.data(forKey: confirmationDataKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data),
           let email = decoded["email"],
           let password = decoded["password"] {

            // Restore memory values
            lastEmail = email
            lastPassword = password

            #if DEBUG
            print("🔐 AuthenticationManager: Retrieved confirmation data for email: \(email)")
            #endif

            return (email, password)
        }

        return nil
    }

    /// Clear confirmation data
    private func clearConfirmationData() {
        lastPassword = nil
        UserDefaults.standard.removeObject(forKey: confirmationDataKey)

        #if DEBUG
        print("🔐 AuthenticationManager: Cleared confirmation data")
        #endif
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

        // We don't need to verify the email again since Supabase has already done it
        // Just note that we received a code, but don't try to verify it
        #if DEBUG
        print("🔐 AuthenticationManager: Received auth code, but not verifying it since Supabase already did")
        #endif

        // We'll rely on the EmailConfirmationSuccess notification to trigger auto sign-in
    }

    @objc private func handleEmailConfirmationSuccess() {
        #if DEBUG
        print("🔐 AuthenticationManager: Received email confirmation success notification")
        #endif

        Task {
            await attemptAutoSignIn()
        }
    }

    @objc private func handlePasswordResetRedirect(_ notification: Notification) {
        #if DEBUG
        print("🔐 AuthenticationManager: Received password reset redirect notification")
        #endif

        // For now, just show a message to the user
        // In a future implementation, you could show a password reset form
        setErrorMessage("Password reset link detected. Please use the sign-in screen to reset your password.")
        authState = .signedOut
    }

    @objc private func handleEmailChangeSuccess() {
        #if DEBUG
        print("🔐 AuthenticationManager: Received email change success notification")
        #endif

        // For now, just show a message to the user
        setErrorMessage("Email change confirmed successfully. Please sign in with your new email.")
        authState = .signedOut
    }

    /// Resend confirmation email to the user
    func resendConfirmationEmail() async {
        #if DEBUG
        print("🔐 AuthenticationManager: Attempting to resend confirmation email")
        #endif

        isLoading = true
        setErrorMessage(nil)

        // Retrieve the email from saved confirmation data
        guard let confirmationData = retrieveConfirmationData(),
              let email = confirmationData.email else {
            #if DEBUG
            print("🔐 AuthenticationManager: No email found for resending confirmation")
            #endif

            setErrorMessage("No email address found. Please try signing up again.")
            isLoading = false
            return
        }

        do {
            // Resend the confirmation email
            try await supabaseService.resendConfirmationEmail(email: email)

            // Show success message
            setErrorMessage("Confirmation email has been resent to \(email)")

            #if DEBUG
            print("🔐 AuthenticationManager: Confirmation email resent successfully")
            #endif
        } catch {
            setErrorMessage("Failed to resend confirmation email: \(error.localizedDescription)")

            #if DEBUG
            print("🔐 AuthenticationManager: Failed to resend confirmation email - \(error)")
            #endif
        }

        isLoading = false
    }

    /// Send password reset email to the user
    func resetPassword(email: String) async {
        #if DEBUG
        print("🔐 AuthenticationManager: Attempting to send password reset email")
        #endif

        isLoading = true
        setErrorMessage(nil)

        // Validate email
        guard !email.isEmpty else {
            setErrorMessage("Please enter your email address")
            isLoading = false
            return
        }

        do {
            // Send the password reset email
            try await supabaseService.resetPassword(email: email)

            // Show success message
            setErrorMessage("Password reset instructions have been sent to \(email)")

            #if DEBUG
            print("🔐 AuthenticationManager: Password reset email sent successfully")
            #endif
        } catch {
            setErrorMessage("Failed to send password reset email: \(error.localizedDescription)")

            #if DEBUG
            print("🔐 AuthenticationManager: Failed to send password reset email - \(error)")
            #endif
        }

        isLoading = false
    }

    /// Attempt to automatically sign in the user after email confirmation
    private func attemptAutoSignIn() async {
        #if DEBUG
        print("🔐 AuthenticationManager: Attempting auto sign-in after email confirmation")
        #endif

        isLoading = true
        setErrorMessage(nil)

        // Retrieve saved confirmation data
        guard let confirmationData = retrieveConfirmationData(),
              let email = confirmationData.email,
              let password = confirmationData.password else {
            #if DEBUG
            print("🔐 AuthenticationManager: No saved credentials found for auto sign-in")
            #endif

            setErrorMessage("Email confirmed, but no saved credentials found. Please sign in manually.")
            authState = .signedOut
            isLoading = false
            return
        }

        do {
            // Sign in with Supabase
            _ = try await supabaseService.signIn(email: email, password: password)

            // Fetch user profile
            try await fetchUserProfile()

            // Update auth state
            authState = .signedIn

            // Clear saved credentials after successful sign-in
            clearConfirmationData()

            #if DEBUG
            print("🔐 AuthenticationManager: Auto sign-in successful after email confirmation")
            #endif
        } catch {
            // If auto sign-in fails, we'll show a message to the user to sign in manually
            authState = .signedOut
            setErrorMessage("Email confirmed successfully. Please sign in with your credentials.")

            #if DEBUG
            print("🔐 AuthenticationManager: Auto sign-in failed after email confirmation - \(error)")
            #endif
        }

        isLoading = false
    }

    /// Verify email with confirmation code
    private func verifyEmailWithCode(_ code: String) async {
        #if DEBUG
        print("🔐 AuthenticationManager: Verifying email with code: \(code)")
        #endif

        isLoading = true
        setErrorMessage(nil)

        do {
            // Retrieve saved confirmation data
            guard let confirmationData = retrieveConfirmationData(),
                  let email = confirmationData.email,
                  let password = confirmationData.password else {
                throw NSError(domain: "AuthenticationManager", code: 400, userInfo: [
                    NSLocalizedDescriptionKey: "No email or password available for verification"
                ])
            }

            // Verify the email with Supabase
            try await supabaseService.verifyEmail(email: email, token: code)

            #if DEBUG
            print("🔐 AuthenticationManager: Email verification successful, attempting auto sign-in")
            #endif

            // Automatically sign in the user with the saved credentials
            do {
                // Sign in with Supabase
                _ = try await supabaseService.signIn(email: email, password: password)

                // Fetch user profile
                try await fetchUserProfile()

                // Update auth state
                authState = .signedIn

                // Clear saved credentials after successful sign-in
                clearConfirmationData()

                #if DEBUG
                print("🔐 AuthenticationManager: Auto sign-in successful after email verification")
                #endif
            } catch {
                // If auto sign-in fails, we still consider the verification successful
                // but we'll show a message to the user to sign in manually
                authState = .signedOut
                setErrorMessage("Email verified successfully. Please sign in with your credentials.")

                #if DEBUG
                print("🔐 AuthenticationManager: Auto sign-in failed after email verification - \(error)")
                #endif
            }
        } catch {
            setErrorMessage("Failed to verify email: \(error.localizedDescription)")
            authState = .signedOut

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

        // Clear any previous error message
        setErrorMessage(nil)

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
                // User is not signed in - this is normal for a fresh install
                authState = .signedOut
                userProfile = nil

                #if DEBUG
                print("🔐 AuthenticationManager: User is signed out")
                #endif
            }
        } catch let error as AuthError {
            // Handle Supabase auth errors
            authState = .signedOut
            userProfile = nil

            // Only set error message for unexpected errors, not for normal "not signed in" cases
            if case .api(_, let errorCode, _, _) = error,
               errorCode.rawValue == "refresh_token_not_found" {
                // This is normal for a fresh install, don't show an error
                #if DEBUG
                print("🔐 AuthenticationManager: No active session (refresh token not found)")
                #endif
            } else {
                setErrorMessage("Authentication error: \(error.localizedDescription)")
                #if DEBUG
                print("🔐 AuthenticationManager: Error checking auth state - \(error)")
                #endif
            }
        } catch {
            // Handle other errors
            authState = .signedOut
            userProfile = nil

            // Only show error message for unexpected errors
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
                // No profile found for this user ID
                #if DEBUG
                print("🔐 AuthenticationManager: User profile not found for ID: \(session.user.id.uuidString)")
                #endif

                throw NSError(domain: "AuthenticationManager", code: 404, userInfo: [
                    NSLocalizedDescriptionKey: "User profile not found"
                ])
            }
        } catch let error as AuthError {
            // Handle Supabase auth errors
            if case .api(_, let errorCode, _, _) = error,
               errorCode.rawValue == "refresh_token_not_found" {
                // This is normal for a fresh install
                #if DEBUG
                print("🔐 AuthenticationManager: No active session when fetching profile (refresh token not found)")
                #endif
            } else {
                #if DEBUG
                print("🔐 AuthenticationManager: Auth error fetching user profile - \(error)")
                #endif
            }
            throw error
        } catch let error as PostgrestError {
            // Handle database query errors
            #if DEBUG
            print("🔐 AuthenticationManager: Database error fetching user profile - \(error)")
            #endif
            throw error
        } catch {
            // Handle other errors
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
        setErrorMessage(nil)

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
            setErrorMessage("Failed to sign in: \(error.localizedDescription)")
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
        setErrorMessage(nil)

        // Save credentials for later use in email verification and auto sign-in
        saveConfirmationData(email: email, password: password)

        do {
            // Sign up with Supabase
            let response = try await supabaseService.signUp(email: email, password: password)

            // Check if sign up was successful
            if response.session != nil {
                // Fetch user profile
                try await fetchUserProfile()

                // Update auth state
                authState = .signedIn

                // Clear saved credentials since we're already signed in
                clearConfirmationData()

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
            setErrorMessage("Failed to sign up: \(error.localizedDescription)")
            authState = .signedOut

            // Clear saved credentials on error
            clearConfirmationData()

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
        setErrorMessage(nil)

        // This will be implemented with ASAuthorizationController
        // For now, we'll just show an error message
        setErrorMessage("Apple sign in is not yet implemented")
        isLoading = false
    }

    /// Sign in with Google
    func signInWithGoogle() {
        #if DEBUG
        print("🔐 AuthenticationManager: Starting Google sign in")
        #endif

        isLoading = true
        setErrorMessage(nil)

        // This will be implemented with GoogleSignIn SDK
        // For now, we'll just show an error message
        setErrorMessage("Google sign in is not yet implemented")
        isLoading = false
    }

    /// Sign in with Facebook
    func signInWithFacebook() {
        #if DEBUG
        print("🔐 AuthenticationManager: Starting Facebook sign in")
        #endif

        isLoading = true
        setErrorMessage(nil)

        // This will be implemented with Facebook SDK
        // For now, we'll just show an error message
        setErrorMessage("Facebook sign in is not yet implemented")
        isLoading = false
    }

    /// Sign out the current user
    func signOut() async {
        #if DEBUG
        print("🔐 AuthenticationManager: Signing out")
        #endif

        isLoading = true
        setErrorMessage(nil)

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
            setErrorMessage("Failed to sign out: \(error.localizedDescription)")

            #if DEBUG
            print("🔐 AuthenticationManager: Sign out failed - \(error)")
            #endif
        }

        isLoading = false
    }

    /// Check if the user signed in with email/password
    /// - Returns: Boolean indicating if the user signed in with email/password
    func isEmailPasswordUser() -> Bool {
        // If we have a user profile and the user has an email, assume they can change their email/password
        // This is a simplification - in a real app, you might want to store the provider in the user profile
        return userProfile != nil && authState == .signedIn
    }

    /// Change the user's password
    /// - Parameters:
    ///   - currentPassword: Current password for verification
    ///   - newPassword: New password to set
    func changePassword(currentPassword: String, newPassword: String) async {
        #if DEBUG
        print("🔐 AuthenticationManager: Attempting to change password")
        #endif

        isLoading = true
        setErrorMessage(nil)

        // Validate passwords
        guard !currentPassword.isEmpty else {
            setErrorMessage("Please enter your current password")
            isLoading = false
            return
        }

        guard !newPassword.isEmpty else {
            setErrorMessage("Please enter a new password")
            isLoading = false
            return
        }

        guard newPassword.count >= 6 else {
            setErrorMessage("New password must be at least 6 characters")
            isLoading = false
            return
        }

        do {
            // Change the password
            try await supabaseService.changePassword(currentPassword: currentPassword, newPassword: newPassword)

            // Show success message
            setErrorMessage("Password changed successfully")

            #if DEBUG
            print("🔐 AuthenticationManager: Password changed successfully")
            #endif
        } catch {
            setErrorMessage("Failed to change password: \(error.localizedDescription)")

            #if DEBUG
            print("🔐 AuthenticationManager: Failed to change password - \(error)")
            #endif
        }

        isLoading = false
    }

    /// Change the user's email
    /// - Parameters:
    ///   - newEmail: New email address
    ///   - password: Current password for verification
    func changeEmail(newEmail: String, password: String) async {
        #if DEBUG
        print("🔐 AuthenticationManager: Attempting to change email to: \(newEmail)")
        #endif

        isLoading = true
        setErrorMessage(nil)

        // Validate email and password
        guard !newEmail.isEmpty else {
            setErrorMessage("Please enter a new email address")
            isLoading = false
            return
        }

        guard !password.isEmpty else {
            setErrorMessage("Please enter your password")
            isLoading = false
            return
        }

        do {
            // Change the email
            try await supabaseService.changeEmail(newEmail: newEmail, password: password)

            // Show success message
            setErrorMessage("Email change initiated. Please check your new email for confirmation.")

            #if DEBUG
            print("🔐 AuthenticationManager: Email change initiated")
            #endif
        } catch {
            setErrorMessage("Failed to change email: \(error.localizedDescription)")

            #if DEBUG
            print("🔐 AuthenticationManager: Failed to change email - \(error)")
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
