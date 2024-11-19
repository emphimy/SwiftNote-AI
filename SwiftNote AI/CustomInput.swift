import SwiftUI
import Combine

// MARK: - Input State
enum InputState {
    case normal
    case active
    case error
    case disabled
    
    var borderColor: Color {
        switch self {
        case .normal: return Theme.Colors.tertiaryBackground
        case .active: return Theme.Colors.primary
        case .error: return Theme.Colors.error
        case .disabled: return Theme.Colors.tertiaryBackground
        }
    }
}

// MARK: - Custom Text Field
struct CustomTextField: View {
    let placeholder: String
    @Binding var text: String
    let keyboardType: UIKeyboardType
    let textContentType: UITextContentType?
    let errorMessage: String?
    let isSecure: Bool
    let isEnabled: Bool
    
    @State private var isEditing: Bool = false
    
    init(
        placeholder: String,
        text: Binding<String>,
        keyboardType: UIKeyboardType = .default,
        textContentType: UITextContentType? = nil,
        errorMessage: String? = nil,
        isSecure: Bool = false,
        isEnabled: Bool = true
    ) {
        self.placeholder = placeholder
        self._text = text
        self.keyboardType = keyboardType
        self.textContentType = textContentType
        self.errorMessage = errorMessage
        self.isSecure = isSecure
        self.isEnabled = isEnabled
        
        #if DEBUG
        print("📝 TextField: Creating text field with placeholder: \(placeholder), enabled: \(isEnabled)")
        #endif
    }
    
    private var inputState: InputState {
        if !isEnabled {
            return .disabled
        }
        if errorMessage != nil {
            return .error
        }
        return isEditing ? .active : .normal
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                        .textContentType(textContentType)
                } else {
                    TextField(placeholder, text: $text)
                        .textContentType(textContentType)
                }
            }
            .keyboardType(keyboardType)
            .disabled(!isEnabled)
            .padding(Theme.Spacing.sm)
            .background(Theme.Colors.background)
            .cornerRadius(Theme.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius)
                    .stroke(inputState.borderColor, lineWidth: 1)
            )
            .onTapGesture {
                withAnimation(Theme.Animation.quick) {
                    isEditing = true
                }
            }
            
            if let error = errorMessage {
                Text(error)
                    .font(Theme.Typography.small)
                    .foregroundColor(Theme.Colors.error)
            }
        }
        .onChange(of: text) { newValue in
            #if DEBUG
            print("📝 TextField: Text changed to: \(newValue)")
            #endif
        }
        .onChange(of: isEditing) { isEditing in
            #if DEBUG
            print("📝 TextField: Editing state changed to: \(isEditing)")
            #endif
        }
    }
}

// MARK: - Search Bar
struct SearchBar: View {
    @Binding var text: String
    let placeholder: String
    @State private var isEditing = false
    
    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Theme.Colors.secondaryText)
                    .font(Theme.Typography.caption)
                
                TextField(placeholder, text: $text)
                    .font(Theme.Typography.body)
                
                if !text.isEmpty {
                    Button(action: {
                        text = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Theme.Colors.secondaryText)
                            .font(Theme.Typography.caption)
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: 280)
            .background(Theme.Colors.secondaryBackground)
            .cornerRadius(Theme.Layout.cornerRadius)
            
            if isEditing {
                Button(action: {
                    withAnimation {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                      to: nil, from: nil, for: nil)
                        isEditing = false
                    }
                }) {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .foregroundColor(Theme.Colors.primary)
                        .font(.system(size: 22))
                }
            }
        }
        .onTapGesture {
            isEditing = true
        }
    }
}

// MARK: - Preview Provider
#if DEBUG
struct CustomInput_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: Theme.Spacing.lg) {
            CustomTextField(
                placeholder: "Username",
                text: .constant(""),
                errorMessage: nil
            )
            
            CustomTextField(
                placeholder: "Password",
                text: .constant(""),
                textContentType: .password,
                errorMessage: "Invalid password",
                isSecure: true
            )
            
            CustomTextField(
                placeholder: "Disabled Input",
                text: .constant(""),
                isEnabled: false
            )
            
            SearchBar(
                text: .constant(""),
                placeholder: "Search" // Add this missing parameter
            )
            
            SearchBar(
                text: .constant("Search term"),
                placeholder: "Search" // Add this missing parameter
            )
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif
