import SwiftUI
import AuthenticationServices
import Combine

struct AuthenticationView: View {
    @EnvironmentObject private var authManager: AuthenticationManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Gradient background
                LinearGradient(
                    colors: [
                        Theme.Colors.background,
                        Theme.Colors.secondaryBackground.opacity(0.3)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        // Top spacer
                        Spacer()
                            .frame(height: geometry.safeAreaInsets.top + 30)

                        // Hero section with logo and branding
                        VStack(spacing: Theme.Spacing.xl) {
                            // App logo with elegant presentation
                            VStack(spacing: Theme.Spacing.xl) {
                                // Logo with subtle glow effect and rounded corners
                                ZStack {
                                    // Subtle glow effect
                                    RoundedRectangle(cornerRadius: 28)
                                        .fill(
                                            RadialGradient(
                                                colors: [
                                                    Theme.Colors.primary.opacity(0.12),
                                                    Color.clear
                                                ],
                                                center: .center,
                                                startRadius: 0,
                                                endRadius: 120
                                            )
                                        )
                                        .frame(width: 240, height: 240)

                                    // App logo with rounded corners
                                    Image("SwiftNote_Logo")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 110, height: 110)
                                        .clipShape(RoundedRectangle(cornerRadius: 24))
                                        .shadow(
                                            color: Color.black.opacity(0.1),
                                            radius: 12,
                                            x: 0,
                                            y: 6
                                        )
                                }

                                // Enhanced social proof badges based on actual features
                                VStack(spacing: Theme.Spacing.md) {
                                    // First row of badges
                                    HStack(spacing: Theme.Spacing.sm) {
                                        // AI Transcription badge
                                        FeatureBadge(
                                            icon: "waveform.and.mic",
                                            text: "Audio Notes",
                                            color: Theme.Colors.primary
                                        )

                                        // Auto Notes badge
                                        FeatureBadge(
                                            icon: "doc.text.magnifyingglass",
                                            text: "Text Notes",
                                            color: Theme.Colors.secondary
                                        )

                                        // YouTube Support badge
                                        FeatureBadge(
                                            icon: "play.rectangle",
                                            text: "Video Notes",
                                            color: Theme.Colors.error
                                        )
                                    }

                                    // Second row of badges
                                    HStack(spacing: Theme.Spacing.sm) {
                                        // Quiz Generation badge
                                        FeatureBadge(
                                            icon: "questionmark.circle",
                                            text: "Quiz Gen",
                                            color: Theme.Colors.success
                                        )

                                        // Flashcards badge
                                        FeatureBadge(
                                            icon: "rectangle.stack",
                                            text: "Flashcards",
                                            color: Theme.Colors.accent
                                        )

                                        // AI Chat badge
                                        FeatureBadge(
                                            icon: "bubble.left.and.bubble.right",
                                            text: "AI Chat",
                                            color: Theme.Colors.primary
                                        )
                                    }
                                }
                            }

                            // App title and tagline
                            VStack(spacing: Theme.Spacing.md) {
                                Text("SwiftNote AI")
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .foregroundColor(Theme.Colors.text)

                                VStack(spacing: Theme.Spacing.xs) {
                                    Text("Transform audio, video & text into")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundColor(Theme.Colors.secondaryText)

                                    Text("smart study materials")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(Theme.Colors.primary)
                                }
                                .multilineTextAlignment(.center)
                            }
                            .padding(.horizontal, Theme.Spacing.lg)
                        }
                        .padding(.bottom, Theme.Spacing.lg)

                        // CTA and Authentication section
                        VStack(spacing: Theme.Spacing.lg) {
                            // Professional CTA
                            Text("Get Started")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(Theme.Colors.secondaryText)

                            // Authentication buttons (Apple first, then Google)
                            VStack(spacing: Theme.Spacing.md) {
                                // Apple sign-in button (first)
                                AppleSignInButton(
                                    onCompletion: { result in
                                        Task {
                                            await authManager.handleAppleSignIn(result: result)
                                        }
                                    },
                                    onRequest: { request in
                                        let (hashedNonce, _) = authManager.prepareAppleSignIn()
                                        request.nonce = hashedNonce
                                    },
                                    style: .black,
                                    cornerRadius: 16,
                                    height: 56
                                )
                                .frame(height: 56)
                                .disabled(authManager.isLoading)

                                // Google sign-in button (second)
                                Button(action: {
                                    authManager.signInWithGoogle()
                                }) {
                                    HStack(spacing: Theme.Spacing.md) {
                                        Image("google_logo")
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 24, height: 24)

                                        Text("Continue with Google")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(Theme.Colors.text)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 56)
                                    .background(Color.white)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.black.opacity(0.1), lineWidth: 1)
                                    )
                                    .cornerRadius(16)
                                    .shadow(
                                        color: Color.black.opacity(0.04),
                                        radius: 8,
                                        x: 0,
                                        y: 2
                                    )
                                }
                                .disabled(authManager.isLoading)
                            }
                            .padding(.horizontal, Theme.Spacing.lg)
                        }

                        // Bottom spacer
                        Spacer()
                            .frame(height: geometry.safeAreaInsets.bottom + 24)
                    }
                }
                .scrollIndicators(.hidden)
            }
        }

                // Error message overlay
                if let errorMessage = authManager.errorMessage {
                    VStack {
                        Spacer()

                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.white)

                            Text(errorMessage)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.leading)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Theme.Colors.error)
                                .shadow(
                                    color: Theme.Colors.error.opacity(0.3),
                                    radius: 8,
                                    x: 0,
                                    y: 4
                                )
                        )
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.bottom, 100)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                authManager.dismissErrorMessage()
                            }
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }

                // Loading overlay
                if authManager.isLoading {
                    ZStack {
                        // Full screen background
                        Theme.Colors.background
                            .ignoresSafeArea()
                            .onTapGesture { } // Prevent interaction

                        // Centered loading content
                        VStack(spacing: Theme.Spacing.xl) {
                            // App logo
                            Image("SwiftNote_Logo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 16))

                            VStack(spacing: Theme.Spacing.lg) {
                                ProgressView()
                                    .scaleEffect(1.2)
                                    .progressViewStyle(CircularProgressViewStyle(tint: Theme.Colors.primary))

                                Text("Signing you in...")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(Theme.Colors.primary)
                            }
                        }
                    }
                }
            }
        }

// MARK: - Feature Badge Component
struct FeatureBadge: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(color)

            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
                .overlay(
                    Capsule()
                        .stroke(color.opacity(0.2), lineWidth: 0.5)
                )
        )
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
