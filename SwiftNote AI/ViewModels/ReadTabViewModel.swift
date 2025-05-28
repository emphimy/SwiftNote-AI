import SwiftUI
import CoreData
import Combine
import Down

// MARK: - Read Tab View Model
@MainActor
final class ReadTabViewModel: ObservableObject {
    @Published var content: NoteContent?
    @Published var textSize: CGFloat = 14
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
        var isNextParagraphFeynman = false

        for (index, line) in lines.enumerated() {
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

            // Handle Feynman simplifications first (before regular headers)
            if (trimmed.contains("**###** 💡 1 Paragraph Simplification") ||
                trimmed.contains("💡 1 Paragraph Simplification") ||
                trimmed.contains("💡1 Paragraph Simplification") ||
                trimmed.contains("**###** 💡 Feynman Simplification") ||
                trimmed.contains("💡 Feynman Simplification") ||
                trimmed.contains("💡Feynman Simplification")) {
                // Mark that the next paragraph should be treated as a Feynman simplification
                isNextParagraphFeynman = true
                continue
            }
            // Handle headers
            else if trimmed.hasPrefix("# ") {
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
                // Check if this paragraph should be a Feynman simplification
                if isNextParagraphFeynman {
                    blocks.append(ContentBlock(type: .feynmanSimplification, content: trimmed))
                    isNextParagraphFeynman = false
                } else {
                    parseInlineFormatting(trimmed, fontSize: textSize, into: &blocks)
                }
            }
        }

        // Handle any remaining table
        if let headers = tableHeaders {
            blocks.append(ContentBlock(type: .table(headers: headers, rows: tableRows), content: ""))
        }

        return blocks
    }

    // Helper method to parse inline formatting (bold, italic, etc.)
    private func parseInlineFormatting(_ text: String, fontSize: CGFloat, into blocks: inout [ContentBlock]) {
        // Check for inline formatting
        if text.contains("**") || text.contains("*") {
            // Process text with regex to identify formatting
            var currentIndex = text.startIndex
            var currentText = ""
            var inBold = false
            var inItalic = false

            while currentIndex < text.endIndex {
                let nextTwoChars = text[currentIndex...].prefix(2)
                let nextChar = text[currentIndex]

                // Handle bold (** **)
                if nextTwoChars == "**" {
                    // Add current text if any
                    if !currentText.isEmpty {
                        let blockType: ContentBlock.BlockType
                        if inBold && inItalic {
                            blockType = .formattedText(style: .boldItalic)
                        } else if inBold {
                            blockType = .formattedText(style: .bold)
                        } else if inItalic {
                            blockType = .formattedText(style: .italic)
                        } else {
                            blockType = .paragraph
                        }
                        blocks.append(ContentBlock(type: blockType, content: currentText))
                        currentText = ""
                    }

                    // Toggle bold state
                    inBold.toggle()
                    currentIndex = text.index(currentIndex, offsetBy: 2)
                }
                // Handle italic (* *)
                else if nextChar == "*" && (currentIndex == text.startIndex || text[text.index(before: currentIndex)] != "*") &&
                        (currentIndex == text.index(before: text.endIndex) || text[text.index(after: currentIndex)] != "*") {
                    // Add current text if any
                    if !currentText.isEmpty {
                        let blockType: ContentBlock.BlockType
                        if inBold && inItalic {
                            blockType = .formattedText(style: .boldItalic)
                        } else if inBold {
                            blockType = .formattedText(style: .bold)
                        } else if inItalic {
                            blockType = .formattedText(style: .italic)
                        } else {
                            blockType = .paragraph
                        }
                        blocks.append(ContentBlock(type: blockType, content: currentText))
                        currentText = ""
                    }

                    // Toggle italic state
                    inItalic.toggle()
                    currentIndex = text.index(after: currentIndex)
                }
                else {
                    currentText.append(nextChar)
                    currentIndex = text.index(after: currentIndex)
                }
            }

            // Add any remaining text
            if !currentText.isEmpty {
                let blockType: ContentBlock.BlockType
                if inBold && inItalic {
                    blockType = .formattedText(style: .boldItalic)
                } else if inBold {
                    blockType = .formattedText(style: .bold)
                } else if inItalic {
                    blockType = .formattedText(style: .italic)
                } else {
                    blockType = .paragraph
                }
                blocks.append(ContentBlock(type: blockType, content: currentText))
            }
        } else {
            // No formatting, just add as paragraph
            blocks.append(ContentBlock(type: .paragraph, content: text))
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
