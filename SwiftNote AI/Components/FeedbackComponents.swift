import SwiftUI
import Combine

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
            
            if let action = message.action {
                Button(action: {
                    #if DEBUG
                    print("🍞 Toast: Action button tapped")
                    #endif
                    action.action()
                    onDismiss()
                }) {
                    Text(action.title)
                        .font(Theme.Typography.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, Theme.Spacing.xs)
                        .padding(.vertical, Theme.Spacing.xxs)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(Theme.Layout.cornerRadius / 2)
                }
            }
            
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

// MARK: - Toast Manager Constants
private enum ToastConstants {
    static let maxVisibleToasts = 3
    static let defaultDuration: TimeInterval = 3.0
}

// MARK: - Toast Manager
@MainActor
final class ToastManager: ObservableObject {
    @Published private(set) var activeToasts: [ToastMessage] = []
    private var cancellables = Set<AnyCancellable>()
    
    nonisolated private func calculateDismissDelay(_ duration: TimeInterval) -> UInt64 {
        UInt64(duration * 1_000_000_000)
    }
    
    private func processToastQueue() {
        #if DEBUG
        print("🍞 ToastManager: Processing toast queue with \(activeToasts.count) toasts")
        #endif
        
        if activeToasts.count > ToastConstants.maxVisibleToasts {
            let excessToasts = activeToasts.count - ToastConstants.maxVisibleToasts
            activeToasts.removeFirst(excessToasts)
            
            #if DEBUG
            print("🍞 ToastManager: Removed \(excessToasts) excess toasts")
            #endif
        }
    }
    
    func show(
        _ message: String,
        type: ToastType = .info,
        duration: TimeInterval = ToastConstants.defaultDuration,
        action: ToastAction? = nil
    ) {
        #if DEBUG
        print("🍞 ToastManager: Showing toast - Message: \(message), Type: \(type)")
        #endif
        
        let toast = ToastMessage(
            message: message,
            type: type,
            duration: duration,
            action: action
        )
        
        withAnimation(.spring()) {
            activeToasts.append(toast)
            processToastQueue()
        }
        
        // Auto dismiss after duration
        Task {
            try? await Task.sleep(nanoseconds: calculateDismissDelay(duration))
            await MainActor.run {
                withAnimation(.spring()) {
                    dismiss(toast)
                }
            }
        }
    }
    
    func dismiss(_ toast: ToastMessage) {
        #if DEBUG
        print("🍞 ToastManager: Dismissing message: \(toast.message)")
        #endif
        
        withAnimation {
            activeToasts.removeAll { $0.id == toast.id }
        }
    }
}

// MARK: - Enhanced Toast Models
struct ToastAction {
    let title: String
    let action: () -> Void
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let type: ToastType
    let duration: TimeInterval
    var action: ToastAction?
    
    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Toast Container
struct ToastContainer: ViewModifier {
    // Use StateObject for the main instance
    @StateObject private var toastManager: ToastManager = {
        let manager = ToastManager()
        #if DEBUG
        print("🍞 ToastContainer: Creating new ToastManager instance")
        #endif
        return manager
    }()
    
    func body(content: Content) -> some View {
        content
            .overlay(
                ZStack {
                    ForEach(toastManager.activeToasts) { toast in
                        ToastView(message: toast) {
                            Task { @MainActor in
                                #if DEBUG
                                print("🍞 ToastContainer: Dismissing toast via overlay")
                                #endif
                                toastManager.dismiss(toast)
                            }
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
            .transformEnvironment(\.toastManager) { environment in
                #if DEBUG
                print("🍞 ToastContainer: Injecting ToastManager into environment")
                #endif
                environment = toastManager
            }
    }
}

// MARK: - Environment Key for Toast Manager
private struct ToastManagerKey: EnvironmentKey {
    @MainActor static var defaultValue: ToastManager = {
        let manager = ToastManager()
        #if DEBUG
        print("🍞 ToastManagerKey: Creating default ToastManager")
        #endif
        return manager
    }()
}

extension EnvironmentValues {
    var toastManager: ToastManager {
        get {
            #if DEBUG
            print("🍞 EnvironmentValues: Accessing ToastManager")
            #endif
            return self[ToastManagerKey.self]
        }
        set {
            #if DEBUG
            print("🍞EnvironmentValues: Setting new ToastManager")
            #endif
            self[ToastManagerKey.self] = newValue
        }
    }
}

// MARK: - Loading Indicator
struct LoadingIndicator: View {
    let message: String?
    let style: LoadingStyle
    
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

// MARK: - Enhanced Loading States
enum LoadingState: Equatable {
    case idle
    case loading(message: String? = nil)
    case success(message: String)
    case error(message: String)
    
    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }
}

// MARK: - Enhanced Loading Indicator
struct EnhancedLoadingIndicator: View {
    let state: LoadingState
    let style: LoadingStyle
    let retryAction: (() -> Void)?
    
    init(
        state: LoadingState,
        style: LoadingStyle = .circular,
        retryAction: (() -> Void)? = nil
    ) {
        self.state = state
        self.style = style
        self.retryAction = retryAction
        
        #if DEBUG
        print("⏳ LoadingIndicator: Creating with state: \(String(describing: state))")
        #endif
    }
    
    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            switch state {
            case .idle:
                EmptyView()
                
            case .loading(let message):
                LoadingIndicator(message: message, style: style)
                
            case .success(let message):
                VStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.Colors.success)
                        .font(.system(size: 48))
                    
                    Text(message)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.success)
                }
                .transition(.scale.combined(with: .opacity))
                
            case .error(let message):
                VStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Theme.Colors.error)
                        .font(.system(size: 48))
                    
                    Text(message)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.error)
                        .multilineTextAlignment(.center)
                    
                    if let retryAction = retryAction {
                        Button(action: {
                            #if DEBUG
                            print("⏳ LoadingIndicator: Retry action triggered")
                            #endif
                            retryAction()
                        }) {
                            Label("Retry", systemImage: "arrow.clockwise")
                                .font(Theme.Typography.body)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.top, Theme.Spacing.sm)
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius)
                .fill(Theme.Colors.background)
                .standardShadow()
        )
        .animation(.spring(), value: state)
    }
}

// MARK: - Loading Container Modifier
struct LoadingContainerModifier: ViewModifier {
    let state: LoadingState
    let retryAction: (() -> Void)?
    
    func body(content: Content) -> some View {
        ZStack {
            content
                .disabled(state.isLoading)
                .opacity(state.isLoading ? 0.6 : 1.0)
            
            if state.isLoading {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                
                EnhancedLoadingIndicator(
                    state: state,
                    retryAction: retryAction
                )
            }
        }
        .animation(.easeInOut, value: state.isLoading)
    }
}

extension View {
    func loadingContainer(
        state: LoadingState,
        retryAction: (() -> Void)? = nil
    ) -> some View {
        modifier(LoadingContainerModifier(state: state, retryAction: retryAction))
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
