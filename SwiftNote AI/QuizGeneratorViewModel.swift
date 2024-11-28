import Foundation
import CoreData
import SwiftUI

// MARK: - Quiz Error
enum QuizError: LocalizedError {
    case emptyContent
    case saveFailed(Error)
    case fetchFailed(Error)
    case invalidQuestionIndex
    
    var errorDescription: String? {
        switch self {
        case .emptyContent: return "Note content is empty"
        case .saveFailed(let error): return "Failed to save quiz: \(error.localizedDescription)"
        case .fetchFailed(let error): return "Failed to fetch quiz data: \(error.localizedDescription)"
        case .invalidQuestionIndex: return "Invalid question index"
        }
    }
}

// MARK: - Quiz Generator View Model
@MainActor
final class QuizGeneratorViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published private(set) var questions: [QuizQuestion] = []
    @Published private(set) var analytics: QuizPerformanceData?
    @Published private(set) var loadingState: LoadingState = .idle
    @Published private(set) var currentQuestionIndex = 0
    @Published var selectedAnswer: Int?
    @Published var showResults = false // Add this line
    
    // MARK: - Private Properties
    private let viewContext: NSManagedObjectContext
    private let noteId: UUID
    private let noteContent: String
    private var quizResults: [UUID: Int] = [:]
    
    // MARK: - Initialization
    init(context: NSManagedObjectContext, noteId: UUID, content: String) {
        self.viewContext = context
        self.noteId = noteId
        self.noteContent = content
        
        #if DEBUG
        print("📝 QuizGenerator: Initializing with noteId: \(noteId)")
        #endif
    }
    
    // MARK: - Quiz Generation
    func generateQuiz() async throws {
        guard !noteContent.isEmpty else {
            #if DEBUG
            print("📝 QuizGenerator: Error - Empty content")
            #endif
            throw QuizError.emptyContent
        }
        
        loadingState = .loading(message: "Generating quiz questions...")
        
        do {
            // Simulate AI processing time
            try await Task.sleep(nanoseconds: 2_000_000_000)
            
            let generatedQuestions = try await generateQuestions(from: noteContent)
            
            await MainActor.run {
                self.questions = generatedQuestions
                self.loadingState = .success(message: "Quiz generated successfully")
            }
            
            #if DEBUG
            print("📝 QuizGenerator: Generated \(generatedQuestions.count) questions")
            #endif
        } catch {
            #if DEBUG
            print("📝 QuizGenerator: Error generating quiz - \(error)")
            #endif
            loadingState = .error(message: error.localizedDescription)
            throw error
        }
    }
    
    // MARK: - Quiz Progress
    func submitAnswer(_ answer: Int) async throws {
        guard let currentQuestion = questions[safe: currentQuestionIndex] else {
            throw QuizError.invalidQuestionIndex
        }
        
        let result = QuizResult(
            questionId: currentQuestion.id,
            selectedAnswer: answer,
            correctAnswer: currentQuestion.correctAnswer
        )
        quizResults[currentQuestion.id] = answer
        
        #if DEBUG
        print("📝 QuizGenerator: Submitting answer - Question: \(currentQuestionIndex), Selected: \(answer), Correct: \(result.isCorrect)")
        #endif

        if currentQuestionIndex < questions.count - 1 {
            currentQuestionIndex += 1
            selectedAnswer = nil
        } else {
            try await calculateAndUpdateAnalytics()
            showResults = true
        }
    }
    
    // MARK: - Private Methods
    private func generateQuestions(from content: String) async throws -> [QuizQuestion] {
        // TODO: Implement AI-based question generation
        return [
            QuizQuestion(
                question: "What is the main topic of this note?",
                options: ["Option A", "Option B", "Option C", "Option D"],
                correctAnswer: 0
            ),
            QuizQuestion(
                question: "Which key point was discussed?",
                options: ["Point 1", "Point 2", "Point 3", "Point 4"],
                correctAnswer: 1
            )
        ]
    }
    
    private func calculateAndUpdateAnalytics() async throws {
        let analytics = try await fetchOrCreateAnalytics()
        try updateAnalytics(analytics)
        try viewContext.save()
        
        #if DEBUG
        print("📝 QuizGenerator: Analytics calculated and updated")
        #endif
    }
    
    private func createQuizProgress() -> NSManagedObject {
        let progress = NSEntityDescription.insertNewObject(forEntityName: "QuizProgress", into: viewContext)
        progress.setValue(UUID(), forKey: "id")
        progress.setValue(Date(), forKey: "timestamp")
        progress.setValue(noteId, forKey: "noteId")
        
        #if DEBUG
        print("📝 QuizGenerator: Created quiz progress entity")
        #endif
        
        return progress
    }
    
    private func createQuizAnalytics() -> NSManagedObject {
        let analytics = NSEntityDescription.insertNewObject(forEntityName: "QuizAnalytics", into: viewContext)
        analytics.setValue(UUID(), forKey: "id")
        analytics.setValue(0, forKey: "completedQuizzes")
        analytics.setValue(0, forKey: "correctAnswers")
        analytics.setValue(0, forKey: "totalQuestions")
        analytics.setValue(0.0, forKey: "averageScore")
        analytics.setValue(noteId, forKey: "noteId")
        
        #if DEBUG
        print("📝 QuizGenerator: Created quiz analytics entity")
        #endif
        
        return analytics
    }
    
    private func saveQuizProgress() async throws {
        do {
            let progress = createQuizProgress()
            progress.setValue(try JSONEncoder().encode(quizResults), forKey: "answers")
            
            let analytics = try await fetchOrCreateAnalytics()
            try updateAnalytics(analytics)

            try viewContext.save()
            
            #if DEBUG
            print("📝 QuizGenerator: Saved quiz progress successfully")
            #endif
        } catch {
            #if DEBUG
            print("📝 QuizGenerator: Error saving quiz progress - \(error)")
            #endif
            throw QuizError.saveFailed(error)
        }
    }
    
    private func fetchOrCreateAnalytics() async throws -> NSManagedObject {
        let request = NSFetchRequest<NSManagedObject>(entityName: "QuizAnalytics")
        request.predicate = NSPredicate(format: "noteId == %@", noteId as CVarArg)
        
        do {
            let analytics = try viewContext.fetch(request).first ?? createQuizAnalytics()
            return analytics
        } catch {
            #if DEBUG
            print("📝 QuizGenerator: Error fetching analytics - \(error)")
            #endif
            throw QuizError.fetchFailed(error)
        }
    }

    private func updateAnalytics(_ analytics: NSManagedObject) throws {
        let completedQuizzes = (analytics.value(forKey: "completedQuizzes") as? Int32 ?? 0)
        let correctCount = calculateCorrectAnswers()
        let score = Double(correctCount) / Double(questions.count) * 100
        
        #if DEBUG
        print("📝 QuizGenerator: Calculating analytics - Score: \(score)%")
        #endif
        
        self.analytics = QuizPerformanceData(
            completedQuizzes: Int(completedQuizzes),
            correctAnswers: Int(correctCount),
            totalQuestions: questions.count,
            averageScore: score,
            topicPerformance: [:],
            title: "Quiz Performance",
            detail: "Session Results"
        )
    }
    
    private func calculateCorrectAnswers() -> Int32 {
        Int32(quizResults.reduce(0) { count, result in
            count + (questions.first { $0.id == result.key }?.correctAnswer == result.value ? 1 : 0)
        })
    }
}

// MARK: - Array Extension
private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
