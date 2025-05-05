import SwiftUI

struct AppLockWrapper<Content: View>: View {
    @State private var isLocked = false
    private let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        ZStack {
            content
                .disabled(isLocked)
                .blur(radius: isLocked ? 10 : 0)
            
            if isLocked {
                AppLockView(isLocked: $isLocked)
                    .transition(.opacity)
            }
        }
        .onAppear {
            checkIfAppShouldBeLocked()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            checkIfAppShouldBeLocked()
        }
    }
    
    private func checkIfAppShouldBeLocked() {
        // Check if biometric lock is enabled
        if BiometricAuthManager.shared.isAppLocked() {
            isLocked = true
        }
    }
}

#if DEBUG
struct AppLockWrapper_Previews: PreviewProvider {
    static var previews: some View {
        AppLockWrapper {
            Text("App Content")
                .font(.largeTitle)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.blue.opacity(0.2))
        }
    }
}
#endif
