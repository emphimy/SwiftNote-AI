import SwiftUI
import CoreData
import AVKit
import Combine

// MARK: - Tab Models
enum StudyTab: String, CaseIterable {
    case read = "Read"
    case transcript = "Transcript"
    case quiz = "Quiz"
    case flashcards = "Flashcards"
    case chat = "Chat"
    
    var icon: String {
        switch self {
        case .read: return "doc.text"
        case .transcript: return "text.quote"
        case .quiz: return "checkmark.circle"
        case .flashcards: return "rectangle.stack"
        case .chat: return "bubble.left.and.bubble.right"
        }
    }
}

// MARK: - Study Tab Container
struct NoteStudyTabs: View {
    @State private var selectedTab: StudyTab = .read
    let note: NoteCardConfiguration
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab Bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.md) {
                    ForEach(StudyTab.allCases, id: \.self) { tab in
                        TabButton(
                            title: tab.rawValue,
                            icon: tab.icon,
                            isSelected: selectedTab == tab
                        ) {
                            withAnimation(.spring(response: 0.3)) {
                                selectedTab = tab
                                #if DEBUG
                                print("📚 NoteStudyTabs: Tab selected - \(tab)")
                                #endif
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
            }
            .background(Theme.Colors.secondaryBackground)
            .cornerRadius(Theme.Layout.cornerRadius)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            
            // Content Area
            Group {
                switch selectedTab {
                case .read:
                    ReadTabView(note: note)
                        .onAppear {
                            #if DEBUG
                            print("📚 NoteStudyTabs: Switched to Read tab")
                            #endif
                        }
                case .transcript:
                    TranscriptTabView(note: note)
                        .onAppear {
                            #if DEBUG
                            print("📚 NoteStudyTabs: Switched to Transcript tab")
                            #endif
                        }
                case .quiz:
                    QuizTabView(note: note)
                        .onAppear {
                            #if DEBUG
                            print("📚 NoteStudyTabs: Switched to Quiz tab")
                            #endif
                        }
                case .flashcards:
                    FlashcardsTabView(note: note)
                        .onAppear {
                            #if DEBUG
                            print("📚 NoteStudyTabs: Switched to Flashcards tab")
                            #endif
                        }
                case .chat:
                    ChatTabView(note: note)
                        .onAppear {
                            #if DEBUG
                            print("📚 NoteStudyTabs: Switched to Chat tab")
                            #endif
                        }
                }
            }
        }
        .onAppear {
            #if DEBUG
            print("📚 NoteStudyTabs: View appeared - Initial tab: \(selectedTab)")
            #endif
        }
    }
}

// MARK: - Tab Button
private struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            #if DEBUG
            print("📚 TabButton: Tapped - \(title)")
            #endif
            action()
        }) {
            VStack(spacing: Theme.Spacing.xxs) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? Theme.Colors.primary : Theme.Colors.secondaryText)
                
                Text(title)
                    .font(Theme.Typography.caption)
                    .foregroundColor(isSelected ? Theme.Colors.primary : Theme.Colors.secondaryText)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius)
                    .fill(isSelected ? Theme.Colors.primary.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Read Tab View
struct ReadTabView: View {
    let note: NoteCardConfiguration
    @StateObject private var viewModel: ReadTabViewModel
    
    init(note: NoteCardConfiguration) {
        self.note = note
        self._viewModel = StateObject(wrappedValue: ReadTabViewModel(note: note))
        
        #if DEBUG
        print("📖 ReadTabView: Initializing with note: \(note.title)")
        #endif
    }
    
    var body: some View {
        ScrollView {
            if viewModel.isLoading {
                LoadingIndicator(message: "Loading content...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 100)
            } else if let error = viewModel.errorMessage {
                ErrorView(
                    error: NSError(
                        domain: "ReadTab",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: error]
                    )
                ) {
                    #if DEBUG
                    print("📖 ReadTabView: Retrying content load")
                    #endif
                    Task {
                        await viewModel.loadContent()
                    }
                }
                .padding()
            } else if let content = viewModel.content {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    ForEach(content.formattedContent) { block in
                        ContentBlockView(block: block, fontSize: viewModel.textSize)
                    }
                }
                .padding()
            } else {
                Text("No content available")
                    .foregroundColor(Theme.Colors.secondaryText)
                    .padding()
            }
        }
        .task {
            #if DEBUG
            print("📖 ReadTabView: Loading content on appear")
            #endif
            await viewModel.loadContent()
        }
    }
}

// MARK: - Flashcards Tab View
struct FlashcardsTabView: View {
    @StateObject private var viewModel: FlashcardsViewModel = FlashcardsViewModel()
    let note: NoteCardConfiguration
    
    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            if viewModel.isLoading {
                LoadingIndicator(message: "Generating flashcards...")
            } else {
                NoteCardConfiguration.FlashcardContent(
                    flashcards: viewModel.flashcards
                )
            }
        }
        .padding()
        .task {
            #if DEBUG
            print("🎴 FlashcardsTab: Generating flashcards for note: \(note.title)")
            #endif
            await viewModel.generateFlashcards(from: note)
        }
    }
}

