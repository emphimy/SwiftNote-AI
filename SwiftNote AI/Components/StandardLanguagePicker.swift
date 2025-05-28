import SwiftUI

// MARK: - Standard Language Picker Component
struct StandardLanguagePicker: View {
    @Binding var selectedLanguage: Language

    var body: some View {
        LanguagePicker(selectedLanguage: $selectedLanguage)
    }
}

// MARK: - Preview
#if DEBUG
struct StandardLanguagePicker_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            StandardLanguagePicker(selectedLanguage: .constant(Language.supportedLanguages[0]))
                .padding()
                .previewLayout(.sizeThatFits)
                .previewDisplayName("Light Mode")

            StandardLanguagePicker(selectedLanguage: .constant(Language.supportedLanguages[1]))
                .padding()
                .preferredColorScheme(.dark)
                .previewLayout(.sizeThatFits)
                .previewDisplayName("Dark Mode")
        }
    }
}
#endif
