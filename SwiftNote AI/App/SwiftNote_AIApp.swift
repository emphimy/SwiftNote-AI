import SwiftUI
import CoreData
import GoogleSignIn

@main
struct SwiftNote_AIApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var themeManager = ThemeManager()
    @Environment(\.scenePhase) private var scenePhase
    @State private var supabaseInitialized = false
    @State private var deepLinkURL: URL?

    init() {
        // Initialize app without UserDefaults restoration
    }

    // Handle Google Sign In URL
    func handleGoogleSignInURL(_ url: URL) {
        #if DEBUG
        print("📱 App: Handling Google Sign In URL: \(url)")
        #endif

        // Process the URL with Google Sign In
        GIDSignIn.sharedInstance.handle(url)
    }

    // Handle deep links for authentication
    func handleDeepLink(_ url: URL) {
        #if DEBUG
        print("📱 App: Handling deep link: \(url)")
        #endif

        // Store the deep link URL to be processed by the AuthenticationManager
        deepLinkURL = url

        // Check if this is an auth-related deep link by examining the host and path
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()

        // First, check if this is a direct auth deep link (swiftnoteai://auth)
        if host == "auth" {
            #if DEBUG
            print("📱 App: Detected direct auth deep link")
            #endif

            // Extract query parameters
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
               let queryItems = components.queryItems {

                // Check for code parameter (used by Supabase for email confirmation)
                if let code = queryItems.first(where: { $0.name == "code" })?.value {
                    #if DEBUG
                    print("📱 App: Extracted code from auth deep link: \(code)")
                    #endif

                    // This is likely an email confirmation redirect
                    // We don't need to use the code for verification since Supabase already verified the email
                    // Just log it for debugging purposes
                    #if DEBUG
                    print("📱 App: Detected confirmation code, but not using it for verification")
                    #endif

                    // Post a notification that email was confirmed successfully
                    NotificationCenter.default.post(
                        name: Notification.Name("EmailConfirmationSuccess"),
                        object: nil
                    )

                    return
                }

                // Check for token parameter
                if let token = queryItems.first(where: { $0.name == "token" })?.value {
                    #if DEBUG
                    print("📱 App: Extracted token from auth deep link: \(token)")
                    print("📱 App: Detected token, but not using it for verification")
                    #endif

                    // Assume this is an email confirmation and trigger auto sign-in
                    NotificationCenter.default.post(
                        name: Notification.Name("EmailConfirmationSuccess"),
                        object: nil
                    )

                    return
                }

                // Check for type parameter to determine the auth action
                if let type = queryItems.first(where: { $0.name == "type" })?.value?.lowercased() {
                    if type == "recovery" || type == "reset" {
                        #if DEBUG
                        print("📱 App: Detected password reset deep link")
                        #endif

                        // Create a dictionary of all query parameters
                        var params = [String: String]()
                        for item in queryItems {
                            params[item.name] = item.value
                        }

                        // Post a notification for password reset
                        NotificationCenter.default.post(
                            name: Notification.Name("PasswordResetRedirect"),
                            object: nil,
                            userInfo: params
                        )

                        return
                    } else if type == "email_change" {
                        #if DEBUG
                        print("📱 App: Detected email change deep link")
                        #endif

                        // Post a notification for email change
                        NotificationCenter.default.post(
                            name: Notification.Name("EmailChangeSuccess"),
                            object: nil
                        )

                        return
                    } else if type == "signup" || type == "confirmation" {
                        #if DEBUG
                        print("📱 App: Detected email confirmation deep link")
                        #endif

                        // Post a notification that email was confirmed successfully
                        NotificationCenter.default.post(
                            name: Notification.Name("EmailConfirmationSuccess"),
                            object: nil
                        )

                        return
                    }
                }
            }

            // If we got here, it's a generic auth deep link without specific parameters
            // Let's assume it's an email confirmation success
            #if DEBUG
            print("📱 App: Assuming generic auth deep link is email confirmation")
            #endif

            NotificationCenter.default.post(
                name: Notification.Name("EmailConfirmationSuccess"),
                object: nil
            )

            return
        }

        // Check for path-based auth deep links (for backward compatibility)
        if path.contains("/auth") {
            // Determine the specific auth action
            if path.contains("/confirm/email") {
                // Email confirmation deep link
                #if DEBUG
                print("📱 App: Detected email confirmation path deep link")
                #endif

                // Post a notification that email was confirmed successfully
                NotificationCenter.default.post(
                    name: Notification.Name("EmailConfirmationSuccess"),
                    object: nil
                )
            } else if path.contains("/reset-password") {
                // Password reset deep link
                #if DEBUG
                print("📱 App: Detected password reset path deep link")
                #endif

                // Extract any token or parameters if needed
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
                   let queryItems = components.queryItems {

                    // Create a dictionary of all query parameters
                    var params = [String: String]()
                    for item in queryItems {
                        params[item.name] = item.value
                    }

                    // Post a notification for password reset
                    NotificationCenter.default.post(
                        name: Notification.Name("PasswordResetRedirect"),
                        object: nil,
                        userInfo: params
                    )
                }
            } else if path.contains("/change-email") {
                // Email change deep link
                #if DEBUG
                print("📱 App: Detected email change path deep link")
                #endif

                // Post a notification for email change
                NotificationCenter.default.post(
                    name: Notification.Name("EmailChangeSuccess"),
                    object: nil
                )
            } else if path.contains("/verify") {
                // This is a verification deep link (alternative format)
                #if DEBUG
                print("📱 App: Detected verification path deep link")
                #endif

                // Extract the token from the URL
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
                   let queryItems = components.queryItems,
                   let _ = queryItems.first(where: { $0.name == "token" })?.value {
                    #if DEBUG
                    print("📱 App: Detected token in verification path deep link")
                    print("📱 App: Not using token for verification")
                    #endif

                    // Assume this is an email confirmation and trigger auto sign-in
                    NotificationCenter.default.post(
                        name: Notification.Name("EmailConfirmationSuccess"),
                        object: nil
                    )
                }
            }
        } else {
            // Handle other types of deep links (non-auth related)
            #if DEBUG
            print("📱 App: Detected non-auth deep link")
            #endif

            // Add handling for other deep link types here if needed
        }
    }

    // Initialize Supabase and restore authentication when the app starts
    private func initializeSupabase() async {
        if !supabaseInitialized {
            await SupabaseService.shared.initialize()
            supabaseInitialized = true

            #if DEBUG
            print("📱 App: Supabase initialized")
            #endif

            // Check which auth provider was used
            let authProvider = UserDefaults.standard.string(forKey: "auth_provider")

            #if DEBUG
            print("📱 App: Stored auth provider: \(authProvider ?? "none")")
            #endif

            // Only restore Google Sign In if it was the last used provider
            if authProvider == "google" {
                Task {
                    do {
                        let result = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
                        #if DEBUG
                        if let email = result.profile?.email {
                            print("📱 App: Restored Google Sign In for user: \(email)")
                        }
                        #endif
                    } catch {
                        #if DEBUG
                        print("📱 App: Error restoring Google Sign In: \(error)")
                        #endif
                    }
                }
            } else if authProvider != "google" {
                // If we're not using Google, make sure to sign out from Google
                GIDSignIn.sharedInstance.signOut()
                #if DEBUG
                print("📱 App: Signed out from Google since another provider is being used")
                #endif
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            AuthenticationWrapper {
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
            .onOpenURL { url in
                #if DEBUG
                print("📱 App: Received URL: \(url)")
                #endif

                // Check if this is a Google Sign In URL
                if let scheme = url.scheme, scheme.contains("com.googleusercontent.apps") {
                    // Handle Google Sign In URL
                    handleGoogleSignInURL(url)
                } else {
                    // Handle other deep links
                    handleDeepLink(url)
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
