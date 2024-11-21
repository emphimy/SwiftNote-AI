import SwiftUI

// MARK: - Audio Type Check Extension
private extension NoteSourceType {
    var supportsAudio: Bool {
        switch self {
        case .audio: return true
        case .video: return true  // Videos also have audio
        case .text: return false
        case .upload: return false
        }
    }
}

// MARK: - Tab Models
enum StudyTab: String, CaseIterable {
    case listen = "Listen"
    case read = "Read"
    case quiz = "Quiz"
    case flashcards = "Flashcards"
    case chat = "Chat"
    
    var icon: String {
        switch self {
        case .listen: return "headphones"
        case .read: return "doc.text"
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
            // Custom Tab Bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.md) {
                    ForEach(StudyTab.allCases, id: \.self) { tab in
                        if tab != .listen || note.sourceType.supportsAudio {
                            TabButton(
                                title: tab.rawValue,
                                icon: tab.icon,
                                isSelected: selectedTab == tab
                            ) {
                                withAnimation(.spring(response: 0.3)) {
                                    selectedTab = tab
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
            }
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Colors.background)
            .standardShadow()
            
            // Tab Content
            TabView(selection: $selectedTab) {
                Group {
                    if note.sourceType.supportsAudio {
                        ListenTabView(note: note)
                            .tag(StudyTab.listen)
                    }
                    
                    ReadTabView(note: note)
                        .tag(StudyTab.read)
                    
                    QuizTabView(note: note)
                        .tag(StudyTab.quiz)
                    
                    FlashcardsTabView(note: note)
                        .tag(StudyTab.flashcards)
                    
                    ChatTabView(note: note)
                        .tag(StudyTab.chat)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
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
        Button(action: action) {
            VStack(spacing: Theme.Spacing.xxs) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                
                Text(title)
                    .font(Theme.Typography.caption)
            }
            .foregroundColor(isSelected ? Theme.Colors.primary : Theme.Colors.secondaryText)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius)
                    .fill(isSelected ? Theme.Colors.primary.opacity(0.1) : Color.clear)
            )
        }
    }
}

// MARK: - Listen Tab View
struct ListenTabView: View {
    let note: NoteCardConfiguration
    @StateObject private var viewModel = AudioPlayerViewModel()
    @StateObject private var transcriptViewModel = TranscriptViewModel()
    
    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            if note.sourceType.supportsAudio {
                if let audioURL = note.audioURL, FileManager.default.fileExists(atPath: audioURL.path) {
                    // MARK: - Audio Player Controls
                    AudioPlayerControls(
                        duration: viewModel.duration,
                        currentTime: Binding(
                            get: { viewModel.currentTime },
                            set: { viewModel.seek(to: $0) }
                        ),
                        isPlaying: Binding(
                            get: { viewModel.isPlaying },
                            set: { newValue in
                                #if DEBUG
                                print("🎵 ListenTabView: Playback state changed to \(newValue)")
                                #endif
                                if newValue {
                                    viewModel.play()
                                } else {
                                    viewModel.pause()
                                }
                            }
                        ),
                        playbackRate: $viewModel.playbackRate,
                        onSeek: { newTime in
                            #if DEBUG
                            print("🎵 ListenTabView: Seeking to time: \(newTime)")
                            #endif
                            viewModel.seek(to: newTime)
                        }
                    )
                    
                    // MARK: - Transcript Section
                    VStack(spacing: Theme.Spacing.lg) {
                        if note.sourceType.supportsAudio {
                            if let audioURL = note.audioURL {
                                // MARK: - Audio Player Controls
                                AudioPlayerControls(
                                    duration: viewModel.duration,
                                    currentTime: Binding(
                                        get: { viewModel.currentTime },
                                        set: { viewModel.seek(to: $0) }
                                    ),
                                    isPlaying: Binding(
                                        get: { viewModel.isPlaying },
                                        set: { newValue in
                                            #if DEBUG
                                            print("🎵 ListenTabView: Playback state changed to \(newValue)")
                                            #endif
                                            if newValue {
                                                viewModel.play()
                                            } else {
                                                viewModel.pause()
                                            }
                                        }
                                    ),
                                    playbackRate: $viewModel.playbackRate,
                                    onSeek: { newTime in
                                        #if DEBUG
                                        print("🎵 ListenTabView: Seeking to time: \(newTime)")
                                        #endif
                                        viewModel.seek(to: newTime)
                                    }
                                )
                                
                                // MARK: - Transcript Section
                                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                    Text("Transcript")
                                        .font(Theme.Typography.h3)
                                        .padding(.horizontal)
                                    
                                    switch transcriptViewModel.loadingState {
                                    case .loading(let message):
                                        LoadingIndicator(message: message)
                                            .padding()
                                        
                                    case .error(let message):
                                        ErrorView(
                                            error: NSError(
                                                domain: "Transcript",
                                                code: -1,
                                                userInfo: [NSLocalizedDescriptionKey: message]
                                            )
                                        ) {
                                            #if DEBUG
                                            print("🎵 ListenTabView: Retrying transcript generation")
                                            #endif
                                            Task {
                                                await transcriptViewModel.generateTranscript(for: audioURL)
                                            }
                                        }
                                        .padding()
                                        
                                    case .success(_):
                                        if transcriptViewModel.segments.isEmpty {
                                            EmptyStateView(
                                                icon: "text.quote",
                                                title: "No Transcript",
                                                message: "Tap to generate transcript for this audio.",
                                                actionTitle: "Generate Transcript"
                                            ) {
                                                #if DEBUG
                                                print("🎵 ListenTabView: Manual transcript generation requested")
                                                #endif
                                                Task {
                                                    await transcriptViewModel.generateTranscript(for: audioURL)
                                                }
                                            }
                                            .padding()
                                        } else {
                                            ScrollView {
                                                LazyVStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                                    ForEach(transcriptViewModel.segments) { segment in
                                                        TranscriptSegmentView(segment: segment) {
                                                            #if DEBUG
                                                            print("🎵 ListenTabView: Segment tapped at time: \(segment.startTime)")
                                                            #endif
                                                            let newTime = transcriptViewModel.seekToSegment(segment)
                                                            viewModel.seek(to: newTime)
                                                        }
                                                    }
                                                }
                                                .padding()
                                            }
                                        }
                                        
                                    case .idle:
                                        if transcriptViewModel.segments.isEmpty {
                                            EmptyStateView(
                                                icon: "text.quote",
                                                title: "No Transcript",
                                                message: "Tap to generate transcript for this audio.",
                                                actionTitle: "Generate Transcript"
                                            ) {
                                                #if DEBUG
                                                print("🎵 ListenTabView: Manual transcript generation requested")
                                                #endif
                                                Task {
                                                    await transcriptViewModel.generateTranscript(for: audioURL)
                                                }
                                            }
                                            .padding()
                                        } else {
                                            ScrollView {
                                                LazyVStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                                    ForEach(transcriptViewModel.segments) { segment in
                                                        TranscriptSegmentView(segment: segment) {
                                                            #if DEBUG
                                                            print("🎵 ListenTabView: Segment tapped at time: \(segment.startTime)")
                                                            #endif
                                                            let newTime = transcriptViewModel.seekToSegment(segment)
                                                            viewModel.seek(to: newTime)
                                                        }
                                                    }
                                                }
                                                .padding()
                                            }
                                        }
                                    }
                                }
                            } else {
                                // MARK: - Missing Audio Error
                                EmptyStateView(
                                    icon: "exclamationmark.triangle",
                                    title: "Audio Not Found",
                                    message: getErrorMessage(),
                                    actionTitle: "Refresh"
                                ) {
                                    #if DEBUG
                                    print("🎵 ListenTabView: Attempting to reload audio URL for type: \(note.sourceType)")
                                    #endif
                                    // Implement refresh logic if needed
                                }
                                .padding()
                            }
                        } else {
                            // MARK: - Unsupported Content Type
                            EmptyStateView(
                                icon: "speaker.slash",
                                title: "Audio Not Available",
                                message: "This \(note.sourceType == .text ? "text" : "uploaded") note doesn't contain any audio content."
                            )
                            .padding()
                        }
                    }
                } else {
                    // MARK: - Missing Audio Error
                    EmptyStateView(
                        icon: "exclamationmark.triangle",
                        title: "Audio Not Found",
                        message: getErrorMessage(),
                        actionTitle: "Refresh"
                    ) {
                        #if DEBUG
                        print("🎵 ListenTabView: Attempting to reload audio URL for type: \(note.sourceType)")
                        #endif
                        // Implement refresh logic if needed
                    }
                    .padding()
                }
            } else {
                // MARK: - Unsupported Content Type
                EmptyStateView(
                    icon: "speaker.slash",
                    title: "Audio Not Available",
                    message: "This \(note.sourceType == .text ? "text" : "uploaded") note doesn't contain any audio content."
                )
                .padding()
            }
        }
        .task {
            if let audioURL = note.audioURL {
                do {
                    #if DEBUG
                    print("🎵 ListenTabView: Loading audio from URL: \(audioURL)")
                    #endif
                    try await viewModel.loadAudio(from: audioURL)
                    await transcriptViewModel.generateTranscript(for: audioURL)
                } catch {
                    #if DEBUG
                    print("🎵 ListenTabView: Error loading audio - \(error.localizedDescription)")
                    #endif
                }
            }
        }
        .onChange(of: viewModel.currentTime) { newTime in
            #if DEBUG
            print("🎵 ListenTabView: Current time updated to: \(newTime)")
            #endif
            transcriptViewModel.currentTime = newTime
        }
    }
    
    // MARK: - Helper Functions
    private func getErrorMessage() -> String {
        #if DEBUG
        print("🎵 ListenTabView: Generating error message for source type: \(note.sourceType)")
        #endif
        
        switch note.sourceType {
        case .audio:
            return "The audio recording could not be found. The file may have been moved or deleted."
        case .video:
            return "The video's audio track could not be accessed. The file may be corrupted or in an unsupported format."
        case .text:
            return "No audio content is available for this text note."
        case .upload:
            return "No audio content is available for this uploaded note."
        }
    }
}
private struct TranscriptSegmentView: View {
    let segment: TranscriptSegment
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text(segment.text)
                .font(Theme.Typography.body)
                .foregroundColor(segment.isHighlighted ? Theme.Colors.primary : Theme.Colors.text)
                .padding(Theme.Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius)
                        .fill(segment.isHighlighted ? Theme.Colors.primary.opacity(0.1) : Color.clear)
                )
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
        _viewModel = StateObject(wrappedValue: ReadTabViewModel(note: note))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Controls Bar
            HStack {
                SearchBar(text: $viewModel.searchText)
                
                Button(action: { viewModel.adjustTextSize(-2) }) {
                    Image(systemName: "textformat.size.smaller")
                }
                
                Button(action: { viewModel.adjustTextSize(2) }) {
                    Image(systemName: "textformat.size.larger")
                }
            }
            .padding(.horizontal)
            
            // Content
            ScrollView {
                if viewModel.isLoading {
                    LoadingIndicator(message: "Loading content...")
                } else if let content = viewModel.content {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        ForEach(content.formattedContent) { block in
                            ContentBlockView(block: block, fontSize: viewModel.textSize)
                        }
                    }
                    .padding()
                }
            }
        }
        .task {
            await viewModel.loadContent()
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

// MARK: - Flashcards Tab View
struct FlashcardsTabView: View {
    let note: NoteCardConfiguration
    @StateObject private var viewModel = FlashcardsViewModel()
    
    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            if viewModel.isLoading {
                LoadingIndicator(message: "Generating flashcards...")
            } else if viewModel.flashcards.isEmpty {
                EmptyStateView(
                    icon: "rectangle.stack",
                    title: "No Flashcards Yet",
                    message: "Tap to generate flashcards from your note.",
                    actionTitle: "Generate Flashcards"
                ) {
                    viewModel.generateFlashcards(from: note)
                }
            } else {
                NoteCardConfiguration.FlashcardContent(flashcards: viewModel.flashcards)
            }
        }
        .padding()
    }
}

