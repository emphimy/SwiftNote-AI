import SwiftUI
import AuthenticationServices

/// A button that initiates the Sign in with Apple flow
struct AppleSignInButton: UIViewRepresentable {
    var onCompletion: (Result<ASAuthorization, Error>) -> Void
    var onRequest: ((ASAuthorizationAppleIDRequest) -> Void)?

    // Button style
    var style: ASAuthorizationAppleIDButton.Style = .black
    var type: ASAuthorizationAppleIDButton.ButtonType = .continue
    var cornerRadius: CGFloat?
    var height: CGFloat = 50

    // MARK: - UIViewRepresentable
    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: type, style: style)

        // Apply custom corner radius if provided
        if let cornerRadius = cornerRadius {
            button.cornerRadius = cornerRadius
        }

        // Disable auto constraints
        button.translatesAutoresizingMaskIntoConstraints = false

        // Add target
        button.addTarget(context.coordinator, action: #selector(Coordinator.handleAppleSignIn), for: .touchUpInside)

        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {
        // Update button properties if needed
        if let cornerRadius = cornerRadius {
            uiView.cornerRadius = cornerRadius
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ASAuthorizationAppleIDButton, context: Context) -> CGSize? {
        return CGSize(width: proposal.width ?? .infinity, height: height)
    }

    // MARK: - Coordinator
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        var parent: AppleSignInButton

        init(_ parent: AppleSignInButton) {
            self.parent = parent
        }

        // MARK: - Button Action
        @objc func handleAppleSignIn() {
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]

            // Call onRequest if provided
            parent.onRequest?(request)

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }

        // MARK: - ASAuthorizationControllerDelegate
        func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
            parent.onCompletion(.success(authorization))
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            parent.onCompletion(.failure(error))
        }

        // MARK: - ASAuthorizationControllerPresentationContextProviding
        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            let scenes = UIApplication.shared.connectedScenes
            let windowScene = scenes.first as? UIWindowScene
            let window = windowScene?.windows.first
            return window ?? UIWindow()
        }
    }
}

// MARK: - Preview
struct AppleSignInButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            AppleSignInButton(
                onCompletion: { _ in },
                style: .black,
                cornerRadius: 8,
                height: 50
            )
            .frame(height: 50)
            .padding()

            AppleSignInButton(
                onCompletion: { _ in },
                style: .white,
                cornerRadius: 8,
                height: 50
            )
            .frame(height: 50)
            .padding()
            .background(Color.black.opacity(0.1))
        }
    }
}
