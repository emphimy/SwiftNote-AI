import SwiftUI
import CoreData
import AVKit
import Combine

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
        self._viewModel = StateObject(wrappedValue: ReadTabViewModel(note: note))
        
        #if DEBUG
        print("📖 ReadTabView: Initializing with note: \(note.title)")
        #endif
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Controls Bar
            HStack {
                SearchBar(text: $viewModel.searchText)
                
                Button(action: {
                    #if DEBUG
                    print("📖 ReadTabView: Decreasing text size")
                    #endif
                    viewModel.adjustTextSize(-2)
                }) {
                    Image(systemName: "textformat.size.smaller")
                        .foregroundColor(Theme.Colors.primary)
                }
                
                Button(action: {
                    #if DEBUG
                    print("📖 ReadTabView: Increasing text size")
                    #endif
                    viewModel.adjustTextSize(2)
                }) {
                    Image(systemName: "textformat.size.larger")
                        .foregroundColor(Theme.Colors.primary)
                }
            }
            .padding(.horizontal)
            
            // Content
            ScrollView {
                if viewModel.isLoading {
                    LoadingIndicator(message: "Loading content...")
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
                }
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
                    #if DEBUG
                    print("🎴 FlashcardsTabView: Generating flashcards")
                    #endif
                    Task {
                        await viewModel.generateFlashcards(from: note)
                    }
                }
            } else {
                if let currentCard = viewModel.flashcards[safe: viewModel.currentIndex] {
                    FlashcardView(flashcard: currentCard) {
                        #if DEBUG
                        print("🎴 FlashcardsTabView: Card tapped - toggling")
                        #endif
                        viewModel.toggleCard()
                    }
                    
                    FlashcardControls(
                        currentCard: viewModel.currentIndex,
                        totalCards: viewModel.totalCards,
                        progress: viewModel.progress,
                        onPrevious: {
                            #if DEBUG
                            print("🎴 FlashcardsTabView: Moving to previous card")
                            #endif
                            viewModel.previousCard()
                        },
                        onNext: {
                            #if DEBUG
                            print("🎴 FlashcardsTabView: Moving to next card")
                            #endif
                            viewModel.nextCard()
                        }
                    )
                }
            }
        }
        .padding()
    }
}

// MARK: - Chat Tab View
struct ChatTabView: View {
    let note: NoteCardConfiguration
    @StateObject private var viewModel: ChatViewModel
    @Environment(\.toastManager) private var toastManager
    
    init(note: NoteCardConfiguration) {
        self.note = note
        self._viewModel = StateObject(wrappedValue: ChatViewModel(noteContent: note.preview))
        
        #if DEBUG
        print("💬 ChatTabView: Initialized with note: \(note.title)")
        #endif
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Chat Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.md) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _ in
                    if let lastMessage = viewModel.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Typing Indicator
            if viewModel.state.isProcessing {
                TypingIndicator()
                    .padding()
                    .transition(.move(edge: .bottom))
            }
            
            // Input Area
            ChatInputField(
                text: $viewModel.inputText,
                isProcessing: viewModel.state.isProcessing,
                onSend: {
                    #if DEBUG
                    print("💬 ChatTabView: Send button tapped")
                    #endif
                    viewModel.sendMessage()
                }
            )
            .padding()
        }
        .onChange(of: viewModel.state) { state in
            if case .error(let message) = state {
                toastManager.show(message, type: .error)
            }
        }
    }
}

// MARK: - Message Bubble
private struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.type == .user {
                Spacer()
            }
            
            VStack(alignment: message.type == .user ? .trailing : .leading, spacing: Theme.Spacing.xxs) {
                Text(message.content)
                    .padding(Theme.Spacing.sm)
                    .background(message.type == .user ? Theme.Colors.primary : Theme.Colors.secondaryBackground)
                    .foregroundColor(message.type == .user ? .white : Theme.Colors.text)
                    .cornerRadius(Theme.Layout.cornerRadius)
                
                if case .failed(let error) = message.status {
                    Text(error.localizedDescription)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.error)
                }
            }
            
            if message.type == .assistant {
                Spacer()
            }
        }
        .transition(.asymmetric(
            insertion: .scale.combined(with: .opacity),
            removal: .opacity
        ))
    }
}

// MARK: - Typing Indicator
private struct TypingIndicator: View {
    @State private var dots = ""
    
    var body: some View {
        HStack {
            Text("AI is typing\(dots)")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
                .onAppear {
                    animateDots()
                }
            Spacer()
        }
    }
    
    private func animateDots() {
        Task {
            while true {
                for i in 1...3 {
                    await MainActor.run {
                        dots = String(repeating: ".", count: i)
                    }
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
        }
    }
}

// MARK: - Chat Input Field
private struct ChatInputField: View {
    @Binding var text: String
    let isProcessing: Bool
    let onSend: () -> Void
    
    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            TextField("Ask a question...", text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .disabled(isProcessing)
            
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(Theme.Colors.primary)
            }
            .disabled(text.isEmpty || isProcessing)
        }
        .background(Theme.Colors.background)
        .standardShadow()
    }
}

