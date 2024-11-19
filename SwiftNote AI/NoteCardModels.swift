import SwiftUI

// MARK: - Note Card Configuration
struct NoteCardConfiguration {
    let title: String
    let date: Date
    let preview: String
    let sourceType: NoteSourceType
    let isFavorite: Bool
    let tags: [String]
    
    // MARK: - Debug Description
    var debugDescription: String {
        """
        NoteCard:
        - Title: \(title)
        - Date: \(date)
        - Preview: \(preview)
        - Source: \(sourceType)
        - Favorite: \(isFavorite)
        - Tags: \(tags.joined(separator: ", "))
        """
    }
}

// MARK: - Note Source Type
enum NoteSourceType: String {
    case audio = "mic.fill"
    case text = "doc.text.fill"
    case video = "video.fill"
    case upload = "arrow.up.circle.fill"
    
    var icon: Image {
        Image(systemName: self.rawValue)
    }
    
    var color: Color {
        switch self {
        case .audio: return .blue
        case .text: return .green
        case .video: return .red
        case .upload: return .orange
        }
    }
}

// MARK: - Card Actions Protocol
protocol CardActions {
    func onFavorite()
    func onShare()
    func onDelete()
    func onTagSelected(_ tag: String)
}

// MARK: - Action Card Item
struct ActionCardItem: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    // MARK: - Debug Description
    var debugDescription: String {
        "ActionCardItem: \(title) with icon \(icon)"
    }
}
