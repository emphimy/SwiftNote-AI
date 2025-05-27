import SwiftUI
import LocalAuthentication

struct AppLockView: View {
    @State private var isUnlocking = false
    @State private var errorMessage: String?
    @Binding var isLocked: Bool
    
    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()
            
            // App Logo
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 80))
                .foregroundColor(Theme.Colors.primary)
                .padding()
            
            Text("SwiftNote AI")
                .font(Theme.Typography.h1)
                .foregroundColor(Theme.Colors.primary)
            
            Text("Your notes are securely locked")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
            
            // Unlock Button
            Button(action: {
                authenticate()
            }) {
                HStack {
                    Image(systemName: getBiometricIcon())
                    Text("Unlock with \(getBiometricName())")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Theme.Colors.primary)
                .foregroundColor(.white)
                .cornerRadius(Theme.Layout.cornerRadius)
            }
            .padding(.horizontal)
            .disabled(isUnlocking)
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.error)
                    .padding(.top, Theme.Spacing.sm)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background.ignoresSafeArea())
        .onAppear {
            // Automatically try to authenticate when the view appears
            authenticate()
        }
    }
    
    private func authenticate() {
        isUnlocking = true
        errorMessage = nil
        
        Task {
            do {
                let success = try await BiometricAuthManager.shared.authenticate(
                    reason: "Unlock SwiftNote AI"
                )
                
                await MainActor.run {
                    if success {
                        withAnimation {
                            isLocked = false
                        }
                    } else {
                        errorMessage = "Authentication failed"
                    }
                    isUnlocking = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isUnlocking = false
                }
            }
        }
    }
    
    private func getBiometricName() -> String {
        return BiometricAuthManager.shared.biometricType() == .faceID ? "Face ID" : "Touch ID"
    }
    
    private func getBiometricIcon() -> String {
        return BiometricAuthManager.shared.biometricType() == .faceID ? "faceid" : "touchid"
    }
}

#if DEBUG
struct AppLockView_Previews: PreviewProvider {
    static var previews: some View {
        AppLockView(isLocked: .constant(true))
    }
}
#endif
