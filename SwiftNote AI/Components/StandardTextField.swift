import SwiftUI

// MARK: - Standard Text Field Component
struct StandardTextField: View {
    let placeholder: String
    @Binding var text: String
    let icon: String?
    let keyboardType: UIKeyboardType
    let submitLabel: SubmitLabel
    let onSubmit: (() -> Void)?

    @FocusState private var isFocused: Bool

    init(
        placeholder: String,
        text: Binding<String>,
        icon: String? = nil,
        keyboardType: UIKeyboardType = .default,
        submitLabel: SubmitLabel = .done,
        onSubmit: (() -> Void)? = nil
    ) {
        self.placeholder = placeholder
        self._text = text
        self.icon = icon
        self.keyboardType = keyboardType
        self.submitLabel = submitLabel
        self.onSubmit = onSubmit
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let icon = icon {
                Image(systemName: icon)
                    .foregroundColor(isFocused ? Theme.Colors.primary : Theme.Colors.secondaryText)
                    .font(.system(size: 16))
                    .frame(width: 20)
            }

            TextField(placeholder, text: $text)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.text)
                .keyboardType(keyboardType)
                .submitLabel(submitLabel)
                .focused($isFocused)
                .onSubmit {
                    onSubmit?()
                }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .foregroundColor(Theme.Colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .stroke(
                    isFocused ? Theme.Colors.primary : Theme.Colors.tertiaryBackground,
                    lineWidth: isFocused ? 2 : 1
                )
        )
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

// MARK: - Preview
#if DEBUG
struct StandardTextField_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            VStack(spacing: 16) {
                StandardTextField(
                    placeholder: "Enter YouTube URL",
                    text: .constant(""),
                    icon: "link"
                )

                StandardTextField(
                    placeholder: "Enter web link",
                    text: .constant("https://example.com"),
                    icon: "globe"
                )

                StandardTextField(
                    placeholder: "Search...",
                    text: .constant(""),
                    icon: "magnifyingglass"
                )
            }
            .padding()
            .previewLayout(.sizeThatFits)
            .previewDisplayName("Light Mode")

            VStack(spacing: 16) {
                StandardTextField(
                    placeholder: "Enter URL",
                    text: .constant(""),
                    icon: "link"
                )

                StandardTextField(
                    placeholder: "Type here...",
                    text: .constant("Sample text"),
                    icon: "pencil"
                )
            }
            .padding()
            .preferredColorScheme(.dark)
            .previewLayout(.sizeThatFits)
            .previewDisplayName("Dark Mode")
        }
    }
}
#endif
