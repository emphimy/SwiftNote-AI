import SwiftUI
import AuthenticationServices

struct AuthenticationView: View {
    @EnvironmentObject private var authManager: AuthenticationManager
    @State private var isSignIn = true
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isPasswordVisible = false
    @State private var isConfirmPasswordVisible = false

    var body: some View {
        ZStack {
            Theme.Colors.background
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.lg) {
                // Logo and title
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "note.text")
                        .font(.system(size: 60))
                        .foregroundColor(Theme.Colors.primary)

                    Text("SwiftNote AI")
                        .font(Theme.Typography.h1)
                        .foregroundColor(Theme.Colors.text)

                    Text(isSignIn ? "Sign in to your account" : "Create a new account")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
                .padding(.top, Theme.Spacing.xl)

                // Form
                VStack(spacing: Theme.Spacing.md) {
                    // Email field
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .padding()
                        .background(Theme.Colors.secondaryBackground)
                        .cornerRadius(Theme.Layout.cornerRadius)

                    // Password field
                    HStack {
                        if isPasswordVisible {
                            TextField("Password", text: $password)
                                .textContentType(isSignIn ? .password : .newPassword)
                        } else {
                            SecureField("Password", text: $password)
                                .textContentType(isSignIn ? .password : .newPassword)
                        }

                        Button(action: {
                            isPasswordVisible.toggle()
                        }) {
                            Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                .foregroundColor(Theme.Colors.secondaryText)
                        }
                    }
                    .padding()
                    .background(Theme.Colors.secondaryBackground)
                    .cornerRadius(Theme.Layout.cornerRadius)

                    // Confirm password field (sign up only)
                    if !isSignIn {
                        HStack {
                            if isConfirmPasswordVisible {
                                TextField("Confirm Password", text: $confirmPassword)
                                    .textContentType(.newPassword)
                            } else {
                                SecureField("Confirm Password", text: $confirmPassword)
                                    .textContentType(.newPassword)
                            }

                            Button(action: {
                                isConfirmPasswordVisible.toggle()
                            }) {
                                Image(systemName: isConfirmPasswordVisible ? "eye.slash" : "eye")
                                    .foregroundColor(Theme.Colors.secondaryText)
                            }
                        }
                        .padding()
                        .background(Theme.Colors.secondaryBackground)
                        .cornerRadius(Theme.Layout.cornerRadius)
                    }

                    // Sign in/up button
                    Button(action: {
                        Task {
                            if isSignIn {
                                await authManager.signInWithEmail(email: email, password: password)
                            } else {
                                if password == confirmPassword {
                                    await authManager.signUpWithEmail(email: email, password: password)
                                } else {
                                    authManager.errorMessage = "Passwords do not match"
                                }
                            }
                        }
                    }) {
                        Text(isSignIn ? "Sign In" : "Sign Up")
                            .font(Theme.Typography.body.bold())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Theme.Colors.primary)
                            .cornerRadius(Theme.Layout.cornerRadius)
                    }
                    .disabled(authManager.isLoading || !isFormValid)
                    .opacity(isFormValid ? 1.0 : 0.6)
                }
                .padding(.horizontal, Theme.Spacing.lg)

                // Social sign-in options
                VStack(spacing: Theme.Spacing.md) {
                    Text("Or continue with")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)

                    HStack(spacing: Theme.Spacing.md) {
                        // Apple sign-in
                        SocialSignInButton(
                            icon: "apple.logo",
                            backgroundColor: .black,
                            foregroundColor: .white
                        ) {
                            authManager.signInWithApple()
                        }

                        // Google sign-in
                        SocialSignInButton(
                            icon: "g.circle.fill",
                            backgroundColor: .white,
                            foregroundColor: .red
                        ) {
                            authManager.signInWithGoogle()
                        }

                        // Facebook sign-in
                        SocialSignInButton(
                            icon: "f.circle.fill",
                            backgroundColor: Color(red: 0.23, green: 0.35, blue: 0.6),
                            foregroundColor: .white
                        ) {
                            authManager.signInWithFacebook()
                        }
                    }
                }

                // Toggle between sign in and sign up
                Button(action: {
                    withAnimation {
                        isSignIn.toggle()
                        // Clear fields when switching modes
                        password = ""
                        confirmPassword = ""
                    }
                }) {
                    Text(isSignIn ? "Don't have an account? Sign Up" : "Already have an account? Sign In")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.primary)
                }

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
    }

    // Validate form fields
    private var isFormValid: Bool {
        if isSignIn {
            return !email.isEmpty && !password.isEmpty
        } else {
            return !email.isEmpty && !password.isEmpty && !confirmPassword.isEmpty && password == confirmPassword
        }
    }
}

// MARK: - Social Sign-In Button
struct SocialSignInButton: View {
    let icon: String
    let backgroundColor: Color
    let foregroundColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(foregroundColor)
                .frame(width: 60, height: 60)
                .background(backgroundColor)
                .cornerRadius(Theme.Layout.cornerRadius)
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        }
    }
}
