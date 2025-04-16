import SwiftUI
import Combine
import AIProxy

// MARK: - Flashcard View Model
@MainActor
final class FlashcardsViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var isLoading = false
    @Published var flashcards: [Flashcard] = []
    @Published var currentIndex = 0
    @Published private(set) var totalCards = 0
    @Published private(set) var progress: Double = 0
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init() {
        #if DEBUG
        print("🎴 FlashcardsViewModel: Initializing")
        #endif
        setupSubscriptions()
    }
    
    // MARK: - Setup
    private func setupSubscriptions() {
        $flashcards
            .sink { [weak self] cards in
                self?.totalCards = cards.count
                self?.updateProgress()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    func generateFlashcards(from note: NoteCardConfiguration) async {
        #if DEBUG
        print("🎴 FlashcardsViewModel: Generating flashcards from note: \(note.title)")
        #endif
        
        isLoading = true
        errorMessage = nil
        
        do {
            // Simulate AI processing time
            try await Task.sleep(nanoseconds: 2_000_000_000)
            
            // Parse note content for better flashcard generation
            let content = parseNoteContent(note.preview)
            
            // Generate flashcards based on content
            flashcards = try await generateFlashcardsFromContent(content, title: note.title, date: note.date)
            
            #if DEBUG
            print("🎴 FlashcardsViewModel: Generated \(flashcards.count) flashcards")
            #endif
        } catch {
            #if DEBUG
            print("🎴 FlashcardsViewModel: Error generating flashcards - \(error)")
            #endif
            errorMessage = "Failed to generate flashcards: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    // MARK: - Navigation Methods
    func nextCard() {
        guard currentIndex < flashcards.count - 1 else {
            #if DEBUG
            print("🎴 FlashcardsViewModel: Cannot move to next card - already at last card")
            #endif
            return
        }
        
        withAnimation(.spring()) {
            currentIndex += 1
            updateProgress()
        }
        
        #if DEBUG
        print("🎴 FlashcardsViewModel: Moving to next card - \(currentIndex + 1)/\(totalCards)")
        #endif
    }
    
    func previousCard() {
        guard currentIndex > 0 else {
            #if DEBUG
            print("🎴 FlashcardsViewModel: Cannot move to previous card - already at first card")
            #endif
            return
        }
        
        withAnimation(.spring()) {
            currentIndex -= 1
            updateProgress()
        }
        
        #if DEBUG
        print("🎴 FlashcardsViewModel: Moving to previous card - \(currentIndex + 1)/\(totalCards)")
        #endif
    }
    
    func toggleCard() {
        guard flashcards.indices.contains(currentIndex) else {
            #if DEBUG
            print("🎴 FlashcardsViewModel: Cannot toggle card - invalid index")
            #endif
            return
        }
        
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            flashcards[currentIndex].isRevealed.toggle()
        }
        
        #if DEBUG
        print("🎴 FlashcardsViewModel: Toggled card \(currentIndex + 1) - Revealed: \(flashcards[currentIndex].isRevealed)")
        #endif
    }
    
    // MARK: - Private Methods
    private func updateProgress() {
        guard totalCards > 0 else {
            progress = 0
            return
        }
        progress = Double(currentIndex + 1) / Double(totalCards)
    }
    
    private func parseNoteContent(_ content: String) -> [String: Any] {
        // Split content into lines
        let lines = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        // Extract term-definition pairs (lines with colons)
        let definitions = lines.filter { $0.contains(":") }.compactMap { line -> (term: String, definition: String)? in
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            
            let term = parts[0].trimmingCharacters(in: .whitespaces)
            let definition = parts[1].trimmingCharacters(in: .whitespaces)
            
            // Only consider valid term-definition pairs with reasonable lengths
            guard !term.isEmpty && !definition.isEmpty && 
                  term.count < 50 && definition.count < 100 else { return nil }
            
            return (term: term, definition: definition)
        }
        
        // Extract bullet points (potential key concepts)
        let bulletPoints = lines.filter { 
            $0.hasPrefix("-") || $0.hasPrefix("•") || $0.hasPrefix("*") || $0.matches(of: /^\d+\.\s/).count > 0 
        }.map { line in
            line.trimmingCharacters(in: CharacterSet(charactersIn: "-•*").union(.whitespaces))
                .replacingOccurrences(of: #"^\d+\.\s+"#, with: "", options: .regularExpression)
        }.filter { $0.count < 100 } // Keep only reasonably sized points
        
        // Extract key phrases (short, complete phrases that might be important)
        let keyPhrases = lines.filter { 
            $0.count > 5 && $0.count < 80 && 
            !$0.contains(":") && 
            !$0.hasPrefix("-") && !$0.hasPrefix("•") && !$0.hasPrefix("*") &&
            $0.matches(of: /^\d+\.\s/).count == 0
        }
        
        return [
            "lines": lines,
            "definitions": definitions,
            "bulletPoints": bulletPoints,
            "keyPhrases": keyPhrases
        ]
    }
    
    private func generateFlashcardsFromContent(_ contentData: [String: Any], title: String, date: Date) async throws -> [Flashcard] {
        // First, try to generate AI-powered flashcards
        let aiCards = try await generateAIFlashcards(contentData: contentData, title: title)
        
        // If AI generation was successful and produced cards, use those
        if !aiCards.isEmpty {
            #if DEBUG
            print("🎴 FlashcardsViewModel: Generated \(aiCards.count) AI-powered flashcards")
            #endif
            return aiCards
        }
        
        // Fallback to traditional generation if AI fails
        #if DEBUG
        print("🎴 FlashcardsViewModel: Falling back to traditional flashcard generation")
        #endif
        
        var generatedCards: [Flashcard] = []
        
        // 1. Generate term-definition flashcards (the most important type)
        if let definitions = contentData["definitions"] as? [(term: String, definition: String)] {
            for (term, definition) in definitions {
                // Only create cards with reasonable lengths
                if term.count < 50 && definition.count < 100 {
                    generatedCards.append(Flashcard(
                        front: term,
                        back: definition
                    ))
                }
            }
        }
        
        // 2. Generate bullet point flashcards (simple recall)
        if let bulletPoints = contentData["bulletPoints"] as? [String] {
            for point in bulletPoints {
                // Create a simple question from the bullet point
                if point.count < 100 {
                    let question = "What is \(createQuestionFromPoint(point))?"
                    generatedCards.append(Flashcard(
                        front: question,
                        back: point
                    ))
                }
            }
        }
        
        // 3. Add a few key phrase flashcards if we don't have enough cards
        if generatedCards.count < 10, let keyPhrases = contentData["keyPhrases"] as? [String] {
            for phrase in keyPhrases.prefix(5) {
                if phrase.count < 80 {
                    let question = "Define or explain:"
                    generatedCards.append(Flashcard(
                        front: question,
                        back: phrase
                    ))
                }
            }
        }
        
        // 4. Add title card as a fallback if we have very few cards
        if generatedCards.count < 3 {
            generatedCards.append(Flashcard(
                front: "What is the main topic?",
                back: title
            ))
        }
        
        // Clean up any markdown in the flashcards and limit length
        return generatedCards.map { card in
            let cleanFront = cleanMarkdown(card.front)
            let cleanBack = cleanMarkdown(card.back)
            
            return Flashcard(
                id: card.id,
                front: cleanFront,
                back: cleanBack,
                isRevealed: card.isRevealed
            )
        }
    }
    
    // AI-powered flashcard generation
    private func generateAIFlashcards(contentData: [String: Any], title: String) async throws -> [Flashcard] {
        // Extract all relevant content for AI processing
        var contentForAI = "Title: \(title)\n\nContent:\n"
        
        if let lines = contentData["lines"] as? [String] {
            contentForAI += lines.joined(separator: "\n")
        }
        
        do {
            // Call the AI proxy service to generate flashcards
            #if DEBUG
            print("🎴 FlashcardsViewModel: Calling AI proxy service to generate flashcards")
            #endif
            
            let aiGeneratedCards = try await AIProxyService.shared.generateFlashcards(
                from: contentForAI,
                title: title,
                count: 15 // Minimum of 15 flashcards
            )
            
            // Convert the AI-generated cards to our Flashcard model
            let flashcards = aiGeneratedCards.map { cardPair in
                Flashcard(
                    front: cardPair.front,
                    back: cardPair.back
                )
            }
            
            #if DEBUG
            print("🎴 FlashcardsViewModel: AI proxy service generated \(flashcards.count) flashcards")
            #endif
            
            // Clean markdown and ensure reasonable lengths
            return flashcards.map { card in
                let cleanFront = cleanMarkdown(card.front)
                let cleanBack = cleanMarkdown(card.back)
                
                return Flashcard(
                    id: card.id,
                    front: cleanFront,
                    back: cleanBack,
                    isRevealed: card.isRevealed
                )
            }
        } catch {
            #if DEBUG
            print("🎴 FlashcardsViewModel: AI proxy service error - \(error.localizedDescription)")
            #endif
            
            // If AI generation fails, fall back to our algorithmic approach
            var aiCards: [Flashcard] = []
            
            // 1. Extract key concepts and definitions
            if let definitions = contentData["definitions"] as? [(term: String, definition: String)] {
                for (term, definition) in definitions {
                    // Create term->definition card
                    aiCards.append(Flashcard(
                        front: "Define: \(term)",
                        back: definition
                    ))
                    
                    // Create definition->term card (reverse)
                    aiCards.append(Flashcard(
                        front: "What term is defined as: \(definition.prefix(60))...",
                        back: term
                    ))
                }
            }
            
            // 2. Create fill-in-the-blank cards from bullet points
            if let bulletPoints = contentData["bulletPoints"] as? [String] {
                for point in bulletPoints {
                    if point.count > 10 && point.count < 100 {
                        let words = point.components(separatedBy: .whitespaces)
                        if words.count > 5 {
                            // Find a key word to blank out
                            let keyWordIndex = min(words.count - 1, max(2, words.count / 2))
                            let keyWord = words[keyWordIndex]
                            
                            if keyWord.count > 3 {
                                var blankPoint = words
                                blankPoint[keyWordIndex] = "________"
                                
                                aiCards.append(Flashcard(
                                    front: "Fill in the blank: \(blankPoint.joined(separator: " "))",
                                    back: keyWord
                                ))
                            }
                        }
                    }
                }
            }
            
            // 3. Create concept explanation cards
            if let keyPhrases = contentData["keyPhrases"] as? [String] {
                for phrase in keyPhrases.prefix(5) {
                    if phrase.count > 5 && phrase.count < 80 {
                        // Extract potential concept from the phrase
                        let words = phrase.components(separatedBy: .whitespaces)
                        if words.count >= 2 {
                            let concept = words.prefix(2).joined(separator: " ")
                            
                            aiCards.append(Flashcard(
                                front: "Explain the concept of \(concept)",
                                back: phrase
                            ))
                        }
                    }
                }
            }
            
            // 4. Create application questions
            if let lines = contentData["lines"] as? [String], lines.count > 5 {
                // Find potential topics from the first words of paragraphs
                let potentialTopics = lines.compactMap { line -> String? in
                    let words = line.components(separatedBy: .whitespaces)
                    if words.count >= 2 && words[0].count > 3 {
                        return words[0]
                    }
                    return nil
                }
                
                // Create application questions for the topics
                for topic in potentialTopics.prefix(3) {
                    aiCards.append(Flashcard(
                        front: "How would you apply the concept of \(topic) in a real-world situation?",
                        back: "Think about how \(topic) relates to the main concepts in this note. Consider practical applications and examples."
                    ))
                }
            }
            
            // 5. Create comparison cards if we have multiple concepts
            if let definitions = contentData["definitions"] as? [(term: String, definition: String)], definitions.count >= 2 {
                let terms = definitions.map { $0.term }
                
                if terms.count >= 2 {
                    for i in 0..<min(terms.count-1, 2) {
                        aiCards.append(Flashcard(
                            front: "Compare and contrast: \(terms[i]) vs. \(terms[i+1])",
                            back: "Consider the similarities and differences between these concepts based on their definitions and contexts."
                        ))
                    }
                }
            }
            
            // Clean markdown and ensure reasonable lengths
            return aiCards.map { card in
                let cleanFront = cleanMarkdown(card.front)
                let cleanBack = cleanMarkdown(card.back)
                
                return Flashcard(
                    id: card.id,
                    front: cleanFront,
                    back: cleanBack,
                    isRevealed: card.isRevealed
                )
            }
        }
    }
    
    // Helper to create a question from a bullet point
    private func createQuestionFromPoint(_ point: String) -> String {
        let words = point.components(separatedBy: .whitespaces)
        if words.count > 3 {
            // Try to extract a key concept from the first few words
            let firstFewWords = words.prefix(3).joined(separator: " ")
            return firstFewWords
        } else {
            return "this concept"
        }
    }
    
    // Helper function to clean markdown from text
    private func cleanMarkdown(_ text: String) -> String {
        var cleanedText = text
        
        // First, specifically handle header markdown (## and ###)
        let headerPattern = "(#{1,6})\\s+(.+?)(?:\\n|$)"
        if let headerRegex = try? NSRegularExpression(pattern: headerPattern, options: [.anchorsMatchLines]) {
            let range = NSRange(location: 0, length: cleanedText.utf16.count)
            let matches = headerRegex.matches(in: cleanedText, options: [], range: range)
            
            for match in matches.reversed() {
                if let contentRange = Range(match.range(at: 2), in: cleanedText),
                   let matchRange = Range(match.range, in: cleanedText) {
                    let headerContent = String(cleanedText[contentRange])
                    cleanedText.replaceSubrange(matchRange, with: headerContent)
                }
            }
        }
        
        // Remove markdown formatting with comprehensive patterns
        let markdownPatterns = [
            // Headers (already handled above, but keeping as fallback)
            "#{1,6}\\s+(.+?)(?:\\n|$)",
            
            // Emphasis
            "\\*\\*(.+?)\\*\\*", // Bold
            "\\*(.+?)\\*",       // Italic
            "__(.+?)__",         // Bold with underscores
            "_(.+?)_",           // Italic with underscores
            
            // Code
            "```[\\s\\S]*?```", // Code blocks
            "`(.+?)`",       // Inline code
            
            // Links
            "\\[(.+?)\\]\\(.+?\\)", // Links with text
            "<(.+?)>",         // Bare links
            
            // Lists
            "^\\s*[\\*\\-\\+]\\s+(.+?)$", // Unordered list items
            "^\\s*\\d+\\.\\s+(.+?)$",     // Ordered list items
            
            // Blockquotes
            "^\\s*>\\s+(.+?)$",
            
            // Horizontal rules
            "^\\s*[\\*\\-\\_]{3,}\\s*$"
        ]
        
        // Handle special cases that need specific replacements
        if let linkRegex = try? NSRegularExpression(pattern: "\\[(.+?)\\]\\((.+?)\\)", options: []) {
            let range = NSRange(location: 0, length: cleanedText.utf16.count)
            let matches = linkRegex.matches(in: cleanedText, options: [], range: range)
            
            for match in matches.reversed() {
                if let textRange = Range(match.range(at: 1), in: cleanedText),
                   let matchRange = Range(match.range, in: cleanedText) {
                    let linkText = String(cleanedText[textRange])
                    cleanedText.replaceSubrange(matchRange, with: linkText)
                }
            }
        }
        
        // Then handle general patterns
        for pattern in markdownPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) {
                let range = NSRange(location: 0, length: cleanedText.utf16.count)
                let matches = regex.matches(in: cleanedText, options: [], range: range)
                
                for match in matches.reversed() {
                    if match.numberOfRanges > 1, 
                       let captureRange = Range(match.range(at: 1), in: cleanedText),
                       let matchRange = Range(match.range, in: cleanedText) {
                        let capturedText = String(cleanedText[captureRange])
                        cleanedText.replaceSubrange(matchRange, with: capturedText)
                    } else if let matchRange = Range(match.range, in: cleanedText) {
                        // For patterns without capture groups, just remove the markdown
                        cleanedText.replaceSubrange(matchRange, with: "")
                    }
                }
            }
        }
        
        // Simple direct replacement for any remaining ## or ### that might be escaped or not caught by regex
        cleanedText = cleanedText.replacingOccurrences(of: "##", with: "")
        cleanedText = cleanedText.replacingOccurrences(of: "###", with: "")
        
        // Clean up any remaining special characters and extra whitespace
        cleanedText = cleanedText.replacingOccurrences(of: "\\", with: "")
        cleanedText = cleanedText.replacingOccurrences(of: "  ", with: " ")
        cleanedText = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleanedText
    }
    
    // MARK: - Cleanup
    deinit {
        #if DEBUG
        print("🎴 FlashcardsViewModel: Deinitializing")
        #endif
        cancellables.forEach { $0.cancel() }
    }
}

// MARK: - Flashcard Model
extension FlashcardsViewModel {
    struct Flashcard: Identifiable, Equatable {
        let id: UUID
        let front: String
        let back: String
        var isRevealed: Bool
        
        init(id: UUID = UUID(), front: String, back: String, isRevealed: Bool = false) {
            self.id = id
            self.front = front
            self.back = back
            self.isRevealed = isRevealed
        }
        
        static func == (lhs: Flashcard, rhs: Flashcard) -> Bool {
            lhs.id == rhs.id &&
            lhs.front == rhs.front &&
            lhs.back == rhs.back &&
            lhs.isRevealed == rhs.isRevealed
        }
    }
}
