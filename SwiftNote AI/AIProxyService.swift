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
                    .system(content: .text("You are a helpful assistant that creates educational content.")),
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
}

// MARK: - AI Proxy Error
enum AIProxyError: Error {
    case invalidResponse
    case apiError(String)
    case invalidResponseFormat
    case invalidResponseData
    case invalidFlashcardFormat
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
        }
    }
}
