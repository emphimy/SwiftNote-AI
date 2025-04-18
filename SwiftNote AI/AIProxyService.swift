import AIProxy
import SwiftUI


// MARK: - AI Proxy Service
final class AIProxyService {
    // MARK: - Properties
    private let openAIService: OpenAIService

    // Singleton instance for easy access
    static let shared = AIProxyService()

    // MARK: - Initialization
    init() {
        self.openAIService = AIProxy.openAIService(
            partialKey: "v2|feef4cd4|k3bJw_-iBG5958LZ",
            serviceURL: "https://api.aiproxy.pro/4b571ffb/5b899002"
        )

        #if DEBUG
        print("🤖 AIProxyService: Initializing")
        #endif
    }

    // MARK: - Public Methods
    func generateCompletion(prompt: String) async throws -> String {
        #if DEBUG
        print("🤖 AIProxyService: Generating completion for prompt length: \(prompt.count)")
        #endif

        do {
            let response = try await openAIService.chatCompletionRequest(body: .init(
                model: "gpt-4.1",
                messages: [
                    .system(content: .text("You are Study‑Note‑GPT. Your mission: convert any transcript into clear, well‑structured Markdown notes that help the reader master the material via the Feynman technique.")),
                    .user(content: .text(prompt))
                ]
            ))

            guard let content = response.choices.first?.message.content else {
                #if DEBUG
                print("🤖 AIProxyService: Invalid response - no content in choices")
                #endif
                throw AIProxyError.invalidResponse
            }

            #if DEBUG
            print("🤖 AIProxyService: Successfully received response")
            #endif

            return content
        } catch {
            #if DEBUG
            print("🤖 AIProxyService: Request failed - \(error)")
            #endif
            throw AIProxyError.apiError(error.localizedDescription)
        }
    }

    /// Generate flashcards from note content
    /// - Parameters:
    ///   - content: The note content to generate flashcards from
    ///   - title: The title of the note
    ///   - count: The minimum number of flashcards to generate (default is 15)
    /// - Returns: An array of flashcard pairs (front, back)
    func generateFlashcards(from content: String, title: String, count: Int = 15) async throws -> [(front: String, back: String)] {
        #if DEBUG
        print("🤖 AIProxyService: Generating flashcards (min: \(count)) for note: \(title)")
        #endif

        // Create a prompt for flashcard generation
        let prompt = """
        Generate between \(count) and 25 educational flashcards from the following note content.
        You decide the exact number based on the richness and complexity of the content, but don't generate fewer than \(count) cards.

        Each flashcard should have a question on the front and an answer on the back.
        Create diverse types of cards including:
        1. Term-definition pairs
        2. Fill-in-the-blank questions
        3. Concept explanation questions
        4. Application questions
        5. Comparison questions

        Format your response as a JSON array of objects with "front" and "back" properties.
        Keep the front side concise (under 100 characters if possible).
        Keep the back side clear and informative (under 200 characters if possible).

        Note Title: \(title)
        Note Content: \(content)

        Return ONLY valid JSON in this format:
        [
          {"front": "Question 1?", "back": "Answer 1"},
          {"front": "Question 2?", "back": "Answer 2"},
          ...
        ]
        """

        // Get the completion from the AI service
        let jsonResponse = try await generateCompletion(prompt: prompt)

        // Parse the JSON response
        return try parseFlashcardsFromJSON(jsonResponse)
    }

    /// Generate quiz questions from note content
    /// - Parameters:
    ///   - content: The note content to generate quiz questions from
    ///   - title: The title of the note
    ///   - count: The minimum number of quiz questions to generate (default is 15)
    /// - Returns: An array of quiz questions with options, correct answers, and explanations
    func generateQuizQuestions(from content: String, title: String, count: Int = 15) async throws -> [QuizQuestion] {
        #if DEBUG
        print("🤖 AIProxyService: Generating quiz questions (min: \(count)) for note: \(title)")
        #endif

        // Create a prompt for quiz question generation
        let prompt = """
        Generate between \(count) and 20 educational multiple-choice quiz questions from the following note content.
        You decide the exact number based on the richness and complexity of the content, but don't generate fewer than \(count) questions.

        Create diverse types of questions including:
        1. Factual recall questions
        2. Conceptual understanding questions
        3. Application questions
        4. Analysis questions
        5. Evaluation questions

        IMPORTANT GUIDELINES FOR DIVERSITY:
        - Ensure questions cover different parts of the content, not just the beginning
        - Make sure correct answers are substantially different from each other
        - Avoid creating multiple questions that test the same concept
        - Use different question formats (what, why, how, which, etc.)
        - Include questions at different difficulty levels

        Each question must have:
        - A clear question statement
        - Exactly 4 answer options (A, B, C, D)
        - One correct answer (indicated by the correctAnswer field)
        - A brief explanation of why the correct answer is right

        IMPORTANT: Vary the position of the correct answer. Don't always put it in the same position (e.g., don't always make index 0 the correct answer). Distribute correct answers randomly among all four positions.

        Format your response as a JSON array of objects with these properties:
        - "question": The question text
        - "options": An array of 4 possible answers
        - "correctAnswer": The index of the correct answer (0-3)
        - "explanation": A brief explanation of the correct answer

        Note Title: \(title)
        Note Content: \(content)

        Return ONLY valid JSON in this format:
        [
          {
            "question": "What is the main concept discussed in the note?",
            "options": ["Option A", "Option B", "Option C", "Option D"],
            "correctAnswer": 2,
            "explanation": "Option C is correct because..."
          },
          ...
        ]
        """

        // Get the completion from the AI service
        let jsonResponse = try await generateCompletion(prompt: prompt)

        // Parse the JSON response
        return try parseQuizQuestionsFromJSON(jsonResponse)
    }