// MARK: - Chat Tab View
struct ChatTabView: View {
    let note: NoteCardConfiguration
    @StateObject private var viewModel = ChatViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Chat Messages
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.md) {
                    ForEach(viewModel.messages) { message in
                        ChatBubble(message: message)
                    }
                }
                .padding()
            }
            
            // Input Area
            HStack(spacing: Theme.Spacing.sm) {
                TextField("Ask a question...", text: $viewModel.inputText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .disabled(viewModel.isProcessing)
                
                Button(action: {
                    viewModel.sendMessage()
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(Theme.Colors.primary)
                }
                .disabled(viewModel.inputText.isEmpty || viewModel.isProcessing)
            }
            .padding()
            .background(Theme.Colors.background)
            .standardShadow()
        }
    }
}

private struct ChatBubble: View {
    let message: ChatViewModel.ChatMessage
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
            }
            
            Text(message.content)
                .padding(Theme.Spacing.sm)
                .background(message.isUser ? Theme.Colors.primary : Theme.Colors.secondaryBackground)
                .foregroundColor(message.isUser ? .white : Theme.Colors.text)
                .cornerRadius(Theme.Layout.cornerRadius)
                .standardShadow()
            
            if !message.isUser {
                Spacer()
            }
        }
    }
}

// MARK: - View Models
class AudioViewModel: ObservableObject {
    @Published var duration: TimeInterval = 180
    @Published var currentTime: TimeInterval = 0
    @Published var isPlaying: Bool = false
    @Published var playbackRate: Float = 1.0
    @Published var transcript: String?
    
