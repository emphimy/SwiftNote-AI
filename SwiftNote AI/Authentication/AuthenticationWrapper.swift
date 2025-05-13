import SwiftUI

struct AuthenticationWrapper<Content: View>: View {
    @StateObject private var authManager = AuthenticationManager()
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            switch authManager.authState {
            case .initializing:
                // Show loading screen while checking auth state
                LoadingView(message: "Loading...")

            case .signedOut:
                // Show authentication view
                AuthenticationView()
                    .environmentObject(authManager)

            case .confirmationRequired:
                // Show email confirmation view
                EmailConfirmationView()
                    .environmentObject(authManager)

            case .signedIn:
                // Show main app content
                content()
                    .environmentObject(authManager)
            }
        }
    }
}

// MARK: - Loading View
struct LoadingView: View {
    let message: String

    var body: some View {
        ZStack {
            Theme.Colors.background
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.md) {
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle(tint: Theme.Colors.primary))

                Text(message)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.secondaryText)
            }
        }
    }
}
