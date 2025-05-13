import SwiftUI

struct AuthProfileView: View {
    @EnvironmentObject private var authManager: AuthenticationManager
    @Environment(\.presentationMode) private var presentationMode
    @State private var showingSignOutAlert = false

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
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .foregroundColor(Theme.Colors.primary)
                    }
                }
            }
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
        }
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
