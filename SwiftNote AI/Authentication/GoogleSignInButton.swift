import SwiftUI
import GoogleSignIn
import UIKit

/// A button that initiates the Sign in with Google flow
struct GoogleSignInButton: View {
    var action: () -> Void
    var height: CGFloat = 50
    var cornerRadius: CGFloat = 8

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Google logo
                Image("google_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)

                // Button text
                Text("Continue with Google")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color(.darkGray))
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Color.white)
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
    }
}

/// A UIViewRepresentable wrapper for GIDSignInButton
struct NativeGoogleSignInButton: UIViewRepresentable {
    var action: () -> Void

    func makeUIView(context: Context) -> GIDSignInButton {
        let button = GIDSignInButton()
        button.style = .wide
        button.colorScheme = .light
        button.addTarget(context.coordinator, action: #selector(Coordinator.buttonTapped), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: GIDSignInButton, context: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func buttonTapped() {
            action()
        }
    }
}

// MARK: - Preview
struct GoogleSignInButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            GoogleSignInButton(action: {})
                .padding()

            GoogleSignInButton(action: {})
                .padding()
                .preferredColorScheme(.dark)
        }
    }
}
