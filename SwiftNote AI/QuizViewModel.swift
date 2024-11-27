import SwiftUI

// MARK: - Quiz View Model
@MainActor
final class QuizViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var currentQuestionIndex = 0
    @Published var selectedAnswer: Int?
    @Published var showResults = false
    @Published private(set) var questions: [QuizQuestion] = []
    @Published private(set) var loadingState: LoadingState = .idle
    
    // MARK: - Models
    struct QuizQuestion: Identifiable, Equatable {
        let id: UUID
        let question: String
        let options: [String]
        let correctAnswer: Int
        let explanation: String?
        
        init(
            id: UUID = UUID(),
            question: String,
            options: [String],
            correctAnswer: Int,
            explanation: String? = nil
        ) {
            self.id = id
            self.question = question
            self.options = options
            self.correctAnswer = correctAnswer
            self.explanation = explanation
            
            #if DEBUG
            print("📝 QuizViewModel: Created question - \(question)")
            #endif
        }
    }

    init() {
        #if DEBUG
        print("📝 QuizViewModel: Initializing")
        #endif
    }

    // MARK: - Question Management
    func generateQuestions(from content: String) async throws {
        loadingState = .loading(message: "Generating questions...")
        
        do {
            // Simulate AI processing time
            try await Task.sleep(nanoseconds: 2_000_000_000)
            
            questions = [
                QuizQuestion(
                    question: "What is the main topic?",
                    options: ["Option A", "Option B", "Option C", "Option D"],
                    correctAnswer: 0
                ),
                QuizQuestion(
                    question: "Which key point was discussed?",
                    options: ["Point 1", "Point 2", "Point 3", "Point 4"],
                    correctAnswer: 1
                )
            ]
            
            loadingState = .success(message: "Questions generated")
            
            #if DEBUG
            print("📝 QuizViewModel: Generated \(questions.count) questions")
            #endif
        } catch {
            #if DEBUG
            print("📝 QuizViewModel: Error generating questions - \(error)")
            #endif
            loadingState = .error(message: error.localizedDescription)
            throw error
        }
    }
}
