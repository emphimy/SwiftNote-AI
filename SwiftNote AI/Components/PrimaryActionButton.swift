import SwiftUI

// MARK: - Helper Functions
private func isSystemSymbol(_ iconName: String) -> Bool {
    // Known custom assets
    let customAssets = ["PdfIcon"]

    // If it's in our custom assets list, it's not a system symbol
    if customAssets.contains(iconName) {
        return false
    }

    // Otherwise, assume it's a system symbol
    return true
}

// MARK: - Primary Action Button Component
struct PrimaryActionButton: View {
    let title: String
    let icon: String?
    let isEnabled: Bool
    let isLoading: Bool
    let action: () -> Void

    init(
        title: String,
        icon: String? = nil,
        isEnabled: Bool = true,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isEnabled = isEnabled
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else if let icon = icon {
                    // Handle both system symbols and custom assets
                    Group {
                        if isSystemSymbol(icon) {
                            // System symbol
                            Image(systemName: icon)
                                .font(.system(size: 16, weight: .medium))
                        } else {
                            // Custom asset
                            Image(icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 16, height: 16)
                        }
                    }
                }

                Text(title)
                    .font(Theme.Typography.button)
                    .fontWeight(.medium)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .fill(
                        isEnabled && !isLoading
                            ? Theme.Colors.primary
                            : Theme.Colors.primary.opacity(0.6)
                    )
            )
        }
        .disabled(!isEnabled || isLoading)
    }
}

// MARK: - Preview
#if DEBUG
struct PrimaryActionButton_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            VStack(spacing: 16) {
                PrimaryActionButton(
                    title: "Start Recording",
                    icon: "mic.fill",
                    action: {}
                )

                PrimaryActionButton(
                    title: "Processing...",
                    isLoading: true,
                    action: {}
                )

                PrimaryActionButton(
                    title: "Disabled Button",
                    isEnabled: false,
                    action: {}
                )

                PrimaryActionButton(
                    title: "Import File",
                    icon: "doc.fill",
                    action: {}
                )
            }
            .padding()
            .previewLayout(.sizeThatFits)
            .previewDisplayName("Light Mode")

            VStack(spacing: 16) {
                PrimaryActionButton(
                    title: "Generate Note",
                    icon: "wand.and.stars",
                    action: {}
                )

                PrimaryActionButton(
                    title: "Loading...",
                    isLoading: true,
                    action: {}
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
