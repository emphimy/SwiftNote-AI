import SwiftUI
import CoreData
import Combine

// MARK: - Read Tab View Model
@MainActor
final class ReadTabViewModel: ObservableObject {
    @Published var content: NoteContent?
    @Published var textSize: CGFloat = 16
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchText = ""
    @Published var highlights: [TextHighlight] = []
    
    private let note: NoteCardConfiguration
    
    init(note: NoteCardConfiguration) {
        self.note = note
        #if DEBUG
        print("📖 ReadTabViewModel: Initializing with note: \(note.title)")
        #endif
    }
    
    func loadContent() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Simulate potential error conditions
            guard !note.preview.isEmpty else {
                throw NSError(domain: "ReadTab", code: 1001,
                             userInfo: [NSLocalizedDescriptionKey: "Note content is empty"])
            }
            
            // Process raw text into formatted content
            let blocks = try parseContent(note.preview)
            content = NoteContent(
                rawText: note.preview,
                formattedContent: blocks,
                summary: nil,
                highlights: []
            )
            
            #if DEBUG
            print("📖 ReadTabViewModel: Content loaded successfully")
            #endif
        } catch {
            #if DEBUG
            print("📖 ReadTabViewModel: Error loading content - \(error)")
            #endif
            errorMessage = "Failed to load content: \(error.localizedDescription)"
        }
    }
    
    private func parseContent(_ text: String) throws -> [ContentBlock] {
        guard !text.isEmpty else {
            throw NSError(domain: "ReadTab", code: 1002,
                         userInfo: [NSLocalizedDescriptionKey: "Cannot parse empty text"])
        }
        
        return text.split(separator: "\n").map { line in
            if line.hasPrefix("# ") {
                return ContentBlock(type: .heading1, content: String(line.dropFirst(2)))
            } else if line.hasPrefix("## ") {
                return ContentBlock(type: .heading2, content: String(line.dropFirst(3)))
            } else if line.hasPrefix("- ") {
                return ContentBlock(type: .bulletList, content: String(line.dropFirst(2)))
            } else if line.hasPrefix("```") {
                return ContentBlock(type: .codeBlock(language: nil), content: String(line.dropFirst(3)))
            } else {
                return ContentBlock(type: .paragraph, content: String(line))
            }
        }
    }
    
    func adjustTextSize(_ delta: CGFloat) {
        textSize = min(max(12, textSize + delta), 24)
        #if DEBUG
        print("📖 ReadTabViewModel: Text size adjusted to: \(textSize)")
        #endif
    }
    
    func addHighlight(_ text: String, range: Range<String.Index>, color: Color = .yellow) {
        let highlight = TextHighlight(text: text, range: range, color: color, note: nil)
        highlights.append(highlight)
        #if DEBUG
        print("📖 ReadTabViewModel: Added highlight for text: \(text)")
        #endif
    }
}