    func seek(to time: TimeInterval) {
        #if DEBUG
        print("🎧 AudioViewModel: Seeking to time: \(time)")
        #endif
        currentTime = time
    }
}

class ReadViewModel: ObservableObject {
    @Published var isLoading = false
}

class QuizViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var questions: [QuizQuestion] = []
    
    struct QuizQuestion: Identifiable {
        let id = UUID()
        let question: String
        let options: [String]
        let correctAnswer: Int
    }
    
    func generateQuestions(from note: NoteCardConfiguration) {
        #if DEBUG
        print("📝 QuizViewModel: Generating questions for note: \(note.title)")
        #endif
        isLoading = true
        // TODO: Implement AI-based question generation
    }
}

class FlashcardsViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var flashcards: [Flashcard] = []
    
    struct Flashcard: Identifiable {
        let id = UUID()
        let front: String
        let back: String
    }
    
    func generateFlashcards(from note: NoteCardConfiguration) {
        #if DEBUG
        print("🎴 FlashcardsViewModel: Generating flashcards for note: \(note.title)")
        #endif
        isLoading = true
        // TODO: Implement AI-based flashcard generation
    }
}

class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText = ""
    @Published var isProcessing = false
    
    struct ChatMessage: Identifiable {
        let id = UUID()
        let content: String
        let isUser: Bool
        let timestamp: Date
    }
    
    func sendMessage() {
        #if DEBUG
        print("💬 ChatViewModel: Sending message: \(inputText)")
        #endif
        guard !inputText.isEmpty else { return }
        
        let userMessage = ChatMessage(
            content: inputText,
            isUser: true,
            timestamp: Date()
        )
        messages.append(userMessage)
        inputText = ""
        
        // TODO: Implement AI-based response generation
    }
}
