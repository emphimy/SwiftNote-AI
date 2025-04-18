import Foundation
import SwiftUI

// MARK: - Language Model
struct Language: Identifiable, Hashable, Equatable {
    let id = UUID()
    let name: String
    let code: String

    static let supportedLanguages: [Language] = [
        Language(name: "English", code: "en"),
        Language(name: "Spanish", code: "es"),
        Language(name: "French", code: "fr"),
        Language(name: "German", code: "de"),
        Language(name: "Italian", code: "it"),
        Language(name: "Portuguese", code: "pt"),
        Language(name: "Russian", code: "ru"),
        Language(name: "Japanese", code: "ja"),
        Language(name: "Chinese", code: "zh"),
        Language(name: "Korean", code: "ko"),
        Language(name: "Arabic", code: "ar"),
        Language(name: "Hindi", code: "hi"),
        Language(name: "Turkish", code: "tr"),
        Language(name: "Dutch", code: "nl"),
        Language(name: "Swedish", code: "sv"),
        Language(name: "Polish", code: "pl"),
        Language(name: "Vietnamese", code: "vi"),
        Language(name: "Thai", code: "th"),
        Language(name: "Indonesian", code: "id"),
        Language(name: "Greek", code: "el")
    ]

    static func getLanguageByCode(_ code: String) -> Language? {
        return supportedLanguages.first { $0.code == code }
    }

    static func getLanguageByName(_ name: String) -> Language? {
        return supportedLanguages.first { $0.name == name }
    }
}

// MARK: - Language Picker Component

struct LanguagePicker: View {
    @Binding var selectedLanguage: Language
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Language Header
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "globe")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.Colors.primary)

                Text("Note Language")
                    .font(Theme.Typography.body.weight(.medium))
                    .foregroundColor(Theme.Colors.text)
            }

            // Language Selector
            Menu {
                ForEach(Language.supportedLanguages) { language in
                    Button(action: {
                        selectedLanguage = language
                    }) {
                        HStack {
                            Text(language.name)
                                .font(Theme.Typography.body)

                            Spacer()

                            if language.code == selectedLanguage.code {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(Theme.Colors.primary)
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(selectedLanguage.name)
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.primary)

                        // Language code badge
                        Text(selectedLanguage.code.uppercased())
                            .font(Theme.Typography.small.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Theme.Colors.primary)
                            )
                    }

                    Spacer()

                    Image(systemName: "chevron.down.circle.fill")
                        .foregroundColor(Theme.Colors.primary)
                        .font(.system(size: 18))
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius)
                        .fill(Theme.Colors.primary.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius)
                        .stroke(Theme.Colors.primary.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}

#if DEBUG
struct LanguagePicker_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Light mode
            LanguagePicker(selectedLanguage: .constant(Language.supportedLanguages[0]))
                .padding()
                .previewLayout(.sizeThatFits)
                .previewDisplayName("Light Mode")

            // Dark mode
            LanguagePicker(selectedLanguage: .constant(Language.supportedLanguages[1]))
                .padding()
                .preferredColorScheme(.dark)
                .previewLayout(.sizeThatFits)
                .previewDisplayName("Dark Mode")

            // In context
            VStack(spacing: Theme.Spacing.md) {
                Text("Create YouTube Note")
                    .font(Theme.Typography.h2)
                    .padding(.bottom)

                TextField("Enter YouTube URL", text: .constant("https://youtube.com/watch?v=example"))
                    .padding()
                    .background(Theme.Colors.secondaryBackground)
                    .cornerRadius(Theme.Layout.cornerRadius)

                LanguagePicker(selectedLanguage: .constant(Language.supportedLanguages[0]))

                Button(action: {}) {
                    Text("Create Note")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.Colors.primary)
                        .foregroundColor(.white)
                        .cornerRadius(Theme.Layout.cornerRadius)
                }
            }
            .padding()
            .previewLayout(.sizeThatFits)
            .previewDisplayName("In Context")
        }
    }
}
#endif

// MARK: - Language Display Component
struct LanguageDisplay: View {
    let language: Language
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? Theme.Spacing.xxs : Theme.Spacing.xs) {
            // Globe icon
            Image(systemName: "globe")
                .font(.system(size: compact ? 12 : 14, weight: .semibold))
                .foregroundColor(Theme.Colors.primary)

            if !compact {
                // Language name
                Text(language.name)
                    .font(Theme.Typography.caption.weight(.medium))
                    .foregroundColor(Theme.Colors.text)
            }

            // Language code badge
            Text(language.code.uppercased())
                .font(Theme.Typography.small.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, compact ? 4 : 6)
                .padding(.vertical, compact ? 1 : 2)
                .background(
                    Capsule()
                        .fill(Theme.Colors.primary)
                )
        }
        .padding(.horizontal, compact ? Theme.Spacing.xs : Theme.Spacing.sm)
        .padding(.vertical, compact ? Theme.Spacing.xxs : Theme.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: compact ? 12 : Theme.Layout.cornerRadius)
                .fill(Theme.Colors.primary.opacity(0.1))
        )
    }
}

#if DEBUG
struct LanguageDisplay_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Standard display
            LanguageDisplay(language: Language.supportedLanguages[0])
                .padding()
                .previewLayout(.sizeThatFits)
                .previewDisplayName("Standard")

            // Compact display
            LanguageDisplay(language: Language.supportedLanguages[0], compact: true)
                .padding()
                .previewLayout(.sizeThatFits)
                .previewDisplayName("Compact")

            // Dark mode
            LanguageDisplay(language: Language.supportedLanguages[1])
                .padding()
                .preferredColorScheme(.dark)
                .previewLayout(.sizeThatFits)
                .previewDisplayName("Dark Mode")
        }
    }
}
#endif
