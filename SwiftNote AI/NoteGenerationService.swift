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
        Please analyze this transcript and create a well-structured detailed note using proper markdown formatting:
        
        Add 1-2 table into different section of the note if anything can be represented better in table. Notes are always between summary and conclusion sections.
        No need another header before summary. If you have to use ##

        ## Summary
        Create a detailed summary with a couple of paragraphs.

        ## Key Points
        - Use bullet points for key points. 

        ## Important Details (with custom header)
        as many topic as you need with the topic format below
        
        ### Topic
        Content for topic

        ## Notable Quotes (only impactful and important ones, 
        > Include quotes if any

        ## Conclusion
        Detailed conclusion based on the whole content with a couple of paragraph.

        Use proper markdown formatting:
        1. Use ## for main headers
        2. Use ### for subheaders
        3. Use proper table formatting with | and -
        4. Use > for quotes
        5. Use - for bullet points
        6. Use ` for code or technical terms
        7. Use ** for emphasis
        
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
                model: "o3-mini",
                messages: [
                    .system(content: .text("You are a helpful assistant that creates well-structured and detailed notes from the provided content. The notes will be used to study with feynman technique.")),
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
