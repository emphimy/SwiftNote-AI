import SwiftUI
import Combine
import AIProxy
import Down

// MARK: - Chat View Model
@MainActor
final class ChatViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var messages: [ChatMessage] = []
    @Published var inputMessage: String = ""
    @Published var chatState: ChatState = .idle
    @Published var error: String?
    @Published var typingMessage: String = ""
    @Published var isTyping: Bool = false

    // MARK: - Private Properties
    private let note: NoteCardConfiguration
    private var cancellables = Set<AnyCancellable>()
    private var typingTimer: Timer?
    private var fullResponse: String = ""
    private let typingDuration: TimeInterval = 1.5 // Duration to show typing indicator before showing response

    // MARK: - Initialization
    init(note: NoteCardConfiguration) {
        self.note = note

        #if DEBUG
        print("💬 ChatViewModel: Initializing for note: \(note.title)")
        #endif

        // Add initial welcome message
        let welcomeMessage = ChatMessage(
            content: "Hello! I'm your AI study assistant. Ask me anything about \"\(note.title)\" and I'll help you understand the material better.",
            type: .assistant,
            timestamp: Date()
        )
        messages.append(welcomeMessage)
    }

    // MARK: - Public Methods

    /// Send a message to the AI assistant
    func sendMessage() async {
        guard !inputMessage.isEmpty else {
            #if DEBUG
            print("💬 ChatViewModel: Empty message, not sending")
            #endif
            return
        }

        let userMessage = ChatMessage(
            content: inputMessage,
            type: .user,
            timestamp: Date(),
            status: .sending
        )

        // Add user message to the chat
        messages.append(userMessage)

        // Clear input field
        let userInput = inputMessage
        inputMessage = ""

        // Update chat state and immediately show typing indicator
        chatState = .processing
        isTyping = true // Start typing animation immediately
        typingMessage = "" // Empty message will show the animated dots

        // Get AI response in the background
        Task {
            do {
                let response = try await generateResponse(to: userInput)

                // Update user message status
                if let index = self.messages.firstIndex(where: { $0.id == userMessage.id }) {
                    self.messages[index].status = .sent
                }

                // Store the full response and start timer for showing it
                self.fullResponse = response

                // Create a timer to show the response after a short delay
                self.typingTimer = Timer.scheduledTimer(withTimeInterval: self.typingDuration, repeats: false) { [weak self] timer in
                    guard let self = self else {
                        timer.invalidate()
                        return
                    }

                    Task { @MainActor in
                        // Typing finished, add the complete message
                        self.finishTypingAnimation()
                        timer.invalidate()
                    }
                }

                #if DEBUG
                print("💬 ChatViewModel: Received response from AI")
                #endif
            } catch {
                // Update user message status
                if let index = self.messages.firstIndex(where: { $0.id == userMessage.id }) {
                    self.messages[index].status = .failed(error)
                }

                // Update chat state
                self.chatState = .error(error.localizedDescription)
                self.error = error.localizedDescription
                self.isTyping = false // Stop typing animation on error

                #if DEBUG
                print("💬 ChatViewModel: Error getting response - \(error.localizedDescription)")
                #endif
            }
        }
    }

    /// Stop the current AI response generation and typing animation
    func stopResponse() {
        // Stop the typing animation
        typingTimer?.invalidate()
        typingTimer = nil

        // If we were in the middle of typing, add a message indicating the response was stopped
        if isTyping {
            let partialMessage = ChatMessage(
                content: "[Response stopped by user]",
                type: .assistant,
                timestamp: Date()
            )
            messages.append(partialMessage)
        }

        // Reset typing state
        isTyping = false
        typingMessage = ""
        fullResponse = ""

        // Reset chat state
        chatState = .idle
        error = nil
    }

    // MARK: - Private Methods

    /// Finish the typing animation and add the complete message
    private func finishTypingAnimation() {
        // Add AI response with the full text
        let assistantMessage = ChatMessage(
            content: fullResponse,
            type: .assistant,
            timestamp: Date()
        )
        messages.append(assistantMessage)

        // Reset typing state
        isTyping = false
        typingMessage = ""

        // Reset chat state
        chatState = .idle
        error = nil
    }

    /// Generate an AI response based on the user message and note content
    private func generateResponse(to message: String) async throws -> String {
        #if DEBUG
        print("💬 ChatViewModel: Generating response to: \(message)")
        #endif

        // Create prompt with context from the note
        let prompt = """
        You are an AI study assistant helping a student understand the following note:

        Title: \(note.title)

        Content:
        \(note.preview)

        The student asks: \(message)

        Provide a helpful, educational response that helps the student understand the material better.
        Your response should be clear, concise, and focused on the student's question.
        If the question is not related to the note content, gently guide the student back to the topic.

        IMPORTANT: Keep your responses SHORT and FOCUSED. Aim for 1-4 sentences maximum unless the question absolutely requires more detail.

        You can use Markdown formatting in your response:
        - Use **bold** for emphasis
        - Use *italic* for definitions or important terms
        - Use bullet points or numbered lists for steps or multiple points
        - Use headings with # or ## for organizing your response
        - Use code blocks with ``` for code examples if relevant
        - Use paragraph breaks when needed

        """

        // Get response from AI service
        return try await AIProxyService.shared.generateCompletion(prompt: prompt)
    }

    /// Parse markdown content to attributed string
    func parseMarkdown(_ markdownText: String) -> AttributedString {
        var attributedString = AttributedString(markdownText)

        // Simple markdown formatting
        do {
            // Bold text
            let boldPattern = try NSRegularExpression(pattern: "\\*\\*(.*?)\\*\\*", options: [])
            let boldMatches = boldPattern.matches(in: markdownText, options: [], range: NSRange(location: 0, length: markdownText.utf16.count))

            for match in boldMatches.reversed() {
                if let range = Range(match.range(at: 1), in: markdownText) {
                    let boldText = String(markdownText[range])
                    if let attributedRange = attributedString.range(of: "**\(boldText)**") {
                        attributedString[attributedRange].font = .boldSystemFont(ofSize: UIFont.systemFontSize)
                        attributedString.replaceSubrange(attributedRange, with: AttributedString(boldText))
                    }
                }
            }

            // Italic text
            let italicPattern = try NSRegularExpression(pattern: "\\*(.*?)\\*", options: [])
            let italicMatches = italicPattern.matches(in: markdownText, options: [], range: NSRange(location: 0, length: markdownText.utf16.count))

            for match in italicMatches.reversed() {
                if let range = Range(match.range(at: 1), in: markdownText) {
                    let italicText = String(markdownText[range])
                    if let attributedRange = attributedString.range(of: "*\(italicText)*") {
                        attributedString[attributedRange].font = .italicSystemFont(ofSize: UIFont.systemFontSize)
                        attributedString.replaceSubrange(attributedRange, with: AttributedString(italicText))
                    }
                }
            }

            // Headings (H1, H2, H3)
            let headingPatterns = [
                (pattern: "^# (.*?)$", size: UIFont.systemFontSize * 1.5),
                (pattern: "^## (.*?)$", size: UIFont.systemFontSize * 1.3),
                (pattern: "^### (.*?)$", size: UIFont.systemFontSize * 1.1)
            ]

            for (pattern, size) in headingPatterns {
                let headingRegex = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
                let headingMatches = headingRegex.matches(in: markdownText, options: [], range: NSRange(location: 0, length: markdownText.utf16.count))

                for match in headingMatches.reversed() {
                    if let range = Range(match.range(at: 1), in: markdownText),
                       let fullRange = Range(match.range, in: markdownText) {
                        let headingText = String(markdownText[range])
                        let fullHeadingText = String(markdownText[fullRange])

                        if let attributedRange = attributedString.range(of: fullHeadingText) {
                            attributedString[attributedRange].font = .boldSystemFont(ofSize: size)
                            attributedString.replaceSubrange(attributedRange, with: AttributedString(headingText))
                        }
                    }
                }
            }
        } catch {
            #if DEBUG
            print("💬 ChatViewModel: Error parsing markdown - \(error)")
            #endif
        }

        return attributedString
    }

    // MARK: - Cleanup
    deinit {
        #if DEBUG
        print("💬 ChatViewModel: Deinitializing")
        #endif
        typingTimer?.invalidate()
        cancellables.forEach { $0.cancel() }
    }
}
