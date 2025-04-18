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

        let prompt = """
        Detect the language of the transcript and write EVERYTHING including headers in that language. Custoize the header names based on the topic. Do not use default names other than Summary and Conclusion

        ## Summary
        Give a 2‑paragraph overview (≤120 words total).

        ## Key Points
        - List the 6–10 most important takeaways.

        ## Important Details
        For each major theme you find (create as many as needed):

        ### <Theme Name>
        - Bullet details (max 25 words each).
        💡 **SwiftNote Simplification:**
        One short paragraph that explains the theme in plain language to a novice.

        ## Notable Quotes
        > Include only impactful quotations. Omit this section if none.

        ## Tables
        Add up to **two** tables **only if** dates, stats, steps, or comparisons are clearer that way. Otherwise omit this section.

        ## Conclusion
        Wrap up in 1‑2 paragraphs, linking back to the Key Points.

        ### Style Rules
        1. `##` for main headers, `###` for sub‑headers  
        2. Bullets with `-`  
        3. Tables with `|` and `-`  
        4. Inline code/terms with back‑ticks  
        5. Bold sparingly for emphasis  
        6. Never invent facts not in the transcript  
        7. Output **only** Markdown—no extra commentary

        TRANSCRIPT (do not modify):
        ```text
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
                model: "gpt-4.1",
                messages: [
                    .system(content: .text("You are Study‑Note‑GPT. Your mission: convert any transcript into clear, well‑structured Markdown notes that help the reader master the material via the Feynman technique.")),
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

        } catch AIProxyError.apiError(let message) {
            #if DEBUG
            print("🤖 NoteGeneration: Request failed - \(message)")
            #endif
            throw NoteGenerationError.apiError(message)
        } catch {
            #if DEBUG
            print("🤖 NoteGeneration: Request failed - \(error)")
            #endif
            throw NoteGenerationError.apiError(error.localizedDescription)
        }
    }
}
