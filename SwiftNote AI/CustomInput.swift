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
    let onCancel: (() -> Void)?
    
    @State private var isEditing = false
    
    init(
        text: Binding<String>,
        placeholder: String = "Search",
        onCancel: (() -> Void)? = nil
    ) {
        self._text = text
        self.placeholder = placeholder
        self.onCancel = onCancel
        
        #if DEBUG
        print("🔍 SearchBar: Creating search bar with placeholder: \(placeholder)")
        #endif
    }
    
    var body: some View {
        HStack {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Theme.Colors.secondaryText)
                
                TextField(placeholder, text: $text)
                    .onChange(of: text) { newValue in
                        #if DEBUG
                        print("🔍 SearchBar: Search text changed to: \(newValue)")
                        #endif
                    }
                
                if !text.isEmpty {
                    Button(action: {
                        #if DEBUG
                        print("🔍 SearchBar: Clear text button tapped")
                        #endif
                        text = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Theme.Colors.secondaryText)
                    }
                }
            }
            .padding(Theme.Spacing.sm)
            .background(Theme.Colors.secondaryBackground)
            .cornerRadius(Theme.Layout.cornerRadius)
            
            if isEditing {
                Button("Cancel") {
                    #if DEBUG
                    print("🔍 SearchBar: Cancel button tapped")
                    #endif
                    
                    withAnimation {
                        isEditing = false
                        text = ""
                        onCancel?()
                        
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                      to: nil, from: nil, for: nil)
                    }
                }
                .foregroundColor(Theme.Colors.primary)
                .transition(.move(edge: .trailing))
            }
        }
        .onTapGesture {
            withAnimation {
                isEditing = true
            }
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
            
            SearchBar(text: .constant(""))
            
            SearchBar(text: .constant("Search term"))
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif
