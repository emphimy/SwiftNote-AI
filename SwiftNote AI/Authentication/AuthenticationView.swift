import SwiftUI
import AuthenticationServices
import Combine

struct AuthenticationView: View {
    // Flag to control whether email authentication is enabled
    private let isEmailAuthEnabled = false // Set to false to hide email auth

    @EnvironmentObject private var authManager: AuthenticationManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var isSignIn = true
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isPasswordVisible = false
    @State private var isConfirmPasswordVisible = false
    @State private var showingForgotPasswordAlert = false
    @State private var forgotPasswordEmail = ""
    @FocusState private var focusedField: Field?

    enum Field {
        case email, password, confirmPassword
    }

    var body: some View {
        ZStack {
            // Background with tap gesture to dismiss keyboard
            Theme.Colors.background
                .ignoresSafeArea()
                .onTapGesture {
                    dismissKeyboard()
                }

            VStack(spacing: Theme.Spacing.lg) {
                // Logo and title
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "note.text")
                        .font(.system(size: 60))
                        .foregroundColor(Theme.Colors.primary)

                    Text("SwiftNote AI")
                        .font(Theme.Typography.h1)
                        .foregroundColor(Theme.Colors.text)

                    Text("Sign in to your account")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
                .padding(.top, Theme.Spacing.xl)

                // Email authentication form (only shown if enabled)
                if isEmailAuthEnabled {
                    VStack(spacing: Theme.Spacing.md) {
                        // Email field
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)
                            .onSubmit {
                                focusedField = .password
                            }
                            .padding()
                            .background(Theme.Colors.secondaryBackground)
                            .cornerRadius(Theme.Layout.cornerRadius)

                        // Password field
                        HStack {
                            if isPasswordVisible {
                                TextField("Password", text: $password)
                                    .textContentType(isSignIn ? .password : .newPassword)
                                    .focused($focusedField, equals: .password)
                                    .submitLabel(isSignIn ? .done : .next)
                                    .onSubmit {
                                        if isSignIn {
                                            dismissKeyboard()
                                        } else {
                                            focusedField = .confirmPassword
                                        }
                                    }
                            } else {
                                SecureField("Password", text: $password)
                                    .textContentType(isSignIn ? .password : .newPassword)
                                    .focused($focusedField, equals: .password)
                                    .submitLabel(isSignIn ? .done : .next)
                                    .onSubmit {
                                        if isSignIn {
                                            dismissKeyboard()
                                        } else {
                                            focusedField = .confirmPassword
                                        }
                                    }
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
                                        .focused($focusedField, equals: .confirmPassword)
                                        .submitLabel(.done)
                                        .onSubmit {
                                            dismissKeyboard()
                                        }
                                } else {
                                    SecureField("Confirm Password", text: $confirmPassword)
                                        .textContentType(.newPassword)
                                        .focused($focusedField, equals: .confirmPassword)
                                        .submitLabel(.done)
                                        .onSubmit {
                                            dismissKeyboard()
                                        }
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

                        // Forgot password button (sign in only)
                        if isSignIn {
                            Button(action: {
                                forgotPasswordEmail = email // Pre-fill with current email
                                showingForgotPasswordAlert = true
                            }) {
                                Text("Forgot Password?")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.primary)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .padding(.trailing, 4)
                            }
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
                }

                // Social sign-in options
                VStack(spacing: Theme.Spacing.md) {
                    Text(isEmailAuthEnabled ? "Or continue with" : "Sign in with")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)

                    VStack(spacing: Theme.Spacing.md) {
                        // Apple sign-in (default)
                        AppleSignInButton(
                            onCompletion: { result in
                                Task {
                                    await authManager.handleAppleSignIn(result: result)
                                }
                            },
                            onRequest: { request in
                                // Get both the hashed nonce (for Apple) and raw nonce (stored for Supabase)
                                let (hashedNonce, _) = authManager.prepareAppleSignIn()
                                // Apple requires the hashed nonce
                                request.nonce = hashedNonce
                            },
                            style: colorScheme == .dark ? .white : .black,
                            cornerRadius: Theme.Layout.cornerRadius,
                            height: 50
                        )
                        .frame(height: 50)

                        // Google sign-in
                        GoogleSignInButton(
                            action: {
                                // Trigger the Google Sign In flow
                                authManager.signInWithGoogle()
                            },
                            height: 50,
                            cornerRadius: Theme.Layout.cornerRadius
                        )
                    }
                    .frame(maxWidth: 280)
                }

                // Toggle between sign in and sign up (only shown if email auth is enabled)
                if isEmailAuthEnabled {
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
        // Forgot password alert
        .alert("Reset Password", isPresented: $showingForgotPasswordAlert) {
            TextField("Email", text: $forgotPasswordEmail)
                .autocapitalization(.none)
                .keyboardType(.emailAddress)

            Button("Cancel", role: .cancel) {}

            Button("Send Reset Link") {
                Task {
                    await authManager.resetPassword(email: forgotPasswordEmail)
                }
            }
        } message: {
            Text("Enter your email address and we'll send you a link to reset your password.")
        }
    }

    // Dismiss the keyboard
    private func dismissKeyboard() {
        focusedField = nil
    }

    // Validate form fields
    private var isFormValid: Bool {
        // If email auth is disabled, we don't need to validate the form
        if !isEmailAuthEnabled {
            return true
        }

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
