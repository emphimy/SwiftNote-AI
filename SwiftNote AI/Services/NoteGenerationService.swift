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
        if let language = detectedLanguage {
            print("🤖 NoteGenerationService: Using specified language: \(language)")
        }
        #endif

        // Language instruction based on whether a language was specified
        let languageInstruction = detectedLanguage != nil ?
            "Write ALL output—including headers—in \(detectedLanguage!) language." :
            "Detect the language of the transcript and write ALL output—including headers—in that language."

        let prompt = """
        \(languageInstruction)

        **###** 💡 1 Paragraph Simplification
        One plain‑language paragraph that could be read to a novice.

        ## Introduction
        Give a 1‑paragraph introduction (≤60 words total).

        For each major theme you find (create as many as needed):

        ### {{Theme Name}}
        Provide a concise discussion of this theme (≤60 words). Present narrative explanations in full paragraphs. Use bullet points **only** for:
        - Ordered sequences (1., 2., 3., …)
        - Lists of distinct items or features
        - Collections of unrelated facts

        Each theme should be formatted entirely as a paragraph or entirely as bullets—never mix the two.

        If—and only if—information (dates, stats, comparisons, steps) would be clearer in a table, add up to 2 tables directly within the relevant theme sections. Do not create a separate "Tables" section.

        ## Conclusion
        Wrap up in 1 paragraph, linking back to the main takeaways.

        ### Style Rules
        1. Use **##** for main headers, **###** for sub‑headers.
        2. Bullet lists with **-**.
        3. Format tables with `|` and `-`.
        4. Inline code or technical terms with back‑ticks.
        5. Bold sparingly for emphasis.
        6. Never invent facts not present in the transcript.
        7. Output *only* Markdown—no explanations, no apologies.
        8. Do NOT use section headers like "Key Points", "Tables", or "Important Details".

        Transcript:
        \(transcript)
        """

        return try await makeRequest(prompt: prompt)
    }

    // MARK: - Streaming Note Generation
    func generateNoteWithProgress(
        from transcript: String,
        detectedLanguage: String? = nil,
        progressCallback: @escaping (Double) -> Void
    ) async throws -> String {
        guard !transcript.isEmpty else {
            throw NoteGenerationError.emptyTranscript
        }

        #if DEBUG
        print("🤖 NoteGenerationService: Generating note with progress from transcript of length: \(transcript.count)")
        if let language = detectedLanguage {
            print("🤖 NoteGenerationService: Using specified language: \(language)")
        }
        #endif

        // Language instruction based on whether a language was specified
        let languageInstruction = detectedLanguage != nil ?
            "Write ALL output—including headers—in \(detectedLanguage!) language." :
            "Detect the language of the transcript and write ALL output—including headers—in that language."

        let prompt = """
        \(languageInstruction)

        **###** 💡 1 Paragraph Simplification
        One plain‑language paragraph that could be read to a novice.

        ## Introduction
        Give a 1‑paragraph introduction (≤60 words total).

        For each major theme you find (create as many as needed):

        ### {{Theme Name}}
        Write in PARAGRAPH format. Use bullet points ONLY for:
        - Sequential steps (1, 2, 3...)
        - Lists of distinct items/features
        - Multiple unrelated facts
        Otherwise, use flowing paragraph text for all explanations and concepts
        - Either use paragraph format or bullet point format per theme
        - ≤60 words total per theme
        - Each NOTE should have at least 1 bullet points theme and 1 numbered theme.

        If—and only if—information (dates, stats, comparisons, steps) would be clearer in a table, add up to 2 tables directly within the relevant theme sections. Do not create a separate "Tables" section.

        ## Conclusion
        Wrap up in 1 paragraph, linking back to the main takeaways.

        ### Style Rules
        1. Use **##** for main headers, **###** for sub‑headers.
        2. Bullet lists with **-**.
        3. Format tables with `|` and `-`.
        4. Inline code or technical terms with back‑ticks.
        5. Bold sparingly for emphasis.
        6. Never invent facts not present in the transcript.
        7. Output *only* Markdown—no explanations, no apologies.
        8. Do NOT use section headers like "Key Points", "Tables", or "Important Details".

        Transcript:
        \(transcript)
        """

        return try await makeStreamingRequest(prompt: prompt, progressCallback: progressCallback)
    }

    func generateTitle(from transcript: String, detectedLanguage: String? = nil) async throws -> String {
        guard !transcript.isEmpty else {
            throw NoteGenerationError.emptyTranscript
        }

        #if DEBUG
        if let language = detectedLanguage {
            print("🤖 NoteGenerationService: Generating title using language: \(language)")
        }
        #endif

        let languagePrompt = detectedLanguage != nil ? "Generate the title in \(detectedLanguage!) language." : "Detect the language of the transcript and generate the title in that same language."

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

    // MARK: - Streaming Title Generation
    func generateTitleWithProgress(
        from transcript: String,
        detectedLanguage: String? = nil,
        progressCallback: @escaping (Double) -> Void
    ) async throws -> String {
        guard !transcript.isEmpty else {
            throw NoteGenerationError.emptyTranscript
        }

        #if DEBUG
        print("🤖 NoteGenerationService: Generating title with progress from transcript of length: \(transcript.count)")
        if let language = detectedLanguage {
            print("🤖 NoteGenerationService: Using specified language: \(language)")
        }
        #endif

        let languagePrompt = detectedLanguage != nil ? "Generate the title in \(detectedLanguage!) language." : "Detect the language of the transcript and generate the title in that same language."

        let prompt = """
        Based on this transcript, generate a concise but descriptive title (maximum 60 characters) that captures the main topic or theme.
        The title should be clear and informative, avoiding generic phrases.
        \(languagePrompt)

        Transcript:
        \(transcript)

        Generate only the title, nothing else.
        """

        let response = try await makeStreamingRequest(prompt: prompt, progressCallback: progressCallback)
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
                    .system(content: .text("You are Study‑Note‑GPT. Your mission: turn any transcript into clear, well‑structured Markdown notes that help the reader **master** the material using the Feynman technique (teach it back in simple language).")),
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

    private func makeStreamingRequest(
        prompt: String,
        progressCallback: @escaping (Double) -> Void
    ) async throws -> String {
        guard !prompt.isEmpty else {
            #if DEBUG
            print("🤖 NoteGeneration: Empty prompt provided")
            #endif
            throw NoteGenerationError.apiError("Empty prompt provided")
        }

        #if DEBUG
        print("🤖 NoteGeneration: Making streaming request with prompt length: \(prompt.count)")
        #endif

        do {
            let requestBody = OpenAIChatCompletionRequestBody(
                model: "gpt-4.1",
                messages: [
                    .system(content: .text("You are Study‑Note‑GPT. Your mission: turn any transcript into clear, well‑structured Markdown notes that help the reader **master** the material using the Feynman technique (teach it back in simple language).")),
                    .user(content: .text(prompt))
                ]
            )

            let stream = try await openAIService.streamingChatCompletionRequest(body: requestBody)

            var fullContent = ""
            var chunkCount = 0
            let estimatedTotalChunks = 150 // Rough estimate based on typical response length

            for try await chunk in stream {
                if let content = chunk.choices.first?.delta.content {
                    fullContent += content
                    chunkCount += 1

                    // Calculate progress based on chunks received
                    let progress = min(0.95, Double(chunkCount) / Double(estimatedTotalChunks))

                    await MainActor.run {
                        progressCallback(progress)
                    }

                    #if DEBUG
                    if chunkCount % 10 == 0 { // Log every 10th chunk to avoid spam
                        print("🤖 NoteGeneration: Received chunk \(chunkCount), progress: \(String(format: "%.1f", progress * 100))%")
                    }
                    #endif
                }
            }

            // Ensure we reach 100% at the end
            await MainActor.run {
                progressCallback(1.0)
            }

            guard !fullContent.isEmpty else {
                #if DEBUG
                print("🤖 NoteGeneration: Invalid streaming response - no content received")
                #endif
                throw NoteGenerationError.invalidResponse
            }

            #if DEBUG
            print("🤖 NoteGeneration: Successfully received streaming response with \(chunkCount) chunks")
            #endif

            return fullContent

        } catch AIProxyError.apiError(let message) {
            #if DEBUG
            print("🤖 NoteGeneration: Streaming request failed - \(message)")
            #endif
            throw NoteGenerationError.apiError(message)
        } catch {
            #if DEBUG
            print("🤖 NoteGeneration: Streaming request failed - \(error)")
            #endif
            throw NoteGenerationError.apiError(error.localizedDescription)
        }
    }
}
