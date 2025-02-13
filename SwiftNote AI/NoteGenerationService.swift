import Foundation
import AIProxy

// MARK: - Note Generation Error
enum NoteGenerationError: LocalizedError {
    case apiError(String)
    case invalidResponse
    case emptyTranscript
    
    var errorDescription: String? {
        switch self {
        case .apiError(let message):
            return "API Error: \(message)"
        case .invalidResponse:
            return "Invalid response from OpenAI"
        case .emptyTranscript:
            return "Empty transcript provided"
        }
    }
}

// MARK: - Note Generation Service
actor NoteGenerationService {

    private let openAIService: OpenAIService
    
    init() {
        self.openAIService = AIProxy.openAIService(
            partialKey: "v2|feef4cd4|k3bJw_-iBG5958LZ",
            serviceURL: "https://api.aiproxy.pro/4b571ffb/5b899002"
        )
        
        #if DEBUG
        print("🤖 NoteGeneration: Initializing service")
        #endif
    }
    
    func generateNote(from transcript: String, detectedLanguage: String? = nil) async throws -> String {
        guard !transcript.isEmpty else {
            throw NoteGenerationError.emptyTranscript
        }
        
        #if DEBUG
        print("🤖 NoteGenerationService: Generating note from transcript of length: \(transcript.count)")
        #endif
        
        let languagePrompt = detectedLanguage != nil ? "Generate the note in \(detectedLanguage!) language." : ""
        
        let prompt = """
        Please analyze this transcript and create a well-structured note with the following sections:
        1. Summary (2-3 sentences)
        2. Key Points (bullet points)
        3. Important Details (organized by topics)
        4. Notable Quotes (if any)
        
        Use Markdown formatting for better readability.
        \(languagePrompt)
        
        Transcript:
        \(transcript)
        """
        
        return try await makeRequest(prompt: prompt)
    }
    
    func generateTitle(from transcript: String, detectedLanguage: String? = nil) async throws -> String {
        guard !transcript.isEmpty else {
            throw NoteGenerationError.emptyTranscript
        }
        
        let languagePrompt = detectedLanguage != nil ? "Generate the title in \(detectedLanguage!) language." : ""
        
        let prompt = """
        Based on this transcript, generate a concise but descriptive title (maximum 60 characters) that captures the main topic or theme.
        The title should be clear and informative, avoiding generic phrases.
        \(languagePrompt)
        
        Transcript:
        \(transcript)
        
        Generate only the title, nothing else.
        """
        
        let response = try await makeRequest(prompt: prompt)
        // Clean up the response to ensure it's just the title
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Private Methods
    private func makeRequest(prompt: String) async throws -> String {
        guard !prompt.isEmpty else {
            #if DEBUG
            print("🤖 NoteGeneration: Empty prompt provided")
            #endif
            throw NoteGenerationError.apiError("Empty prompt provided")
        }

        #if DEBUG
        print("🤖 NoteGeneration: Making request with prompt length: \(prompt.count)")
        #endif

        do {
            let response = try await openAIService.chatCompletionRequest(body: .init(
                model: "gpt-4o-mini",
                messages: [
                    .system(content: .text("You are a helpful assistant that creates well-structured notes from transcripts.")),
                    .user(content: .text(prompt))
                ]
            ))
            
            guard let content = response.choices.first?.message.content else {
                #if DEBUG
                print("🤖 NoteGeneration: Invalid response - no content in choices")
                #endif
                throw NoteGenerationError.invalidResponse
            }

            #if DEBUG
            print("🤖 NoteGeneration: Successfully received response")
            #endif
            
            return content

        } catch AIProxyError.unsuccessfulRequest(let statusCode, let responseBody) {
            #if DEBUG
            print("🤖 NoteGeneration: Request failed with status code: \(statusCode), body: \(responseBody)")
            #endif
            throw NoteGenerationError.apiError("Request failed with status \(statusCode)")
        } catch {
            #if DEBUG
            print("🤖 NoteGeneration: Request failed - \(error)")
            #endif
            throw NoteGenerationError.apiError(error.localizedDescription)
        }
    }
}
