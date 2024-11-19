import SwiftUI

// MARK: - Theme
enum Theme {
    // MARK: - Colors
    enum Colors {
        // Primary
        static let primary = Color("PrimaryColor", bundle: .main)
        static let secondary = Color("SecondaryColor", bundle: .main)
        static let accent = Color("Accent", bundle: .main)
        
        // Background
        static let background = Color("Background", bundle: .main)
        static let secondaryBackground = Color("SecondaryBackground", bundle: .main)
        static let tertiaryBackground = Color("TertiaryBackground", bundle: .main)
        
        // Text
        static let text = Color("Text", bundle: .main)
        static let secondaryText = Color("SecondaryText", bundle: .main)
        static let tertiaryText = Color("TertiaryText", bundle: .main)
        
        // Status
        static let success = Color("Success", bundle: .main)
        static let error = Color("Error", bundle: .main)
        static let warning = Color("Warning", bundle: .main)
        
        // MARK: - Color Scheme Specific
        static func adaptiveColor(light: Color, dark: Color) -> Color {
            Color(UIColor { traitCollection in
                switch traitCollection.userInterfaceStyle {
                case .light:
                    return UIColor(light)
                case .dark:
                    return UIColor(dark)
                case .unspecified:
                    #if DEBUG
                    print("🎨 Theme: Unspecified UI style detected, defaulting to light mode")
                    #endif
                    return UIColor(light)
                @unknown default:
                    #if DEBUG
                    print("🎨 Theme: Unknown UI style detected, defaulting to light mode")
                    #endif
                    return UIColor(light)
                }
            })
        }
    }
    
    // MARK: - Typography
    enum Typography {
        // Base font sizes
        static let h1: Font = .system(size: 32, weight: .bold)
        static let h2: Font = .system(size: 24, weight: .bold)
        static let h3: Font = .system(size: 20, weight: .semibold)
        static let body: Font = .system(size: 16, weight: .regular)
        static let caption: Font = .system(size: 14, weight: .regular)
        static let small: Font = .system(size: 12, weight: .regular)
        
        // Line heights
        static let bodyLineHeight: CGFloat = 1.5
        static let headingLineHeight: CGFloat = 1.3
    }
    
    // MARK: - Spacing
    enum Spacing {
        static let xxxs: CGFloat = 2
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        static let xxxl: CGFloat = 64
    }
    
    // MARK: - Layout
    enum Layout {
        static let cornerRadius: CGFloat = 12
        static let buttonHeight: CGFloat = 44
        static let iconSize: CGFloat = 24
        static let maxWidth: CGFloat = 414 // iPhone 12 Pro Max width
        
        // MARK: - Safe Area and Dynamic Margins
        static func dynamicHorizontalPadding(for size: CGSize) -> CGFloat {
            let baseWidth = size.width
            switch baseWidth {
            case 0..<375: return Spacing.md    // iPhone SE, mini
            case 375..<428: return Spacing.lg  // iPhone regular, max
            default: return Spacing.xl         // iPad and larger
            }
        }
    }
    
    // MARK: - Animation
    enum Animation {
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.3)
        static let quick = SwiftUI.Animation.easeInOut(duration: 0.15)
        static let slow = SwiftUI.Animation.easeInOut(duration: 0.45)
    }
    
    // MARK: - Shadows
    enum Shadows {
        static let small = Shadow(color: .black.opacity(0.1),
                                radius: 4,
                                x: 0,
                                y: 2)
        
        static let medium = Shadow(color: .black.opacity(0.15),
                                 radius: 8,
                                 x: 0,
                                 y: 4)
        
        static let large = Shadow(color: .black.opacity(0.2),
                                radius: 16,
                                x: 0,
                                y: 8)
    }
    // MARK: - Settings
    enum Settings {
        static let iconSize: CGFloat = 32
        static let cardPadding: CGFloat = 16
        static let cornerRadius: CGFloat = 12
        static let animationDuration: Double = 0.3
        
        static let sections: [SettingsSection] = [
            .init(
                id: "account",
                title: "Account & Security",
                icon: "person.circle.fill",
                color: Colors.primary
            ),
            .init(
                id: "appearance",
                title: "Appearance",
                icon: "paintbrush.fill",
                color: Colors.accent
            ),
            .init(
                id: "notifications",
                title: "Notifications",
                icon: "bell.fill",
                color: Colors.warning
            ),
            .init(
                id: "storage",
                title: "Storage & Data",
                icon: "internaldrive.fill",
                color: Colors.secondary
            ),
            .init(
                id: "privacy",
                title: "Privacy & Security",
                icon: "lock.fill",
                color: Colors.error
            ),
            .init(
                id: "support",
                title: "Help & Support",
                icon: "questionmark.circle.fill",
                color: Colors.success
            )
        ]
    }
}

// MARK: - Shadow Model
struct Shadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// MARK: - View Extensions
extension View {
    func standardShadow() -> some View {
        self.shadow(color: Theme.Shadows.small.color,
                   radius: Theme.Shadows.small.radius,
                   x: Theme.Shadows.small.x,
                   y: Theme.Shadows.small.y)
    }
    
    func mediumShadow() -> some View {
        self.shadow(color: Theme.Shadows.medium.color,
                   radius: Theme.Shadows.medium.radius,
                   x: Theme.Shadows.medium.x,
                   y: Theme.Shadows.medium.y)
    }
}

// MARK: - Debug Logging
#if DEBUG
struct ThemeLogger {
    static func logColorSchemeChange(_ scheme: ColorScheme) {
        print("🎨 Theme: Color scheme changed to \(scheme == .dark ? "dark" : "light")")
    }
    
    static func logDynamicTypeChange(_ size: CGFloat) {
        print("📏 Theme: Dynamic type size changed to \(size)")
    }
}
#endif
