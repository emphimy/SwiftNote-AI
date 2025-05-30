import SwiftUI

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
                HStack {
                    configuration.sourceType.icon
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(configuration.sourceType.color)

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
                        Image(systemName: configuration.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(configuration.isFavorite ? Theme.Colors.warning : Theme.Colors.secondaryText)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                // Footer
                HStack {
                    Text(configuration.date, style: .date)
                        .font(Theme.Typography.small)
                        .foregroundColor(Theme.Colors.tertiaryText)

                    Spacer()
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
                HStack {
                    configuration.sourceType.icon
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(configuration.sourceType.color)

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
                        Image(systemName: configuration.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(configuration.isFavorite ? Theme.Colors.warning : Theme.Colors.secondaryText)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Spacer()

                // Date and actions
                HStack {
                    Text(configuration.date, style: .date)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.tertiaryText)

                    Spacer()
                }
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
                            Image(systemName: item.icon)
                                .font(.system(size: 32, weight: .medium))
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