// MARK: - Flashcard View
private struct FlashcardView: View {
    let flashcard: FlashcardsViewModel.Flashcard
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack {
                Spacer()
                
                Text(flashcard.isRevealed ? flashcard.back : flashcard.front)
                    .font(Theme.Typography.body)
                    .multilineTextAlignment(.center)
                    .padding(Theme.Spacing.lg)
                    .frame(maxWidth: .infinity)
                
                Spacer()
                
                if !flashcard.isRevealed {
                    Text("Tap to reveal")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                        .padding(.bottom, Theme.Spacing.md)
                }
            }
            .frame(height: 300)
            .background(Theme.Colors.background)
            .cornerRadius(Theme.Layout.cornerRadius)
            .standardShadow()
            .rotation3DEffect(
                .degrees(flashcard.isRevealed ? 180 : 0),
                axis: (x: 0, y: 1, z: 0)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Flashcard Controls
private struct FlashcardControls: View {
    let currentCard: Int
    let totalCards: Int
    let progress: Double
    let onPrevious: () -> Void
    let onNext: () -> Void
    
    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Progress Bar
            ProgressView(value: progress)
                .tint(Theme.Colors.primary)
            
            // Navigation Controls
            HStack {
                Button(action: onPrevious) {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title2)
                        .foregroundColor(Theme.Colors.primary)
                }
                .disabled(currentCard == 0)
                
                Spacer()
                
                Text("\(currentCard + 1) of \(totalCards)")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
                
                Spacer()
                
                Button(action: onNext) {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title2)
                        .foregroundColor(Theme.Colors.primary)
                }
                .disabled(currentCard == totalCards - 1)
            }
            .padding(.horizontal, Theme.Spacing.md)
        }
        .onChange(of: currentCard) { newValue in
            #if DEBUG
            print("🎴 FlashcardControls: Card changed to \(newValue + 1)/\(totalCards)")
            #endif
        }
    }
}

// MARK: - View Models
class AudioViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var duration: TimeInterval
    @Published var currentTime: TimeInterval
    @Published var isPlaying: Bool
    @Published var playbackRate: Float
    @Published var transcript: String?
    
    // MARK: - Initialization
    init() {
        self.duration = 180
        self.currentTime = 0
        self.isPlaying = false
        self.playbackRate = 1.0
        self.transcript = nil
        
        #if DEBUG
        print("🎧 AudioViewModel: Initialized with default values")
        #endif
    }
    
    // MARK: - Public Methods
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

@MainActor
final class ChatViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var state: ChatState = .idle
    @Published var inputText = ""
    
    // MARK: - Private Properties
    private let noteContent: String
    private var processingTask: Task<Void, Never>?
    
    // MARK: - Initialization
    init(noteContent: String) {
        self.noteContent = noteContent
        
        #if DEBUG
        print("💬 ChatViewModel: Initializing with note content length: \(noteContent.count)")
        #endif
    }
    
    // MARK: - Message Handling
    func sendMessage() {
        guard !inputText.isEmpty else {
            #if DEBUG
            print("💬 ChatViewModel: Attempted to send empty message")
            #endif
            return
        }
        
        let messageText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        inputText = ""
        
        let message = ChatMessage(
            content: messageText,
            type: .user,
            status: .sending
        )
        
        #if DEBUG
        print("💬 ChatViewModel: Sending message: \(messageText)")
        #endif
        
        messages.append(message)
        processMessage(message)
    }
    
    private func processMessage(_ message: ChatMessage) {
        state = .processing
        
        processingTask = Task {
            do {
                // Simulate AI processing time
                try await Task.sleep(nanoseconds: 2_000_000_000)
                
                // Generate AI response based on context
                let response = generateResponse(to: message)
                
                await MainActor.run {
                    let responseMessage = ChatMessage(
                        content: response,
                        type: .assistant
                    )
                    messages.append(responseMessage)
                    state = .idle
                }
                
                #if DEBUG
                print("💬 ChatViewModel: Response generated successfully")
                #endif
            } catch {
                #if DEBUG
                print("💬 ChatViewModel: Error processing message - \(error)")
                #endif
                
                await MainActor.run {
                    state = .error(error.localizedDescription)
                }
            }
        }
    }
    
    // MARK: - Cleanup
    private func cleanup() {
        processingTask?.cancel()
        processingTask = nil
        
        #if DEBUG
        print("💬 ChatViewModel: Cleanup performed")
        #endif
    }
    
    deinit {
        // Create a separate Task that won't retain self
        Task { @MainActor [processingTask] in
            processingTask?.cancel()
            
            #if DEBUG
            print("💬 ChatViewModel: Deinitializing and cleanup completed")
            #endif
        }
    }
    
    // MARK: - Response Generation
    private func generateResponse(to message: ChatMessage) -> String {
        // TODO: Implement actual AI response generation
        // This is a placeholder that simulates response generation
        return "I understand you're asking about \(message.content). Let me help you with that based on the note content."
    }
}

// MARK: - Array Safe Subscript Extension
private extension Array {
    /// Safe array subscript that returns nil if index is out of bounds
    ///
    /// Usage: array[safe: index]
    subscript(safe index: Index) -> Element? {
        #if DEBUG
        print("🔄 Array: Safe accessing index \(index) of \(count) elements")
        #endif
        return indices.contains(index) ? self[index] : nil
    }
}
