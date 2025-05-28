import SwiftUI

// MARK: - Note Creation Header Component
struct NoteCreationHeader: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.Colors.primary, Theme.Colors.primary.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.top, Theme.Spacing.xl)

            Text(title)
                .font(Theme.Typography.h2)
                .foregroundColor(Theme.Colors.text)

            Text(subtitle)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
}

// MARK: - Preview
#if DEBUG
struct NoteCreationHeader_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            NoteCreationHeader(
                icon: "mic.circle.fill",
                title: "Audio Recording",
                subtitle: "Record audio and create AI-powered notes"
            )
            .padding()
            .previewLayout(.sizeThatFits)
            .previewDisplayName("Audio Recording")
            
            NoteCreationHeader(
                icon: "play.circle.fill",
                title: "YouTube Notes",
                subtitle: "Create AI-powered notes from YouTube videos"
            )
            .padding()
            .previewLayout(.sizeThatFits)
            .previewDisplayName("YouTube")
            
            NoteCreationHeader(
                icon: "doc.circle.fill",
                title: "Import PDF",
                subtitle: "Extract text from PDF documents"
            )
            .padding()
            .preferredColorScheme(.dark)
            .previewLayout(.sizeThatFits)
            .previewDisplayName("PDF - Dark Mode")
        }
    }
}
#endif
