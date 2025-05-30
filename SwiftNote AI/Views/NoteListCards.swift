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

// MARK: - Note List Card
struct NoteListCard: View {
    let configuration: NoteCardConfiguration
    let actions: CardActions
    let onTap: () -> Void

    init(configuration: NoteCardConfiguration, actions: CardActions, onTap: @escaping () -> Void) {
        self.configuration = configuration
        self.actions = actions
        self.onTap = onTap
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                // Header
                HStack(alignment: .center, spacing: Theme.Spacing.md) {
                    // Icon with rounded square background
                    Group {
                        if configuration.sourceType.isCustomIcon {
                            configuration.sourceType.icon
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 23, height: 23)
                        } else {
                            configuration.sourceType.icon
                                .font(.system(size: 20, weight: .bold))
                        }
                    }
                    .foregroundColor(configuration.sourceType.color)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(configuration.sourceType.color.opacity(0.1))
                    )

                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        // Title and favorite on same line
                        HStack {
                            Text(configuration.title)
                                .font(Theme.Typography.caption.weight(.medium))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer()

                            Button(action: {
#if DEBUG
                                print("📝 NoteListCard: Favorite button tapped")
#endif
                                actions.onFavorite()
                            }) {
                                Image(systemName: configuration.isFavorite ? "heart.fill" : "heart")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(configuration.isFavorite ? .red : Theme.Colors.secondaryText)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                        // Date positioned under title
                        Text(configuration.date, style: .date)
                            .font(Theme.Typography.small)
                            .foregroundColor(Theme.Colors.adaptiveColor(
                                light: Color(red: 0.4, green: 0.2, blue: 0.1), // Dark brown for light mode
                                dark: Color(red: 0.8, green: 0.6, blue: 0.4)   // Light brown for dark mode
                            ))
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.cardBackground)
            .cornerRadius(Theme.Layout.cornerRadius)
        }
        .buttonStyle(PlainButtonStyle())
        .onDrag {
#if DEBUG
            print("📁 NoteListCard: Starting drag operation")
#endif
            return NSItemProvider(object: configuration.id.uuidString as NSString)
        } preview: {
            NoteListCard(configuration: configuration, actions: actions, onTap: {})
                .frame(width: 200)
        }
    }
}

// MARK: - Note Grid Card
struct NoteGridCard: View {
    let configuration: NoteCardConfiguration
    let actions: CardActions
    let onTap: () -> Void

    init(configuration: NoteCardConfiguration, actions: CardActions, onTap: @escaping () -> Void) {
        self.configuration = configuration
        self.actions = actions
        self.onTap = onTap
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                // Header with source icon and favorite
                HStack(alignment: .center, spacing: Theme.Spacing.md) {
                    // Icon with rounded square background
                    Group {
                        if configuration.sourceType.isCustomIcon {
                            configuration.sourceType.icon
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 23, height: 23)
                        } else {
                            configuration.sourceType.icon
                                .font(.system(size: 20, weight: .bold))
                        }
                    }
                    .foregroundColor(configuration.sourceType.color)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(configuration.sourceType.color.opacity(0.1))
                    )

                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        // Title and favorite on same line
                        HStack {
                            Text(configuration.title)
                                .font(Theme.Typography.caption.weight(.medium))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer()

                            Button(action: {
#if DEBUG
                                print("📝 NoteGridCard: Favorite button tapped")
#endif
                                actions.onFavorite()
                            }) {
                                Image(systemName: configuration.isFavorite ? "heart.fill" : "heart")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(configuration.isFavorite ? .red : Theme.Colors.secondaryText)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                        // Date positioned under title
                        Text(configuration.date, style: .date)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.adaptiveColor(
                                light: Color(red: 0.4, green: 0.2, blue: 0.1), // Dark brown for light mode
                                dark: Color(red: 0.8, green: 0.6, blue: 0.4)   // Light brown for dark mode
                            ))
                    }
                }

                Spacer()
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.cardBackground)
            .frame(width: 160, height: 180)
            .cornerRadius(Theme.Layout.cornerRadius)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Action Card
