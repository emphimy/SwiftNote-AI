import SwiftUI
import Combine

// MARK: - Flashcard View Model
@MainActor
final class FlashcardsViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var isLoading = false
    @Published var flashcards: [Flashcard] = []
    @Published private(set) var currentIndex = 0
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
        
        withAnimation(.spring()) {
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
    
    private func parseNoteContent(_ content: String) -> [String] {
        return content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
    
    private func generateFlashcardsFromContent(_ content: [String], title: String, date: Date) async throws -> [Flashcard] {
        // TODO: Implement AI-based flashcard generation
        // For now, using basic content parsing
        var generatedCards = [
            Flashcard(front: "What is the main topic?", back: title),
            Flashcard(front: "When was this created?", back: date.formatted())
        ]
        
        // Generate cards from content
        for (index, line) in content.enumerated() {
            if index > 5 { break } // Limit number of cards for now
            
            if line.contains(":") {
                let parts = line.split(separator: ":")
                if parts.count == 2 {
                    generatedCards.append(
                        Flashcard(
                            front: String(parts[0].trimmingCharacters(in: .whitespaces)) + "?",
                            back: String(parts[1].trimmingCharacters(in: .whitespaces))
                        )
                    )
                }
            } else if line.hasPrefix("-") || line.hasPrefix("•") {
                generatedCards.append(
                    Flashcard(
                        front: "What point was mentioned in the notes?",
                        back: line.trimmingCharacters(in: CharacterSet(charactersIn: "-•").union(.whitespaces))
                    )
                )
            }
        }
        
        return generatedCards
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
