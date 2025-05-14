import SwiftUI

struct EmailConfirmationView: View {
    @EnvironmentObject private var authManager: AuthenticationManager
    @State private var showingResendAlert = false

    var body: some View {
        ZStack {
            Theme.Colors.background
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.lg) {
                // Logo and title
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "envelope.badge.fill")
                        .font(.system(size: 60))
                        .foregroundColor(Theme.Colors.primary)

                    Text("Email Confirmation")
                        .font(Theme.Typography.h1)
                        .foregroundColor(Theme.Colors.text)

                    Text("Please check your email")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
                .padding(.top, Theme.Spacing.xl)

                // Confirmation message
                VStack(spacing: Theme.Spacing.md) {
                    Text("We've sent a confirmation link to your email address. Please check your inbox and click the link to verify your account.")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.text)
                        .multilineTextAlignment(.center)
                        .padding()

                    Text("After confirming your email, you'll be automatically redirected to the app and signed in. No need to enter your password again!")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Text("If you're using a different device to confirm your email, you'll need to sign in manually after confirmation.")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding()
                .background(Theme.Colors.secondaryBackground)
                .cornerRadius(Theme.Layout.cornerRadius)
                .padding(.horizontal)

                // Resend button
                Button(action: {
                    showingResendAlert = true
                }) {
                    Text("Didn't receive the email?")
                        .font(Theme.Typography.body.bold())
                        .foregroundColor(Theme.Colors.primary)
                }
                .padding(.top, Theme.Spacing.md)

                // Back to sign in button
                Button(action: {
                    authManager.authState = .signedOut
                }) {
                    Text("Back to Sign In")
                        .font(Theme.Typography.body.bold())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.Colors.primary)
                        .cornerRadius(Theme.Layout.cornerRadius)
                }
                .padding(.horizontal)
                .padding(.top, Theme.Spacing.xl)

                Spacer()
            }
            .padding()

            // Error message
            if let errorMessage = authManager.errorMessage {
                VStack {
                    Spacer()

                    Text(errorMessage)
                        .font(Theme.Typography.caption)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(Theme.Layout.cornerRadius)
                        .padding()
                        .onTapGesture {
                            authManager.dismissErrorMessage()
                        }
                        .transition(.opacity)
                        .animation(.easeInOut, value: authManager.errorMessage != nil)
                }
            }

            // Loading indicator
            if authManager.isLoading {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()

                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            }
        }
        .alert(isPresented: $showingResendAlert) {
            Alert(
                title: Text("Resend Confirmation Email"),
                message: Text("Would you like us to resend the confirmation email?"),
                primaryButton: .default(Text("Resend")) {
                    // Call the method to resend the confirmation email
                    Task {
                        await authManager.resendConfirmationEmail()
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }
}