struct ActionCard: View {
    let items: [ActionCardItem]

    // MARK: - Constants
    private let buttonWidth: CGFloat = 160
    private let buttonHeight: CGFloat = 100
    private let columns: [GridItem] = [
        GridItem(.fixed(160), spacing: Theme.Spacing.xl),
        GridItem(.fixed(160), spacing: Theme.Spacing.xl)
    ]

    init(items: [ActionCardItem]) {
        self.items = items

#if DEBUG
        print("📝 ActionCard: Creating card with \(items.count) items")
        items.forEach { print($0.debugDescription) }
#endif
    }

    // MARK: - Body
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Theme.Spacing.lg) {
                ForEach(items) { item in
                    Button(action: {
#if DEBUG
                        print("📝 ActionCard: Item tapped: \(item.title)")
#endif
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            item.action()
                        }
                    }) {
                        VStack(spacing: Theme.Spacing.sm) {
                            // Handle both system symbols and custom assets
                            Group {
                                if isSystemSymbol(item.icon) {
                                    // System symbol
                                    Image(systemName: item.icon)
                                        .font(.system(size: 32, weight: .medium))
                                } else {
                                    // Custom asset
                                    Image(item.icon)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 32, height: 32)
                                }
                            }
                            .foregroundColor(item.color)
                            .frame(height: 40)
                            .accessibility(label: Text(item.title))

                            Text(item.title)
                                .font(Theme.Typography.body.weight(.medium))
                                .foregroundColor(Theme.Colors.text)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .frame(height: 15)
                        }
                        .frame(width: buttonWidth, height: buttonHeight)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius)
                                .fill(Theme.Colors.secondaryBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius)
                                        .stroke(item.color.opacity(0.1), lineWidth: 1)
                                )
                        )
                        .shadow(color: Theme.Colors.primary.opacity(0.05), radius: 15, x: 0, y: 5)
                        .shadow(color: Theme.Colors.primary.opacity(0.05), radius: 3, x: 0, y: 2)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(Theme.Spacing.md)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: items.count)
        }
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Tag View Component
struct TagView: View {
    let tag: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(tag)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.primary)
                .padding(.horizontal, Theme.Spacing.xs)
                .padding(.vertical, Theme.Spacing.xxs)
                .background(Theme.Colors.primary.opacity(0.1))
                .cornerRadius(Theme.Layout.cornerRadius / 2)
        }
    }
}

// MARK: - Preview Provider
#if DEBUG
struct NoteCards_Previews: PreviewProvider {
    static var previewConfiguration: NoteCardConfiguration {
        NoteCardConfiguration(
            title: "Meeting Notes",
            date: Date(),
            preview: "Discussed the new project timeline and key deliverables...",
            sourceType: .audio,
            isFavorite: true
        )
    }

    static var previewActions: CardActions {
        struct PreviewCardActions: CardActions {
            func onFavorite() { print("Favorite tapped") }
            func onShare() { print("Share tapped") }
            func onDelete() { print("Delete tapped") }
            func onTagSelected(_ tag: String) { print("Tag tapped: \(tag)") }
        }
        return PreviewCardActions()
    }

    static var previews: some View {
        Group {
            NoteListCard(
                configuration: previewConfiguration,
                actions: previewActions,
                onTap: { print("Card tapped") }
            )
            .padding()
            .previewDisplayName("List Card")

            NoteGridCard(
                configuration: previewConfiguration,
                actions: previewActions,
                onTap: { print("Card tapped") }
            )
            .padding()
            .previewDisplayName("Grid Card")

            ActionCard(items: [
                ActionCardItem(title: "Record Audio", icon: "mic", color: .blue) {},
                ActionCardItem(title: "Scan Text", icon: "doc", color: .green) {},
                ActionCardItem(title: "Upload File", icon: "arrow.up.circle.fill", color: .orange) {},
                ActionCardItem(title: "YouTube Video", icon: "play.circle.fill", color: .red) {}
            ])
            .padding()
            .previewDisplayName("Action Card")
        }
        .previewLayout(.sizeThatFits)
    }
}
#endif
