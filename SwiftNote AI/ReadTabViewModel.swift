import SwiftUI
import CoreData
import Combine
import Down

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
        
        var blocks: [ContentBlock] = []
        let lines = text.components(separatedBy: .newlines)
        var currentCodeBlock: String?
        var codeLanguage: String?
        var tableHeaders: [String]?
        var tableRows: [[String]] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            
            // Handle code blocks
            if trimmed.hasPrefix("```") {
                if currentCodeBlock == nil {
                    codeLanguage = String(trimmed.dropFirst(3))
                    currentCodeBlock = ""
                } else {
                    blocks.append(ContentBlock(type: .codeBlock(language: codeLanguage), content: currentCodeBlock ?? ""))
                    currentCodeBlock = nil
                    codeLanguage = nil
                }
                continue
            }
            
            if currentCodeBlock != nil {
                currentCodeBlock?.append(trimmed + "\n")
                continue
            }
            
            // Handle tables
            if trimmed.contains("|") {
                let cells = trimmed.components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                
                if tableHeaders == nil {
                    tableHeaders = cells
                } else if trimmed.contains("---") {
                    continue
                } else {
                    tableRows.append(cells)
                }
                continue
            } else if tableHeaders != nil {
                blocks.append(ContentBlock(type: .table(headers: tableHeaders ?? [], rows: tableRows), content: ""))
                tableHeaders = nil
                tableRows = []
            }
            
            // Handle headers
            if trimmed.hasPrefix("# ") {
                blocks.append(ContentBlock(type: .heading1, content: String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("## ") {
                blocks.append(ContentBlock(type: .heading2, content: String(trimmed.dropFirst(3))))
            } else if trimmed.hasPrefix("### ") {
                blocks.append(ContentBlock(type: .heading3, content: String(trimmed.dropFirst(4))))
            } else if trimmed.hasPrefix("#### ") {
                blocks.append(ContentBlock(type: .heading4, content: String(trimmed.dropFirst(5))))
            } else if trimmed.hasPrefix("##### ") {
                blocks.append(ContentBlock(type: .heading5, content: String(trimmed.dropFirst(6))))
            } else if trimmed.hasPrefix("###### ") {
                blocks.append(ContentBlock(type: .heading6, content: String(trimmed.dropFirst(7))))
            }
            // Handle lists
            else if trimmed.hasPrefix("- [ ] ") {
                blocks.append(ContentBlock(type: .taskList(checked: false), content: String(trimmed.dropFirst(6))))
            } else if trimmed.hasPrefix("- [x] ") {
                blocks.append(ContentBlock(type: .taskList(checked: true), content: String(trimmed.dropFirst(6))))
            } else if trimmed.hasPrefix("- ") {
                blocks.append(ContentBlock(type: .bulletList, content: String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("* ") {
                blocks.append(ContentBlock(type: .bulletList, content: String(trimmed.dropFirst(2))))
            } else if let match = trimmed.range(of: "^\\d+\\. ", options: .regularExpression) {
                blocks.append(ContentBlock(type: .numberedList, content: String(trimmed[match.upperBound...])))
            }
            // Handle quotes
            else if trimmed.hasPrefix("> ") {
                blocks.append(ContentBlock(type: .quote, content: String(trimmed.dropFirst(2))))
            }
            // Handle horizontal rules
            else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(ContentBlock(type: .horizontalRule, content: ""))
            }
            // Handle formatted text
            else {
                let text = trimmed
                var currentIndex = text.startIndex
                var segments: [ContentBlock] = []
                
                while currentIndex < text.endIndex {
                    // Find next bold text
                    if let boldRange = text[currentIndex...].range(of: "\\*\\*[^*]+\\*\\*", options: .regularExpression) {
                        // Add text before bold as regular paragraph if any
                        let beforeBold = String(text[currentIndex..<boldRange.lowerBound])
                        if !beforeBold.isEmpty {
                            segments.append(ContentBlock(type: .paragraph, content: beforeBold))
                        }
                        
                        // Add bold text
                        let boldText = String(text[boldRange])
                        let content = String(boldText.dropFirst(2).dropLast(2))
                        segments.append(ContentBlock(type: .formattedText(style: .bold), content: content))
                        
                        currentIndex = boldRange.upperBound
                    } else {
                        // Add remaining text as regular paragraph
                        let remainingText = String(text[currentIndex...])
                        if !remainingText.isEmpty {
                            segments.append(ContentBlock(type: .paragraph, content: remainingText))
                        }
                        break
                    }
                }
                
                blocks.append(contentsOf: segments)
            }
        }
        
        // Handle any remaining table
        if let headers = tableHeaders {
            blocks.append(ContentBlock(type: .table(headers: headers, rows: tableRows), content: ""))
        }
        
        // Deduplicate blocks by comparing content
        var uniqueBlocks: [ContentBlock] = []
        var seenContent = Set<String>()
        
        for block in blocks {
            let key = "\(block.content)_\(block.type)"
            if !seenContent.contains(key) {
                uniqueBlocks.append(block)
                seenContent.insert(key)
            }
        }
        
        return uniqueBlocks
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
