import Foundation

// MARK: - Quiz Models
struct QuizQuestion: Identifiable, Codable, Equatable {
    let id: UUID
    let question: String
    let options: [String]
    let correctAnswer: Int
    let explanation: String?
    
    init(id: UUID = UUID(), question: String, options: [String], correctAnswer: Int, explanation: String? = nil) {
        self.id = id
        self.question = question
        self.options = options
        self.correctAnswer = correctAnswer
        self.explanation = explanation
    }
}

struct QuizResult: Codable, Equatable {
    let questionId: UUID
    let selectedAnswer: Int
    let isCorrect: Bool
    let timestamp: Date
    
    init(questionId: UUID, selectedAnswer: Int, correctAnswer: Int, timestamp: Date = Date()) {
        self.questionId = questionId
        self.selectedAnswer = selectedAnswer
        self.isCorrect = selectedAnswer == correctAnswer
        self.timestamp = timestamp
    }
}

struct QuizSession: Codable {
    let id: UUID
    let noteId: UUID
    let startTime: Date
    let endTime: Date?
    let results: [QuizResult]
    let score: Double
    
    var duration: TimeInterval {
        endTime?.timeIntervalSince(startTime) ?? Date().timeIntervalSince(startTime)
    }
}

// MARK: - Quiz Analytics Models
struct QuizPerformanceData: Codable, Equatable {
    let completedQuizzes: Int
    let correctAnswers: Int
    let totalQuestions: Int
    let averageScore: Double
    let topicPerformance: [String: Double]
    var title: String?
    var detail: String?
}
