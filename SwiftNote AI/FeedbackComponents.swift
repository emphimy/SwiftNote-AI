// File: Components/Feedback/FeedbackComponents.swift

import SwiftUI
import Combine

// MARK: - Toast Message
struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let type: ToastType
    let duration: TimeInterval
    
    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool {
        lhs.id == rhs.id
    }
}

enum ToastType {
    case success
    case error
    case warning
    case info
    
    var backgroundColor: Color {
        switch self {
        case .success: return Theme.Colors.success
        case .error: return Theme.Colors.error
        case .warning: return Theme.Colors.warning
        case .info: return Theme.Colors.primary
        }
    }
    
    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
}

// MARK: - Toast View
struct ToastView: View {
    let message: ToastMessage
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: message.type.icon)
                .foregroundColor(.white)
            
            Text(message.message)
                .font(Theme.Typography.body)
                .foregroundColor(.white)
            
            Spacer()
            
            Button(action: {
                #if DEBUG
                print("🍞 Toast: Dismiss button tapped")
                #endif
                onDismiss()
            }) {
                Image(systemName: "xmark")
                    .foregroundColor(.white)
            }
        }
        .padding(Theme.Spacing.md)
        .background(message.type.backgroundColor)
        .cornerRadius(Theme.Layout.cornerRadius)
        .shadow(color: Color.black.opacity(0.2),
                radius: 8,
                x: 0,
                y: 4)
    }
}

// MARK: - Toast Manager
class ToastManager: ObservableObject {
    @Published private(set) var activeToasts: [ToastMessage] = []
    private var cancellables = Set<AnyCancellable>()
    
    func show(
        _ message: String,
        type: ToastType = .info,
        duration: TimeInterval = 3.0
    ) {
        #if DEBUG
        print("🍞 Toast: Showing message: \(message), type: \(type)")
        #endif
        
        let toast = ToastMessage(message: message,
                               type: type,
                               duration: duration)
        
        activeToasts.append(toast)
        
        // Automatically dismiss after duration
        Just(toast)
            .delay(for: .seconds(duration), scheduler: RunLoop.main)
            .sink { [weak self] toast in
                self?.dismiss(toast)
            }
            .store(in: &cancellables)
    }
    
    func dismiss(_ toast: ToastMessage) {
        #if DEBUG
        print("🍞 Toast: Dismissing message: \(toast.message)")
        #endif
        
        withAnimation {
            activeToasts.removeAll { $0.id == toast.id }
        }
    }
}

// MARK: - Toast Container
struct ToastContainer: ViewModifier {
    @StateObject private var toastManager = ToastManager()
    
    func body(content: Content) -> some View {
        content
            .overlay(
                ZStack {
                    ForEach(toastManager.activeToasts) { toast in
                        ToastView(message: toast) {
                            toastManager.dismiss(toast)
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                    }
                }
                .animation(.spring(), value: toastManager.activeToasts)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.lg)
                , alignment: .top
            )
            .environment(\.toastManager, toastManager)
    }
}

// MARK: - Environment Key for Toast Manager
private struct ToastManagerKey: EnvironmentKey {
    static var defaultValue: ToastManager = ToastManager()
}

extension EnvironmentValues {
    var toastManager: ToastManager {
        get { self[ToastManagerKey.self] }
        set { self[ToastManagerKey.self] = newValue }
    }
}

// MARK: - Loading Indicator
struct LoadingIndicator: View {
    let message: String?
    let style: LoadingStyle
    
    enum LoadingStyle: Equatable {
        case circular
        case linear(progress: Double)
        case indeterminate
        
        var animation: Animation {
            switch self {
            case .circular, .indeterminate:
                return .linear(duration: 1).repeatForever(autoreverses: false)
            case .linear:
                return .spring()
            }
        }
        static func == (lhs: LoadingStyle, rhs: LoadingStyle) -> Bool {
            switch (lhs, rhs) {
            case (.circular, .circular):
                return true
            case (.indeterminate, .indeterminate):
                return true
            case let (.linear(lProgress), .linear(rProgress)):
                return lProgress == rProgress
            default:
                return false
            }
        }
    }
    
    init(
        message: String? = nil,
        style: LoadingStyle = .circular
    ) {
        self.message = message
        self.style = style
        
        #if DEBUG
        print("⏳ Loading: Creating indicator with style: \(style)")
        #endif
    }
    
    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Group {
                switch style {
                case .circular:
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                case .linear(let progress):
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle())
                case .indeterminate:
                    IndeterminateProgressView()
                }
            }
            .animation(style.animation, value: style)
            
            if let message = message {
                Text(message)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(Theme.Spacing.md)
    }
}

// MARK: - Indeterminate Progress View
struct IndeterminateProgressView: View {
    @State private var isAnimating = false
    
    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Theme.Colors.primary)
                .frame(width: geometry.size.width * 0.3)
                .frame(maxWidth: .infinity, alignment: isAnimating ? .trailing : .leading)
        }
        .frame(height: 2)
        .onAppear {
            withAnimation(
                .linear(duration: 1)
                .repeatForever(autoreverses: true)
            ) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Error View
struct ErrorView: View {
    let error: Error
    let retryAction: (() -> Void)?
    
    init(
        error: Error,
        retryAction: (() -> Void)? = nil
    ) {
        self.error = error
        self.retryAction = retryAction
        
        #if DEBUG
        print("❌ Error: Creating error view for error: \(error.localizedDescription)")
        #endif
    }
    
    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(Theme.Colors.error)
            
            Text("Oops! Something went wrong")
                .font(Theme.Typography.h3)
            
            Text(error.localizedDescription)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.secondaryText)
                .multilineTextAlignment(.center)
            
            if let retryAction = retryAction {
                Button(action: {
                    #if DEBUG
                    print("❌ Error: Retry button tapped")
                    #endif
                    retryAction()
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Try Again")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, Theme.Spacing.md)
            }
        }
        .padding(Theme.Spacing.lg)
    }
}

// MARK: - Preview Provider
#if DEBUG
struct FeedbackComponents_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Toast Previews
            VStack(spacing: Theme.Spacing.md) {
                ToastView(message: ToastMessage(
                    message: "Success Message",
                    type: .success,
                    duration: 3.0
                )) {}
                
                ToastView(message: ToastMessage(
                    message: "Error Message",
                    type: .error,
                    duration: 3.0
                )) {}
                
                ToastView(message: ToastMessage(
                    message: "Warning Message",
                    type: .warning,
                    duration: 3.0
                )) {}
            }
            .padding()
            .previewDisplayName("Toast Messages")
            
            // Loading Indicators
            VStack(spacing: Theme.Spacing.lg) {
                LoadingIndicator(message: "Loading...")
                
                LoadingIndicator(
                    message: "Uploading...",
                    style: .linear(progress: 0.7)
                )
                
                LoadingIndicator(
                    message: "Processing...",
                    style: .indeterminate
                )
            }
            .padding()
            .previewDisplayName("Loading Indicators")
            
            // Error View
            ErrorView(
                error: NSError(
                    domain: "PreviewError",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "This is a preview error message"]
                )
            ) {
                print("Retry tapped")
            }
            .padding()
            .previewDisplayName("Error View")
        }
        .previewLayout(.sizeThatFits)
    }
}
#endif
