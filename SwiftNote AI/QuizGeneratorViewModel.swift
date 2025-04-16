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
            
            // Ensure questions are unique by checking for duplicates
            let uniqueQuestions = removeDuplicateQuestions(generatedQuestions)
            
            await MainActor.run {
                self.questions = uniqueQuestions
                self.currentQuestionIndex = 0
                self.selectedAnswer = nil
                self.loadingState = .success(message: "Quiz generated successfully")
            }
            
            #if DEBUG
            print("📝 QuizGenerator: Generated \(uniqueQuestions.count) unique questions")
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
    
    // Helper function to remove duplicate questions
    private func removeDuplicateQuestions(_ questions: [QuizQuestion]) -> [QuizQuestion] {
        var uniqueQuestions: [QuizQuestion] = []
        var seenQuestions: Set<String> = []
        
        for question in questions {
            // Create a unique identifier for the question based on its content
            let questionIdentifier = question.question.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Only add the question if we haven't seen it before
            if !seenQuestions.contains(questionIdentifier) {
                uniqueQuestions.append(question)
                seenQuestions.insert(questionIdentifier)
            } else {
                #if DEBUG
                print("📝 QuizGenerator: Removed duplicate question: \(question.question)")
                #endif
            }
        }
        
        return uniqueQuestions
    }
    
    // MARK: - Private Methods
    private func generateQuestions(from content: String) async throws -> [QuizQuestion] {
        #if DEBUG
        print("📝 QuizGenerator: Generating questions from content with length: \(content.count)")
        #endif
        
        // Ensure we have enough content to work with
        guard content.count > 100 else {
            return generateBasicQuestions(from: content)
        }
        
        // Process the content to extract key information
        let processedContent = processContent(content)
        
        // Generate different types of questions
        var questions: [QuizQuestion] = []
        
        // Add factual questions
        questions.append(contentsOf: generateFactualQuestions(from: processedContent))
        
        // Add conceptual questions
        questions.append(contentsOf: generateConceptualQuestions(from: processedContent))
        
        // Add relationship questions
        questions.append(contentsOf: generateRelationshipQuestions(from: processedContent))
        
        // Add application questions
        questions.append(contentsOf: generateApplicationQuestions(from: processedContent))
        
        // Ensure we have at least 15 questions
        if questions.count < 15 {
            questions.append(contentsOf: generateSupplementaryQuestions(from: processedContent, currentCount: questions.count))
        }
        
        // Shuffle the questions for variety
        return questions.shuffled()
    }
    
    // Process content to extract key information
    private func processContent(_ content: String) -> [String: Any] {
        // Split content into paragraphs
        let paragraphs = content.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        
        // Extract sentences
        let sentences = content.components(separatedBy: ".").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        
        // Extract key terms (words that appear frequently)
        let words = content.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count > 3 }
        
        let wordFrequency = Dictionary(grouping: words, by: { $0 })
            .mapValues { $0.count }
            .filter { $0.value > 1 }
            .sorted { $0.value > $1.value }
            .prefix(20)
            .map { $0.key }
        
        // Extract potential topics (first sentence of each paragraph often contains the topic)
        let potentialTopics = paragraphs.compactMap { paragraph -> String? in
            let firstSentence = paragraph.components(separatedBy: ".").first?.trimmingCharacters(in: .whitespacesAndNewlines)
            return firstSentence?.count ?? 0 > 10 ? firstSentence : nil
        }
        
        return [
            "paragraphs": paragraphs,
            "sentences": sentences,
            "keyTerms": wordFrequency,
            "potentialTopics": potentialTopics
        ]
    }
    
    // Generate factual questions (who, what, when, where)
    private func generateFactualQuestions(from processedContent: [String: Any]) -> [QuizQuestion] {
        guard let sentences = processedContent["sentences"] as? [String],
              let keyTerms = processedContent["keyTerms"] as? [String] else {
            return []
        }
        
        var questions: [QuizQuestion] = []
        
        // Create questions based on key terms
        for term in keyTerms.prefix(5) {
            // Find sentences containing this term
            let relevantSentences = sentences.filter { $0.lowercased().contains(term.lowercased()) }
            guard let sentence = relevantSentences.first else { continue }
            
            // Create a question by replacing the term with a blank
            let question = "Which term best fits in this context: \"\(sentence.replacingOccurrences(of: term, with: "______", options: .caseInsensitive))\""
            
            // Generate options (1 correct, 3 distractors)
            var options = [term]
            
            // Add distractor options from other key terms
            let distractors = keyTerms.filter { $0 != term }.prefix(3)
            options.append(contentsOf: distractors)
            
            // If we don't have enough distractors, add some generic ones
            while options.count < 4 {
                options.append("None of the above")
            }
            
            // Shuffle options
            options.shuffle()
            
            // Find the index of the correct answer
            let correctAnswer = options.firstIndex(of: term) ?? 0
            
            questions.append(QuizQuestion(
                question: question,
                options: options,
                correctAnswer: correctAnswer
            ))
        }
        
        return questions
    }
    
    // Generate conceptual questions (understanding of concepts)
    private func generateConceptualQuestions(from processedContent: [String: Any]) -> [QuizQuestion] {
        guard let paragraphs = processedContent["paragraphs"] as? [String],
              let potentialTopics = processedContent["potentialTopics"] as? [String] else {
            return []
        }
        
        var questions: [QuizQuestion] = []
        
        // Create questions about main topics
        for (index, topic) in potentialTopics.prefix(5).enumerated() {
            let question = "What is the main idea discussed in this excerpt: \"\(topic)\""
            
            // Generate options
            var options: [String] = []
            
            // The correct answer is a summary of the paragraph containing this topic
            if let paragraphIndex = paragraphs.firstIndex(where: { $0.contains(topic) }),
               let paragraph = paragraphs[safe: paragraphIndex] {
                let correctOption = summarizeParagraph(paragraph)
                options.append(correctOption)
                
                // Add distractor options from other paragraphs
                for i in 0..<3 {
                    let distractorIndex = (paragraphIndex + i + 1) % paragraphs.count
                    if let distractorParagraph = paragraphs[safe: distractorIndex] {
                        options.append(summarizeParagraph(distractorParagraph))
                    } else {
                        options.append("None of the above")
                    }
                }
            } else {
                // Fallback if we can't find the paragraph
                options = [
                    "It explains the main concept of the note",
                    "It introduces a supporting example",
                    "It presents a counterargument",
                    "It concludes the discussion"
                ]
            }
            
            // Shuffle options if we're not using the fallback
            if options.count == 4 {
                let correctOption = options[0]
                options.shuffle()
                let correctAnswer = options.firstIndex(of: correctOption) ?? 0
                
                questions.append(QuizQuestion(
                    question: question,
                    options: options,
                    correctAnswer: correctAnswer
                ))
            }
        }
        
        return questions
    }
    
    // Generate relationship questions (how concepts relate)
    private func generateRelationshipQuestions(from processedContent: [String: Any]) -> [QuizQuestion] {
        guard let sentences = processedContent["sentences"] as? [String],
              let keyTerms = processedContent["keyTerms"] as? [String] else {
            return []
        }
        
        var questions: [QuizQuestion] = []
        
        // Find sentences that contain multiple key terms
        let multiTermSentences = sentences.filter { sentence in
            let termCount = keyTerms.filter { sentence.lowercased().contains($0.lowercased()) }.count
            return termCount >= 2
        }
        
        for sentence in multiTermSentences.prefix(5) {
            let question = "What relationship is described in this statement: \"\(sentence)\""
            
            // Generate options
            let options = [
                "Cause and effect",
                "Comparison and contrast",
                "Problem and solution",
                "Sequential relationship"
            ]
            
            // For simplicity, we'll use a random correct answer since we don't have actual NLP
            let correctAnswer = Int.random(in: 0..<options.count)
            
            questions.append(QuizQuestion(
                question: question,
                options: options,
                correctAnswer: correctAnswer
            ))
        }
        
        return questions
    }
    
    // Generate application questions (applying concepts)
    private func generateApplicationQuestions(from processedContent: [String: Any]) -> [QuizQuestion] {
        guard let paragraphs = processedContent["paragraphs"] as? [String] else {
            return []
        }
        
        var questions: [QuizQuestion] = []
        
        // Create application questions based on the content
        for paragraph in paragraphs.prefix(3) {
            let question = "Based on the information in the note, which of the following would be the most appropriate application?"
            
            // Generate options
            let options = [
                "Apply the concepts to solve a related problem",
                "Use the information to make a decision",
                "Explain the concept to someone else",
                "Create a new theory based on this information"
            ]
            
            // For simplicity, we'll use a random correct answer
            let correctAnswer = Int.random(in: 0..<options.count)
            
            questions.append(QuizQuestion(
                question: question,
                options: options,
                correctAnswer: correctAnswer
            ))
        }
        
        return questions
    }
    
    // Generate supplementary questions to reach the minimum count
    private func generateSupplementaryQuestions(from processedContent: [String: Any], currentCount: Int) -> [QuizQuestion] {
        guard let sentences = processedContent["sentences"] as? [String] else {
            return []
        }
        
        var questions: [QuizQuestion] = []
        let neededCount = max(0, 15 - currentCount)
        
        // Create true/false questions from sentences
        for sentence in sentences.prefix(neededCount) {
            let question = "Is the following statement true according to the note: \"\(sentence)\""
            
            // Generate options
            let options = ["True", "False"]
            
            // For simplicity, we'll set "True" as the correct answer for actual sentences from the note
            let correctAnswer = 0
            
            questions.append(QuizQuestion(
                question: question,
                options: options,
                correctAnswer: correctAnswer
            ))
        }
        
        return questions
    }
    
    // Generate basic questions for very short content
    private func generateBasicQuestions(from content: String) -> [QuizQuestion] {
        return [
            QuizQuestion(
                question: "What is the main topic of this note?",
                options: ["The content provided", "An unrelated topic", "Cannot be determined", "None of the above"],
                correctAnswer: 0
            ),
            QuizQuestion(
                question: "Which best describes the content of this note?",
                options: ["Brief information", "Detailed analysis", "Step-by-step instructions", "Historical overview"],
                correctAnswer: 0
            )
        ]
    }
    
    // Helper function to summarize a paragraph
    private func summarizeParagraph(_ paragraph: String) -> String {
        // Simple summarization: take the first sentence if it's not too long
        if let firstSentence = paragraph.components(separatedBy: ".").first,
           firstSentence.count < 100 {
            return firstSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Otherwise, take a substring
        let maxLength = min(paragraph.count, 100)
        let endIndex = paragraph.index(paragraph.startIndex, offsetBy: maxLength)
        return String(paragraph[..<endIndex]) + "..."
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