    /// Transcribe audio file using OpenAI's Whisper model
    /// - Parameters:
    ///   - fileURL: URL to the audio file
    ///   - language: Optional language code to guide the transcription (e.g., "en", "es")
    /// - Returns: Transcribed text
    func transcribeAudio(fileURL: URL, language: String? = nil) async throws -> String {
        #if DEBUG
        print("🤖 AIProxyService: Transcribing audio file: \(fileURL.lastPathComponent)")
        #endif

        do {
            // Read file data
            let audioData = try Data(contentsOf: fileURL)

            // Create the audio transcription request
            let requestBody = OpenAICreateTranscriptionRequestBody(
                file: audioData,
                model: "whisper-1",
                language: language
            )

            let response = try await openAIService.createTranscriptionRequest(body: requestBody)

            // Check if we have a valid response with text
            let transcription = response.text
            if transcription.isEmpty {
                #if DEBUG
                print("🤖 AIProxyService: Invalid transcription response - empty text")
                #endif
                throw AIProxyError.invalidResponse
            }

            #if DEBUG
            print("🤖 AIProxyService: Successfully transcribed audio (\(transcription.count) characters)")
            #endif

            return transcription
        } catch {
            #if DEBUG
            print("🤖 AIProxyService: Audio transcription failed - \(error)")
            #endif

            if let aiProxyError = error as? AIProxyError {
                throw aiProxyError
            } else {
                throw AIProxyError.audioTranscriptionError(error.localizedDescription)
            }
        }
    }

    // MARK: - Private Methods

    /// Parse flashcards from JSON string
    private func parseFlashcardsFromJSON(_ jsonString: String) throws -> [(front: String, back: String)] {
        // Clean up the JSON string (sometimes AI adds markdown code blocks)
        let cleanedJSON = jsonString
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleanedJSON.data(using: .utf8) else {
            throw AIProxyError.invalidResponseData
        }

        // Try to parse as a direct array of flashcards
        if let flashcardsArray = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
            return try parseFlashcardsArray(flashcardsArray)
        }

        // Try to parse as a JSON object with a "flashcards" array
        if let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let flashcardsArray = jsonObject["flashcards"] as? [[String: Any]] {
            return try parseFlashcardsArray(flashcardsArray)
        }

        throw AIProxyError.invalidResponseFormat
    }

    /// Parse flashcards from array
    private func parseFlashcardsArray(_ array: [[String: Any]]) throws -> [(front: String, back: String)] {
        return try array.compactMap { flashcard in
            guard let front = flashcard["front"] as? String,
                  let back = flashcard["back"] as? String else {
                throw AIProxyError.invalidFlashcardFormat
            }
            return (front: front, back: back)
        }
    }

    /// Parse quiz questions from JSON string
    private func parseQuizQuestionsFromJSON(_ jsonString: String) throws -> [QuizQuestion] {
        // Clean up the JSON string (sometimes AI adds markdown code blocks)
        let cleanedJSON = jsonString
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleanedJSON.data(using: .utf8) else {
            throw AIProxyError.invalidResponseData
        }

        // Try to parse as a direct array of quiz questions
        if let questionsArray = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
            return try parseQuizQuestionsArray(questionsArray)
        }

        // Try to parse as a JSON object with a "questions" array
        if let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let questionsArray = jsonObject["questions"] as? [[String: Any]] {
            return try parseQuizQuestionsArray(questionsArray)
        }

        throw AIProxyError.invalidResponseFormat
    }

    /// Parse quiz questions from array
    private func parseQuizQuestionsArray(_ array: [[String: Any]]) throws -> [QuizQuestion] {
        return try array.compactMap { questionData in
            guard let question = questionData["question"] as? String,
                  let options = questionData["options"] as? [String],
                  let correctAnswer = questionData["correctAnswer"] as? Int,
                  options.count == 4,
                  correctAnswer >= 0 && correctAnswer < options.count else {
                throw AIProxyError.invalidQuizQuestionFormat
            }

            // Explanation is optional
            let explanation = questionData["explanation"] as? String

            return QuizQuestion(
                question: question,
                options: options,
                correctAnswer: correctAnswer,
                explanation: explanation
            )
        }
    }
}

// MARK: - AI Proxy Error
enum AIProxyError: Error {
    case invalidResponse
    case apiError(String)
    case invalidResponseFormat
    case invalidResponseData
    case invalidFlashcardFormat
    case invalidQuizQuestionFormat
    case audioTranscriptionError(String)
}

extension AIProxyError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .apiError(let message):
            return "API error: \(message)"
        case .invalidResponseFormat:
            return "Invalid response format"
        case .invalidResponseData:
            return "Invalid response data"
        case .invalidFlashcardFormat:
            return "Invalid flashcard format in response"
        case .invalidQuizQuestionFormat:
            return "Invalid quiz question format in response"
        case .audioTranscriptionError(let message):
            return "Audio transcription error: \(message)"
        }
    }
}
