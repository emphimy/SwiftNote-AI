import SwiftUI

struct AuthProfileView: View {
    @EnvironmentObject private var authManager: AuthenticationManager
    @Environment(\.presentationMode) private var presentationMode
    @State private var showingSignOutAlert = false

    // Change email states
    @State private var showingChangeEmailSheet = false
    @State private var newEmail = ""
    @State private var emailPassword = ""

    // Change password states
    @State private var showingChangePasswordSheet = false
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmNewPassword = ""

    // Focus states for text fields
    @FocusState private var emailFocusedField: EmailField?
    @FocusState private var passwordFocusedField: PasswordField?

    enum EmailField {
        case email, password
    }

    enum PasswordField {
        case current, new, confirm
    }

    // For profile updates
    @State private var profileUpdateCounter = 0

    var body: some View {
        NavigationView {
            ZStack {
                Theme.Colors.background
                    .ignoresSafeArea()

                VStack(spacing: Theme.Spacing.lg) {
                    // Profile header
                    VStack(spacing: Theme.Spacing.md) {
                        // Profile image
                        if let avatarUrl = authManager.userProfile?.avatarUrl, !avatarUrl.isEmpty {
                            AsyncImage(url: URL(string: avatarUrl)) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Theme.Colors.primary, lineWidth: 2))
                        } else {
                            // Default profile image
                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundColor(Theme.Colors.primary)
                                .frame(width: 100, height: 100)
                        }

                        // User name or email
                        Text(authManager.userProfile?.fullName ?? authManager.userProfile?.email ?? "User")
                            .font(Theme.Typography.h3)
                            .foregroundColor(Theme.Colors.text)
                    }
                    .padding(.top, Theme.Spacing.lg)

                    // Profile details
                    VStack(spacing: Theme.Spacing.md) {
                        ProfileDetailRow(icon: "envelope", title: "Email", value: authManager.userProfile?.email ?? "")

                        if let createdAt = authManager.userProfile?.createdAt {
                            ProfileDetailRow(
                                icon: "calendar",
                                title: "Member Since",
                                value: dateFormatter.string(from: createdAt)
                            )
                        }
                    }
                    .padding()
                    .background(Theme.Colors.secondaryBackground)
                    .cornerRadius(Theme.Layout.cornerRadius)
                    .padding(.horizontal)

                    // Account settings section (only for email/password users)
                    if authManager.isEmailPasswordUser() {
                        VStack(spacing: Theme.Spacing.md) {
                            Text("Account Settings")
                                .font(Theme.Typography.h3)
                                .foregroundColor(Theme.Colors.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)

                            VStack(spacing: 0) {
                                // Change Email Button
                                Button(action: {
                                    showingChangeEmailSheet = true
                                    newEmail = authManager.userProfile?.email ?? ""
                                    emailPassword = ""
                                }) {
                                    HStack {
                                        Image(systemName: "envelope.badge")
                                            .foregroundColor(Theme.Colors.primary)
                                            .frame(width: 24)

                                        Text("Change Email")
                                            .font(Theme.Typography.body)
                                            .foregroundColor(Theme.Colors.text)

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .foregroundColor(Theme.Colors.secondaryText)
                                    }
                                    .padding()
                                }

                                Divider()
                                    .padding(.horizontal)

                                // Change Password Button
                                Button(action: {
                                    showingChangePasswordSheet = true
                                    currentPassword = ""
                                    newPassword = ""
                                    confirmNewPassword = ""
                                }) {
                                    HStack {
                                        Image(systemName: "lock.rotation")
                                            .foregroundColor(Theme.Colors.primary)
                                            .frame(width: 24)

                                        Text("Change Password")
                                            .font(Theme.Typography.body)
                                            .foregroundColor(Theme.Colors.text)

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .foregroundColor(Theme.Colors.secondaryText)
                                    }
                                    .padding()
                                }
                            }
                            .background(Theme.Colors.secondaryBackground)
                            .cornerRadius(Theme.Layout.cornerRadius)
                            .padding(.horizontal)
                        }
                    }

                    Spacer()

                    // Sign out button
                    Button(action: {
                        showingSignOutAlert = true
                    }) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Sign Out")
                        }
                        .font(Theme.Typography.body.bold())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .cornerRadius(Theme.Layout.cornerRadius)
                        .padding(.horizontal)
                    }
                    .padding(.bottom, Theme.Spacing.lg)
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
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "xmark")
                        .foregroundColor(Theme.Colors.primary)
                },
                trailing: Button(action: {
                    Task {
                        await authManager.refreshUserProfile()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(Theme.Colors.primary)
                }
            )
            .alert(isPresented: $showingSignOutAlert) {
                Alert(
                    title: Text("Sign Out"),
                    message: Text("Are you sure you want to sign out?"),
                    primaryButton: .destructive(Text("Sign Out")) {
                        Task {
                            await authManager.signOut()
                        }
                    },
                    secondaryButton: .cancel()
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .userProfileUpdated)) { _ in
                // Force view to refresh when profile is updated
                profileUpdateCounter += 1

                #if DEBUG
                print("🔐 AuthProfileView: Received profile update notification")
                if let email = authManager.userProfile?.email {
                    print("🔐 AuthProfileView: Current email in profile: \(email)")
                }
                #endif
            }
            .id(profileUpdateCounter) // Force view to refresh when counter changes
            .onAppear {
                // Refresh the profile when the view appears
                Task {
                    await authManager.refreshUserProfile()
                }
            }
            // Change Email Sheet
            .sheet(isPresented: $showingChangeEmailSheet) {
                NavigationView {
                    ZStack {
                        Theme.Colors.background
                            .ignoresSafeArea()
                            .onTapGesture {
                                dismissKeyboard()
                            }

                        VStack(spacing: Theme.Spacing.lg) {
                            Text("Change your email address")
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                                .padding(.top, Theme.Spacing.lg)

                            VStack(spacing: Theme.Spacing.md) {
                                // New Email Field
                                TextField("New Email", text: $newEmail)
                                    .textContentType(.emailAddress)
                                    .keyboardType(.emailAddress)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                                    .focused($emailFocusedField, equals: .email)
                                    .submitLabel(.next)
                                    .onSubmit {
                                        emailFocusedField = .password
                                    }
                                    .padding()
                                    .background(Theme.Colors.secondaryBackground)
                                    .cornerRadius(Theme.Layout.cornerRadius)

                                // Password Field
                                SecureField("Current Password", text: $emailPassword)
                                    .textContentType(.password)
                                    .focused($emailFocusedField, equals: .password)
                                    .submitLabel(.done)
                                    .onSubmit {
                                        dismissKeyboard()
                                    }
                                    .padding()
                                    .background(Theme.Colors.secondaryBackground)
                                    .cornerRadius(Theme.Layout.cornerRadius)
                            }
                            .padding(.horizontal)

                            // Submit Button
                            Button(action: {
                                Task {
                                    await authManager.changeEmail(newEmail: newEmail, password: emailPassword)
                                    if authManager.errorMessage?.contains("initiated") ?? false {
                                        // Show a toast or alert that the email change has been initiated
                                        authManager.setErrorMessage("Email change initiated. Please check your new email for confirmation.")

                                        // Close the sheet
                                        showingChangeEmailSheet = false
                                    }
                                }
                            }) {
                                Text("Update Email")
                                    .font(Theme.Typography.body.bold())
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Theme.Colors.primary)
                                    .cornerRadius(Theme.Layout.cornerRadius)
                                    .padding(.horizontal)
                            }
                            .disabled(authManager.isLoading || newEmail.isEmpty || emailPassword.isEmpty)
                            .opacity((newEmail.isEmpty || emailPassword.isEmpty) ? 0.6 : 1.0)

                            // Email change instructions
                            VStack(spacing: 8) {
                                Text("Important:")
                                    .font(Theme.Typography.caption.bold())
                                    .foregroundColor(Theme.Colors.primary)

                                Text("After submitting, you'll receive a confirmation email at your new address. You must click the link in that email to complete the change.")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.secondaryText)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                            .padding(.top, 8)

                            Spacer()

                            // Error message
                            if let errorMessage = authManager.errorMessage {
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
                    .navigationTitle("Change Email")
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationBarItems(leading:
                        Button(action: {
                            showingChangeEmailSheet = false
                        }) {
                            Image(systemName: "xmark")
                                .foregroundColor(Theme.Colors.primary)
                        }
                    )
                }
            }

            // Change Password Sheet
            .sheet(isPresented: $showingChangePasswordSheet) {
                NavigationView {
                    ZStack {
                        Theme.Colors.background
                            .ignoresSafeArea()
                            .onTapGesture {
                                dismissKeyboard()
                            }

                        VStack(spacing: Theme.Spacing.lg) {
                            Text("Change your password")
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                                .padding(.top, Theme.Spacing.lg)

                            VStack(spacing: Theme.Spacing.md) {
                                // Current Password Field
                                SecureField("Current Password", text: $currentPassword)
                                    .textContentType(.password)
                                    .focused($passwordFocusedField, equals: .current)
                                    .submitLabel(.next)
                                    .onSubmit {
                                        passwordFocusedField = .new
                                    }
                                    .padding()
                                    .background(Theme.Colors.secondaryBackground)
                                    .cornerRadius(Theme.Layout.cornerRadius)

                                // New Password Field
                                SecureField("New Password", text: $newPassword)
                                    .textContentType(.newPassword)
                                    .focused($passwordFocusedField, equals: .new)
                                    .submitLabel(.next)
                                    .onSubmit {
                                        passwordFocusedField = .confirm
                                    }
                                    .padding()
                                    .background(Theme.Colors.secondaryBackground)
                                    .cornerRadius(Theme.Layout.cornerRadius)

                                // Confirm New Password Field
                                SecureField("Confirm New Password", text: $confirmNewPassword)
                                    .textContentType(.newPassword)
                                    .focused($passwordFocusedField, equals: .confirm)
                                    .submitLabel(.done)
                                    .onSubmit {
                                        dismissKeyboard()
                                    }
                                    .padding()
                                    .background(Theme.Colors.secondaryBackground)
                                    .cornerRadius(Theme.Layout.cornerRadius)
                            }
                            .padding(.horizontal)

                            // Submit Button
                            Button(action: {
                                if newPassword == confirmNewPassword {
                                    Task {
                                        await authManager.changePassword(currentPassword: currentPassword, newPassword: newPassword)
                                        if authManager.errorMessage?.contains("successfully") ?? false {
                                            showingChangePasswordSheet = false
                                        }
                                    }
                                } else {
                                    authManager.setErrorMessage("New passwords do not match")
                                }
                            }) {
                                Text("Update Password")
                                    .font(Theme.Typography.body.bold())
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Theme.Colors.primary)
                                    .cornerRadius(Theme.Layout.cornerRadius)
                                    .padding(.horizontal)
                            }
                            .disabled(authManager.isLoading || !isPasswordFormValid)
                            .opacity(isPasswordFormValid ? 1.0 : 0.6)

                            Spacer()

                            // Error message
                            if let errorMessage = authManager.errorMessage {
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
                    .navigationTitle("Change Password")
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationBarItems(leading:
                        Button(action: {
                            showingChangePasswordSheet = false
                        }) {
                            Image(systemName: "xmark")
                                .foregroundColor(Theme.Colors.primary)
                        }
                    )
                }
            }
        }
    }

    // Dismiss the keyboard
    private func dismissKeyboard() {
        emailFocusedField = nil
        passwordFocusedField = nil
    }

    // Validate password form
    private var isPasswordFormValid: Bool {
        return !currentPassword.isEmpty &&
               !newPassword.isEmpty &&
               !confirmNewPassword.isEmpty &&
               newPassword == confirmNewPassword &&
               newPassword.count >= 6
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }
}

// MARK: - Profile Detail Row
struct ProfileDetailRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .foregroundColor(Theme.Colors.primary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)

                Text(value)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.text)
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}
