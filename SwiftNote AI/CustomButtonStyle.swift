import SwiftUI

// MARK: - Button Styles Protocol
protocol CustomButtonStyle {
    var isEnabled: Bool { get }
    var isLoading: Bool { get }
}

// MARK: - Primary Button Style
struct PrimaryButtonStyle: ButtonStyle {
    let configuration: CustomButtonStyle
    
    init(isEnabled: Bool = true, isLoading: Bool = false) {
        self.configuration = DefaultButtonConfiguration(isEnabled: isEnabled, isLoading: isLoading)
    }
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            if self.configuration.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .padding(.trailing, Theme.Spacing.xxs)
            }
            
            configuration.label
        }
        .frame(maxWidth: .infinity)
        .frame(height: Theme.Layout.buttonHeight)
        .background(self.configuration.isEnabled ? Theme.Colors.primary : Theme.Colors.primary.opacity(0.5))
        .foregroundColor(Theme.Colors.background)
        .cornerRadius(Theme.Layout.cornerRadius)
        .opacity(configuration.isPressed ? 0.8 : 1.0)
        .animation(Theme.Animation.quick, value: configuration.isPressed)
        .onChange(of: configuration.isPressed) { isPressed in
            #if DEBUG
            print("🔘 Button: Primary button pressed state changed to \(isPressed)")
            #endif
        }
    }
}

// MARK: - Secondary Button Style
struct SecondaryButtonStyle: ButtonStyle {
    let configuration: CustomButtonStyle
    
    init(isEnabled: Bool = true, isLoading: Bool = false) {
        self.configuration = DefaultButtonConfiguration(isEnabled: isEnabled, isLoading: isLoading)
    }
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            if self.configuration.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Theme.Colors.primary))
                    .padding(.trailing, Theme.Spacing.xxs)
            }
            
            configuration.label
        }
        .frame(maxWidth: .infinity)
        .frame(height: Theme.Layout.buttonHeight)
        .background(Theme.Colors.background)
        .foregroundColor(Theme.Colors.primary)
        .cornerRadius(Theme.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius)
                .stroke(Theme.Colors.primary, lineWidth: 1)
        )
        .opacity(configuration.isPressed ? 0.8 : 1.0)
        .animation(Theme.Animation.quick, value: configuration.isPressed)
        .onChange(of: configuration.isPressed) { isPressed in
            #if DEBUG
            print("🔘 Button: Secondary button pressed state changed to \(isPressed)")
            #endif
        }
    }
}

// MARK: - Icon Button Style
struct IconButtonStyle: ButtonStyle {
    let configuration: CustomButtonStyle
    let size: CGFloat
    
    init(size: CGFloat = Theme.Layout.iconSize, isEnabled: Bool = true, isLoading: Bool = false) {
        self.size = size
        self.configuration = DefaultButtonConfiguration(isEnabled: isEnabled, isLoading: isLoading)
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: size, height: size)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(Theme.Animation.quick, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { isPressed in
                #if DEBUG
                print("🔘 Button: Icon button pressed state changed to \(isPressed)")
                #endif
            }
    }
}

// MARK: - Default Button Configuration
private struct DefaultButtonConfiguration: CustomButtonStyle {
    let isEnabled: Bool
    let isLoading: Bool
}

// MARK: - Custom Button Views
struct CustomButton: View {
    let title: String
    let action: () -> Void
    let style: ButtonStyleConfiguration
    let isEnabled: Bool
    let isLoading: Bool
    
    init(
        title: String,
        style: ButtonStyleConfiguration = .primary,
        isEnabled: Bool = true,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.style = style
        self.isEnabled = isEnabled
        self.isLoading = isLoading
        self.action = action
        
        #if DEBUG
        print("🔘 Button: Creating button with title: \(title), style: \(style), enabled: \(isEnabled), loading: \(isLoading)")
        #endif
    }
    
    var body: some View {
        Button(action: {
            #if DEBUG
            print("🔘 Button: '\(title)' tapped")
            #endif
            action()
        }) {
            Text(title)
                .font(Theme.Typography.body)
        }
        .buttonStyle(style.buttonStyle(isEnabled: isEnabled, isLoading: isLoading))
        .disabled(!isEnabled || isLoading)
    }
}

struct AnyButtonStyle: ButtonStyle {
    private let _makeBody: (Configuration) -> AnyView
    
    init<S: ButtonStyle>(_ style: S) {
        self._makeBody = { configuration in
            AnyView(style.makeBody(configuration: configuration))
        }
    }
    
    func makeBody(configuration: Configuration) -> some View {
        _makeBody(configuration)
    }
}

// MARK: - Button Style Configuration
enum ButtonStyleConfiguration {
    case primary
    case secondary
    case icon(size: CGFloat = Theme.Layout.iconSize)
    
    func buttonStyle(isEnabled: Bool, isLoading: Bool) -> AnyButtonStyle {
        switch self {
        case .primary:
            return AnyButtonStyle(PrimaryButtonStyle(isEnabled: isEnabled, isLoading: isLoading))
        case .secondary:
            return AnyButtonStyle(SecondaryButtonStyle(isEnabled: isEnabled, isLoading: isLoading))
        case .icon(let size):
            return AnyButtonStyle(IconButtonStyle(size: size, isEnabled: isEnabled, isLoading: isLoading))
        }
    }
}

// MARK: - Preview Provider
#if DEBUG
struct CustomButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: Theme.Spacing.md) {
            CustomButton(title: "Primary Button", style: .primary) {
                print("Primary tapped")
            }
            
            CustomButton(title: "Secondary Button", style: .secondary) {
                print("Secondary tapped")
            }
            
            CustomButton(title: "Disabled Button", style: .primary, isEnabled: false) {
                print("Disabled tapped")
            }
            
            CustomButton(title: "Loading Button", style: .primary, isLoading: true) {
                print("Loading tapped")
            }
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif
