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
        print("""
        📖 ReadTabViewModel: Initializing
        - Note Title: \(note.title)
        - Content Length: \(note.preview.count)
        """)
        #endif
    }
    
    func loadContent() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // First check metadata for AI generated content
            if let aiContent = note.metadata?["aiGeneratedContent"] as? String {
                #if DEBUG
                print("📖 ReadTabViewModel: Using AI generated content")
                #endif
                let blocks = try parseContent(aiContent)
                content = NoteContent(
                    rawText: aiContent,
                    formattedContent: blocks,
                    summary: nil,
                    highlights: []
                )
            } else {
                // Fallback to preview if no AI content
                guard !note.preview.isEmpty else {
                    throw NSError(domain: "ReadTab", code: 1001,
                                 userInfo: [NSLocalizedDescriptionKey: "Note content is empty"])
                }
                
                #if DEBUG
                print("📖 ReadTabViewModel: Using preview content")
                #endif
                let blocks = try parseContent(note.preview)
                content = NoteContent(
                    rawText: note.preview,
                    formattedContent: blocks,
                    summary: nil,
                    highlights: []
                )
            }
            
            #if DEBUG
            print("📖 ReadTabViewModel: Content loaded successfully with \(content?.formattedContent.count ?? 0) blocks")
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
            #if DEBUG
            print("📖 ReadTabViewModel: Cannot parse empty text")
            #endif
            throw NSError(domain: "ReadTab", code: 1002,
                         userInfo: [NSLocalizedDescriptionKey: "Cannot parse empty text"])
        }
        
        #if DEBUG
        print("📖 ReadTabViewModel: Parsing content of length: \(text.count)")
        #endif
        
        return text.components(separatedBy: "\n").compactMap { line in
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard !trimmedLine.isEmpty else { return nil }
            
            if trimmedLine.hasPrefix("# ") {
                return ContentBlock(type: .heading1, content: String(trimmedLine.dropFirst(2)))
            } else if trimmedLine.hasPrefix("## ") {
                return ContentBlock(type: .heading2, content: String(trimmedLine.dropFirst(3)))
            } else if trimmedLine.hasPrefix("- ") {
                return ContentBlock(type: .bulletList, content: String(trimmedLine.dropFirst(2)))
            } else if trimmedLine.hasPrefix("`") && trimmedLine.hasSuffix("`") {
                return ContentBlock(type: .codeBlock(language: nil), content: String(trimmedLine.dropFirst().dropLast()))
            } else if trimmedLine.hasPrefix("> ") {
                return ContentBlock(type: .quote, content: String(trimmedLine.dropFirst(2)))
            } else {
                return ContentBlock(type: .paragraph, content: trimmedLine)
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