// MARK: - Chat Tab View
struct ChatTabView: View {
    let note: NoteCardConfiguration
    @State private var message = ""
    @State private var messages: [ChatMessage] = []
    @State private var chatState: ChatState = .idle
    
    var body: some View {
        VStack(spacing: 0) {
            // Chat Messages
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.sm) {
                    ForEach(messages) { message in
                        ChatMessageBubble(message: message)
                    }
                }
                .padding()
            }
            
            // Input Bar
            HStack(spacing: Theme.Spacing.sm) {
                TextField("Ask a question...", text: $message)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(Theme.Colors.primary)
                }
                .disabled(message.isEmpty || chatState.isProcessing)
            }
            .padding()
            .background(Theme.Colors.secondaryBackground)
        }
        .onAppear {
            #if DEBUG
            print("💬 ChatTab: View appeared for note: \(note.title)")
            #endif
        }
    }
    
    private func sendMessage() {
        #if DEBUG
        print("💬 ChatTab: Sending message: \(message)")
        #endif
        
        // Add user message
        let userMessage = ChatMessage(
            content: message,
            type: .user,
            timestamp: Date()
        )
        messages.append(userMessage)
        message = ""
        
        // Simulate AI response
        chatState = .processing
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let response = ChatMessage(
                content: "This is a simulated response. AI chat functionality will be implemented later.",
                type: .assistant,
                timestamp: Date()
            )
            messages.append(response)
            chatState = .idle
            
            #if DEBUG
            print("💬 ChatTab: Received response")
            #endif
        }
    }
}

// MARK: - Chat Message Bubble
private struct ChatMessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.type == .assistant {
                Spacer()
            }
            
            Text(message.content)
                .padding()
                .background(
                    message.type == .user ? Theme.Colors.primary : Theme.Colors.secondaryBackground
                )
                .foregroundColor(
                    message.type == .user ? .white : Theme.Colors.text
                )
                .cornerRadius(Theme.Layout.cornerRadius)
            
            if message.type == .user {
                Spacer()
            }
        }
    }
}

// MARK: - Content Block View
private struct ContentBlockView: View {
    let block: ContentBlock
    let fontSize: CGFloat
    
    var body: some View {
        switch block.type {
        case .heading1:
            Text(block.content)
                .font(.system(size: fontSize + 8, weight: .bold))
        case .heading2:
            Text(block.content)
                .font(.system(size: fontSize + 4, weight: .semibold))
        case .paragraph:
            Text(block.content)
                .font(.system(size: fontSize))
        case .bulletList:
            HStack(alignment: .top) {
                Text("•")
                Text(block.content)
            }
            .font(.system(size: fontSize))
        case .numberedList:
            Text(block.content)
                .font(.system(size: fontSize))
        case .codeBlock(let language):
            VStack(alignment: .leading) {
                if let language = language {
                    Text(language)
                        .font(.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
                Text(block.content)
                    .font(.system(size: fontSize, design: .monospaced))
            }
            .padding()
            .background(Theme.Colors.secondaryBackground)
            .cornerRadius(Theme.Layout.cornerRadius)
        case .quote:
            Text(block.content)
                .font(.system(size: fontSize, weight: .regular, design: .serif))
                .italic()
                .padding(.leading)
        }
    }
}

// MARK: - Transcript Tab View
struct TranscriptTabView: View {
    let note: NoteCardConfiguration
    @StateObject private var viewModel: TranscriptViewModel
    
    init(note: NoteCardConfiguration) {
        self.note = note
        self._viewModel = StateObject(wrappedValue: TranscriptViewModel(note: note))
    }
    
    var body: some View {
        ScrollView {
            if viewModel.isLoading {
                LoadingIndicator(message: "Loading transcript...")
            } else if let error = viewModel.errorMessage {
                ErrorView(
                    error: NSError(
                        domain: "TranscriptTab",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: error]
                    )
                ) {
                    Task {
                        await viewModel.loadTranscript()
                    }
                }
                .padding()
            } else if let transcript = viewModel.transcript {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(transcript.components(separatedBy: "\n\n"), id: \.self) { paragraph in
                        if !paragraph.isEmpty {
                            if let timeRange = paragraph.range(of: "\\[\\d{2}:\\d{2}\\]", options: [.regularExpression]) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(String(paragraph[timeRange]))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Text(String(paragraph[paragraph.index(after: timeRange.upperBound)...])
                                        .trimmingCharacters(in: CharacterSet.whitespaces))
                                        .font(.body)
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
        }
        .task {
            await viewModel.loadTranscript()
        }
    }
}
