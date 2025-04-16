import SwiftUI
import Combine
import AIProxy

// MARK: - Chat View Model
@MainActor
final class ChatViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var messages: [ChatMessage] = []
    @Published var inputMessage: String = ""
    @Published var chatState: ChatState = .idle
    @Published var error: String?
    
    // MARK: - Private Properties
    private let note: NoteCardConfiguration
    private var cancellables = Set<AnyCancellable>()
    
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
        
        // Update chat state
        chatState = .processing
        
        do {
            // Get AI response
            let response = try await generateResponse(to: userInput)
            
            // Update user message status
            if let index = messages.firstIndex(where: { $0.id == userMessage.id }) {
                messages[index].status = .sent
            }
            
            // Add AI response
            let assistantMessage = ChatMessage(
                content: response,
                type: .assistant,
                timestamp: Date()
            )
            messages.append(assistantMessage)
            
            // Reset chat state
            chatState = .idle
            error = nil
            
            #if DEBUG
            print("💬 ChatViewModel: Received response from AI")
            #endif
        } catch {
            // Update user message status
            if let index = messages.firstIndex(where: { $0.id == userMessage.id }) {
                messages[index].status = .failed(error)
            }
            
            // Update chat state
            chatState = .error(error.localizedDescription)
            self.error = error.localizedDescription
            
            #if DEBUG
            print("💬 ChatViewModel: Error getting response - \(error.localizedDescription)")
            #endif
        }
    }
    
    // MARK: - Private Methods
    
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
        Use examples and analogies when appropriate to aid understanding.
        """
        
        // Get response from AI service
        return try await AIProxyService.shared.generateCompletion(prompt: prompt)
    }
    
    // MARK: - Cleanup
    deinit {
        #if DEBUG
        print("💬 ChatViewModel: Deinitializing")
        #endif
        cancellables.forEach { $0.cancel() }
    }
}
