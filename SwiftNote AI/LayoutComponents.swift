// File: Components/Layout/LayoutComponents.swift

import SwiftUI

// MARK: - Custom Navigation Bar
struct CustomNavigationBar: View {
    let title: String
    let leftItems: [NavBarItem]
    let rightItems: [NavBarItem]
    @Environment(\.dismiss) private var dismiss
    
    init(
        title: String,
        leftItems: [NavBarItem] = [],
        rightItems: [NavBarItem] = []
    ) {
        self.title = title
        self.leftItems = leftItems
        self.rightItems = rightItems
        
        #if DEBUG
        print("🧭 NavBar: Creating navigation bar with title: \(title)")
        #endif
    }
    
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Left Items
            HStack(spacing: Theme.Spacing.sm) {
                if leftItems.isEmpty {
                    Button(action: {
                        #if DEBUG
                        print("🧭 NavBar: Back button tapped")
                        #endif
                        dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(Theme.Colors.primary)
                    }
                } else {
                    ForEach(leftItems) { item in
                        NavBarButton(item: item)
                    }
                }
            }
            
            Spacer()
            
            // Title
            Text(title)
                .font(Theme.Typography.h3)
                .lineLimit(1)
            
            Spacer()
            
            // Right Items
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(rightItems) { item in
                    NavBarButton(item: item)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: 44)
        .background(Theme.Colors.background)
    }
}

// MARK: - Navigation Bar Item
struct NavBarItem: Identifiable {
    let id = UUID()
    let icon: String
    let action: () -> Void
    
    static func == (lhs: NavBarItem, rhs: NavBarItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Navigation Bar Button
struct NavBarButton: View {
    let item: NavBarItem
    
    var body: some View {
        Button(action: {
            #if DEBUG
            print("🧭 NavBar: Button tapped with icon: \(item.icon)")
            #endif
            item.action()
        }) {
            Image(systemName: item.icon)
                .foregroundColor(Theme.Colors.primary)
                .frame(width: 32, height: 32)
        }
    }
}

// MARK: - Section Header
struct SectionHeader: View {
    let title: String
    let subtitle: String?
    let trailing: (() -> AnyView)?
    
    init(
        title: String,
        subtitle: String? = nil,
        trailing: (() -> AnyView)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        
        #if DEBUG
        print("📑 SectionHeader: Creating header with title: \(title)")
        #endif
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            HStack {
                Text(title)
                    .font(Theme.Typography.h3)
                
                Spacer()
                
                if let trailing = trailing {
                    trailing()
                }
            }
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
    }
}

// MARK: - List Grid Container
struct ListGridContainer<Content: View>: View {
    enum ViewMode {
        case list
        case grid
    }
    
    @Binding var viewMode: ViewMode
    let content: Content
    
    init(
        viewMode: Binding<ViewMode>,
        @ViewBuilder content: () -> Content
    ) {
        self._viewMode = viewMode
        self.content = content()
        
        #if DEBUG
        print("📱 Container: Creating container with mode: \(viewMode.wrappedValue)")
        #endif
    }
    
    var body: some View {
        Group {
            switch viewMode {
            case .list:
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.sm) {
                        content
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                }
            case .grid:
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: Theme.Spacing.sm),
                            GridItem(.flexible(), spacing: Theme.Spacing.sm)
                        ],
                        spacing: Theme.Spacing.sm
                    ) {
                        content
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                }
            }
        }
        .onChange(of: viewMode) { newMode in
            #if DEBUG
            print("📱 Container: View mode changed to: \(newMode)")
            #endif
        }
    }
}

// MARK: - Custom Divider
struct CustomDivider: View {
    let title: String?
    let color: Color
    let thickness: CGFloat
    
    init(
        title: String? = nil,
        color: Color = Theme.Colors.tertiaryBackground,
        thickness: CGFloat = 1
    ) {
        self.title = title
        self.color = color
        self.thickness = thickness
        
        #if DEBUG
        print("〰️ Divider: Creating divider with title: \(title ?? "none")")
        #endif
    }
    
    var body: some View {
        if let title = title {
            HStack {
                line
                
                Text(title)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
                    .lineLimit(1)
                
                line
            }
            .padding(.horizontal, Theme.Spacing.md)
        } else {
            line
                .padding(.horizontal, Theme.Spacing.md)
        }
    }
    
    private var line: some View {
        Rectangle()
            .fill(color)
            .frame(height: thickness)
    }
}

// MARK: - Safe Area Wrapper
struct SafeAreaWrapper<Content: View>: View {
    let horizontalPadding: CGFloat?
    let verticalPadding: CGFloat?
    let content: Content
    
    init(
        horizontalPadding: CGFloat? = nil,
        verticalPadding: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.content = content()
        
        #if DEBUG
        print("📏 SafeArea: Creating wrapper with horizontal padding: \(String(describing: horizontalPadding)), vertical padding: \(String(describing: verticalPadding))")
        #endif
    }
    
    var body: some View {
        GeometryReader { geometry in
            content
                .padding(.horizontal, horizontalPadding ?? Theme.Layout.dynamicHorizontalPadding(for: geometry.size))
                .padding(.vertical, verticalPadding ?? Theme.Spacing.md)
                .frame(minHeight: geometry.size.height)
        }
    }
}

// MARK: - Empty State View
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let action: (() -> Void)?
    let actionTitle: String?
    
    init(
        icon: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
        
        #if DEBUG
        print("🗑️ EmptyState: Creating view with title: \(title)")
        #endif
    }
    
    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(Theme.Colors.secondaryText)
            
            VStack(spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Typography.h3)
                
                Text(message)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            
            if let action = action, let actionTitle = actionTitle {
                Button(action: {
                    #if DEBUG
                    print("🗑️ EmptyState: Action button tapped")
                    #endif
                    action()
                }) {
                    Text(actionTitle)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(Theme.Spacing.xl)
    }
}

// MARK: - Preview Provider
#if DEBUG
struct LayoutComponents_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Navigation Bar Preview
            CustomNavigationBar(
                title: "Example Title",
                rightItems: [
                    NavBarItem(icon: "gear") { print("Settings tapped") },
                    NavBarItem(icon: "square.and.arrow.up") { print("Share tapped") }
                ]
            )
            .previewDisplayName("Navigation Bar")
            
            // Section Header Preview
            SectionHeader(
                title: "Section Title",
                subtitle: "Optional subtitle text",
                trailing: { AnyView(Button("See All") { print("See all tapped") }) }
            )
            .previewDisplayName("Section Header")
            
            // Divider Preview
            VStack {
                CustomDivider()
                CustomDivider(title: "Or continue with")
            }
            .previewDisplayName("Dividers")
            
            // Empty State Preview
            EmptyStateView(
                icon: "doc.text",
                title: "No Notes Yet",
                message: "Start by creating your first note",
                actionTitle: "Create Note"
            ) {
                print("Create note tapped")
            }
            .previewDisplayName("Empty State")
        }
        .previewLayout(.sizeThatFits)
    }
}
#endif
