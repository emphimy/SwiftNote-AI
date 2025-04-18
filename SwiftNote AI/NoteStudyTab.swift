import SwiftUI
import CoreData
import AVKit
import Combine
import WebKit
import Down

// MARK: - Tab Models
enum StudyTab: String, CaseIterable {
    case read = "Read"
    case transcript = "Transcript"
    case quiz = "Quiz"
    case flashcards = "Flashcards"
    case chat = "Chat"

    var icon: String {
        switch self {
        case .read: return "book.fill"
        case .transcript: return "doc.text.fill" // Changed from text.quote.fill for better visibility
        case .quiz: return "checkmark.circle.fill"
        case .flashcards: return "rectangle.stack.fill"
        case .chat: return "bubble.left.and.bubble.right.fill"
        }
    }
}

// MARK: - Study Tab Container
struct NoteStudyTabs: View {
    @State private var selectedTab: StudyTab = .read
    let note: NoteCardConfiguration

    var body: some View {
        VStack(spacing: 0) {
            // Modern Tab Bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(StudyTab.allCases, id: \.self) { tab in
                        TabButton(
                            title: tab.rawValue,
                            icon: tab.icon,
                            isSelected: selectedTab == tab
                        ) {
                            withAnimation(nil) {
                                selectedTab = tab
#if DEBUG
                                print("📚 NoteStudyTabs: Tab selected - \(tab)")
#endif
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.Colors.secondaryBackground.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
            )
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.top, 0)
            .padding(.bottom, Theme.Spacing.md)

            // Content Area with smooth transitions
            ZStack {
                switch selectedTab {
                case .read:
                    ReadTabView(note: note)
                        .id("read-tab")
                        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                        .onAppear {
#if DEBUG
                            print("📚 NoteStudyTabs: Switched to Read tab")
#endif
                        }
                case .transcript:
                    TranscriptTabView(note: note)
                        .id("transcript-tab")
                        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                        .onAppear {
#if DEBUG
                            print("📚 NoteStudyTabs: Switched to Transcript tab")
#endif
                        }
                case .quiz:
                    QuizTabView(note: note)
                        .id("quiz-tab")
                        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                        .onAppear {
#if DEBUG
                            print("📚 NoteStudyTabs: Switched to Quiz tab")
#endif
                        }
                case .flashcards:
                    FlashcardsTabView(note: note)
                        .id("flashcards-tab")
                        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                        .onAppear {
#if DEBUG
                            print("📚 NoteStudyTabs: Switched to Flashcards tab")
#endif
                        }
                case .chat:
                    ChatTabView(note: note)
                        .id("chat-tab")
                        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
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
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isSelected ? .white : Theme.Colors.text.opacity(0.7))
                    .frame(width: 24, height: 24)

                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .white : Theme.Colors.text.opacity(0.7))
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    if isSelected {
                        // Selected tab background with gradient
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Theme.Colors.primary,
                                        Theme.Colors.primary.opacity(0.8)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: Theme.Colors.primary.opacity(0.3), radius: 3, x: 0, y: 2)
                    }
                }
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
                    // Show video player if it's a YouTube note
                    if note.sourceType == .video,
                       let metadata = note.metadata,
                       let videoId = metadata["videoId"] as? String {
                        YouTubeVideoPlayerView(videoId: videoId)
                            .padding(.bottom, Theme.Spacing.sm)
                            .padding(.horizontal, -Theme.Spacing.xs) // Extend beyond the normal content padding
                    }

                    // Show audio player if it's an audio or recording note
                    if (note.sourceType == .audio || note.sourceType == .recording), let audioURL = note.audioURL {
                        CompactAudioPlayerView(audioURL: audioURL)
                            .id("audio-player-\(audioURL.lastPathComponent)-\(UUID())") // Force recreation on each appearance
                            .padding(.bottom, Theme.Spacing.sm)
                            .padding(.horizontal, -Theme.Spacing.xs) // Extend beyond the normal content padding
                            .onAppear {
#if DEBUG
                                print("📝 ReadTabView: Audio player appeared for URL: \(audioURL)")
#endif
                            }
                    }

                    ForEach(content.formattedContent) { block in
                        ContentBlockView(block: block, fontSize: viewModel.textSize)
                    }
                }
                .padding(.horizontal, Theme.Spacing.xs)
            } else {
                Text("No content available")
                    .foregroundColor(Theme.Colors.secondaryText)
                    .padding(.horizontal, Theme.Spacing.xs)
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

// MARK: - YouTube Video Player View
struct YouTubeVideoPlayerView: View {
    let videoId: String

    var body: some View {
        let videoURL = URL(string: "https://www.youtube.com/embed/\(videoId)")!

        WebView(url: videoURL)
            .frame(height: 220)
            .cornerRadius(Theme.Layout.cornerRadius)
            .shadow(radius: 4)
    }
}

// MARK: - Web View
struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.scrollView.isScrollEnabled = false
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - Flashcards Tab View
struct FlashcardsTabView: View {
    @StateObject private var viewModel: FlashcardsViewModel = FlashcardsViewModel()
    let note: NoteCardConfiguration
    @State private var showingInfo = false

    var body: some View {
        VStack(spacing: 0) {
            // Audio player removed - only shown in Read tab

            // Header with title and info button
            HStack {
                Text("Flashcards")
                    .font(Theme.Typography.h2)
                    .foregroundColor(Theme.Colors.primary)

                Spacer()

                Button {
                    showingInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.title2)
                        .foregroundColor(Theme.Colors.primary)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, Theme.Spacing.md)

            // Progress indicator
            if !viewModel.flashcards.isEmpty {
                ProgressView(value: viewModel.progress)
                    .tint(Theme.Colors.primary)
                    .padding(.horizontal)
                    .padding(.bottom, Theme.Spacing.md)
            }

            // Main content
            ZStack {
                switch viewModel.loadingState {
                case .loading(let message):
                    LoadingIndicator(message: message)

                case .error(let message):
                    ErrorView(
                        error: NSError(domain: "Flashcards", code: -1, userInfo: [
                            NSLocalizedDescriptionKey: message
                        ])
                    ) {
                        Task { @MainActor in
                            await viewModel.generateFlashcards(from: note)
                        }
                    }

                case .success, .idle:
                    if viewModel.flashcards.isEmpty {
                        emptyStateView
                    } else {
                        flashcardsView
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Controls
            if !viewModel.flashcards.isEmpty {
                flashcardControls
            }
        }
        .padding(.vertical)
        .onAppear {
#if DEBUG
            print("🎴 FlashcardsTab: View appeared for note: \(note.title)")
#endif
        }
        .alert("About Flashcards", isPresented: $showingInfo) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Tap a card to flip it and reveal the answer. Use the buttons below to navigate between cards.")
        }
    }

    // Empty state view when no flashcards are available
    private var emptyStateView: some View {
        EmptyStateView(
            icon: "rectangle.stack",
            title: "No Flashcards Available",
            message: "Tap to generate flashcards from your note.",
            actionTitle: "Generate Flashcards"
        ) {
            Task {
                await viewModel.generateFlashcards(from: note)
            }
        }
    }

    // Flashcards view when cards are available
    private var flashcardsView: some View {
        VStack {
            // Card counter
            Text("\(viewModel.currentIndex + 1) of \(viewModel.totalCards)")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
                .padding(.bottom, Theme.Spacing.sm)

            // Flashcard content
            NoteCardConfiguration.FlashcardContent(
                flashcards: viewModel.flashcards,
                viewModel: viewModel
            )
        }
    }

    // Navigation controls for flashcards
    private var flashcardControls: some View {
        HStack(spacing: Theme.Spacing.xl) {
            Button {
                viewModel.previousCard()
            } label: {
                HStack {
                    Image(systemName: "chevron.left")
                    Text("Previous")
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(viewModel.currentIndex == 0)

            Button {
                viewModel.toggleCard()
            } label: {
                HStack {
                    Image(systemName: "arrow.2.squarepath")
                    Text("Flip")
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
            }
            .buttonStyle(PrimaryButtonStyle())

            Button {
                viewModel.nextCard()
            } label: {
                HStack {
                    Text("Next")
                    Image(systemName: "chevron.right")
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(viewModel.currentIndex == viewModel.totalCards - 1)
        }
        .padding(.top, Theme.Spacing.lg)
    }
}

// MARK: - Chat Tab View
struct ChatTabView: View {
    let note: NoteCardConfiguration
    @StateObject private var viewModel: ChatViewModel
    @FocusState private var isInputFocused: Bool
    @State private var keyboardHeight: CGFloat = 0

    init(note: NoteCardConfiguration) {
        self.note = note
        self._viewModel = StateObject(wrappedValue: ChatViewModel(note: note))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with title - more compact
            HStack {
                Text("Chat With Note")
                    .font(Theme.Typography.h2)
                    .foregroundColor(Theme.Colors.primary)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, Theme.Spacing.sm) // Reduced bottom padding

            // Chat Messages List with ScrollViewReader for programmatic scrolling
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.md) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message, viewModel: viewModel)
                                .id(message.id)
                        }

                        // Typing indicator
                        if viewModel.isTyping {
                            TypingIndicator(message: viewModel.typingMessage, viewModel: viewModel)
                                .id("typingIndicator")
                        }

                        // Minimal spacer at the bottom
                        Color.clear
                            .frame(height: 20) // Fixed small height
                            .id("bottomSpacer")
                    }
                    .padding(.horizontal)
                    .padding(.vertical, Theme.Spacing.xs) // Reduced vertical padding
                }
                .onChange(of: viewModel.messages.count) { _ in
                    if let lastMessage = viewModel.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.typingMessage) { _ in
                    if viewModel.isTyping {
                        withAnimation {
                            proxy.scrollTo("typingIndicator", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: keyboardHeight) { newHeight in
                    if newHeight > 0 {
                        // When keyboard appears, scroll to ensure content is visible
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                // First scroll to the bottom spacer
                                proxy.scrollTo("bottomSpacer", anchor: .bottom)

                                // Then scroll to the last message or typing indicator if available
                                if viewModel.isTyping {
                                    proxy.scrollTo("typingIndicator", anchor: .bottom)
                                } else if let lastMessage = viewModel.messages.last {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }

                // Error message if present
                if let error = viewModel.error {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(Theme.Colors.error)

                        Text(error)
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.error)

                        Spacer()

                        Button {
                            viewModel.error = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Theme.Colors.error)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Colors.errorBackground)
                }

                // Input Bar - very compact design
                HStack(spacing: Theme.Spacing.sm) {
                    // Message Input Field
                    TextField("Ask a question...", text: $viewModel.inputMessage, axis: .vertical)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, 8) // Slightly increased vertical padding
                        .background(Theme.Colors.secondaryBackground)
                        .cornerRadius(Theme.Layout.cornerRadius)
                        .focused($isInputFocused)
                        .disabled(viewModel.chatState.isProcessing && !viewModel.isTyping)
                        .submitLabel(.send)
                        .onSubmit {
                            sendMessage()
                        }
                        .lineLimit(1) // Single line by default

                    // Send Button
                    if viewModel.isTyping {
                        Button(action: {
                            viewModel.stopResponse()
                        }) {
                            Circle()
                                .fill(Theme.Colors.error)
                                .frame(width: 42, height: 42)
                                .overlay(
                                    Image(systemName: "stop.fill")
                                        .foregroundColor(.white)
                                )
                        }
                    } else {
                        Button(action: sendMessage) {
                            Circle()
                                .fill(viewModel.inputMessage.isEmpty || viewModel.chatState.isProcessing ?
                                      Theme.Colors.secondaryText : Theme.Colors.primary)
                                .frame(width: 42, height: 42)
                                .overlay(
                                    Image(systemName: "paperplane.fill")
                                        .foregroundColor(.white)
                                        .rotationEffect(.degrees(45))
                                )
                        }
                        .disabled(viewModel.inputMessage.isEmpty || (viewModel.chatState.isProcessing && !viewModel.isTyping))
                    }
                }
                .padding(.horizontal, Theme.Spacing.xs)
                .padding(.vertical, 6) // Slightly increased vertical padding
                .background(Theme.Colors.background)
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Theme.Colors.tertiaryBackground),
                    alignment: .top
                )
                // Position the input bar directly above the keyboard
                .padding(.bottom, keyboardHeight > 0 ? 0 : 0) // No extra padding - let it sit directly on the keyboard
            }
        }
        // Add gesture to dismiss keyboard when tapping outside text field
        .contentShape(Rectangle())
        .onTapGesture {
            isInputFocused = false
        }
        .onAppear {
#if DEBUG
            print("💬 ChatTab: View appeared for note: \(note.title)")
#endif
        }
        // Use the newer SwiftUI keyboard handling approach with animation
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                withAnimation(.easeOut(duration: 0.2)) {
                    keyboardHeight = keyboardFrame.height
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeIn(duration: 0.2)) {
                keyboardHeight = 0
            }
        }
        .padding(.vertical, Theme.Spacing.xs) // Minimal vertical padding
    }

    private func sendMessage() {
        guard !viewModel.inputMessage.isEmpty && !viewModel.chatState.isProcessing else { return }

    #if DEBUG
        print("💬 ChatTab: Sending message: \(viewModel.inputMessage)")
    #endif

        Task {
            await viewModel.sendMessage()
        }
    }
}

// MARK: - Message Bubble Component
private struct MessageBubble: View {
    let message: ChatMessage
    let viewModel: ChatViewModel

    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
            }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                HStack(alignment: .top) {
                    if !message.isUser {
                        // AI avatar
                        Circle()
                            .fill(Theme.Colors.primary)
                            .frame(width: 30, height: 30)
                            .overlay(
                                Image(systemName: "sparkles")
                                    .foregroundColor(.white)
                                    .font(.system(size: 16))
                            )
                    }

                    // Message content
                    if message.isUser {
                        Text(message.content)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                            .background(Theme.Colors.primary)
                            .foregroundColor(.white)
                            .cornerRadius(Theme.Layout.cornerRadius)
                    } else {
                        Text(viewModel.parseMarkdown(message.content))
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                            .background(Theme.Colors.secondaryBackground)
                            .foregroundColor(Theme.Colors.text)
                            .cornerRadius(Theme.Layout.cornerRadius)
                    }

                    if message.isUser {
                        // User avatar
                        Circle()
                            .fill(Theme.Colors.primary)
                            .frame(width: 30, height: 30)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 16))
                            )
                    }
                }

                // Message status and timestamp
                HStack(spacing: 4) {
                    if message.isUser {
                        Spacer()

                        // Message status
                        switch message.status {
                        case .sending:
                            Image(systemName: "clock")
                                .font(.caption2)
                                .foregroundColor(Theme.Colors.secondaryText)
                        case .sent:
                            Image(systemName: "checkmark")
                                .font(.caption2)
                                .foregroundColor(Theme.Colors.success)
                        case .failed:
                            Image(systemName: "exclamationmark.triangle")
                                .font(.caption2)
                                .foregroundColor(Theme.Colors.error)
                        }
                    }

                    // Timestamp
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(Theme.Colors.secondaryText)

                    if !message.isUser {
                        Spacer()
                    }
                }
                .padding(.horizontal, 8)
            }
            .contextMenu {
                Button(action: {
                    message.copyText()
                }) {
                    Label("Copy Text", systemImage: "doc.on.doc")
                }
            }

            if !message.isUser {
                Spacer()
            }
        }
    }
}

// MARK: - Typing Indicator Component
private struct TypingIndicator: View {
    let message: String
    let viewModel: ChatViewModel
    @State private var isAnimating = false

    var body: some View {
        HStack {
            // AI avatar
            Circle()
                .fill(Theme.Colors.primary)
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: "sparkles")
                        .foregroundColor(.white)
                        .font(.system(size: 16))
                )

            VStack(alignment: .leading) {
                if message.isEmpty {
                    // Animated dots when no text is available yet
                    HStack(spacing: 4) {
                        ForEach(0..<3) { index in
                            Circle()
                                .fill(Theme.Colors.secondaryText)
                                .frame(width: 6, height: 6)
                                .offset(y: isAnimating ? -5 : 0)
                                .animation(
                                    Animation.easeInOut(duration: 0.5)
                                        .repeatForever(autoreverses: true)
                                        .delay(Double(index) * 0.2),
                                    value: isAnimating
                                )
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                } else {
                    // Show the typing message as it's being generated
                    Text(viewModel.parseMarkdown(message))
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Colors.secondaryBackground)
            .cornerRadius(Theme.Layout.cornerRadius)

            Spacer()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.3)) {
                isAnimating = true
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
                .font(.system(size: fontSize * 2, weight: .bold))
                .foregroundColor(Theme.Colors.primary)
                .padding(.vertical, 8)
        case .heading2:
            Text(block.content)
                .font(.system(size: fontSize * 1.5, weight: .bold))
                .foregroundColor(Theme.Colors.primary)
                .padding(.vertical, 6)
        case .heading3:
            Text(block.content)
                .font(.system(size: fontSize * 1.25, weight: .bold))
                .foregroundColor(Theme.Colors.primary)
                .padding(.vertical, 4)
        case .heading4:
            Text(block.content)
                .font(.system(size: fontSize * 1.1, weight: .bold))
                .foregroundColor(Theme.Colors.primary)
                .padding(.vertical, 4)
        case .heading5:
            Text(block.content)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundColor(Theme.Colors.primary)
                .padding(.vertical, 4)
        case .heading6:
            Text(block.content)
                .font(.system(size: fontSize * 0.9, weight: .bold))
                .foregroundColor(Theme.Colors.primary)
                .padding(.vertical, 4)
        case .paragraph:
            Text(LocalizedStringKey(block.content))
                .font(.system(size: fontSize))
                .padding(.vertical, 2)
        case .bulletList:
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(.system(size: fontSize))
                Text(LocalizedStringKey(block.content))
                    .font(.system(size: fontSize))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 2)
        case .numberedList:
            Text(LocalizedStringKey(block.content))
                .font(.system(size: fontSize))
                .padding(.vertical, 2)
        case .taskList(let checked):
            HStack(spacing: 8) {
                Image(systemName: checked ? "checkmark.square" : "square")
                Text(LocalizedStringKey(block.content))
                    .font(.system(size: fontSize))
            }
            .padding(.vertical, 2)
        case .codeBlock(let language):
            VStack(alignment: .leading, spacing: 4) {
                if let language = language {
                    Text(language)
                        .font(.system(size: fontSize * 0.8))
                        .foregroundColor(.secondary)
                }
                Text(block.content)
                    .font(.system(size: fontSize, design: .monospaced))
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
            }
            .padding(.vertical, 4)
        case .quote:
            HStack {
                Rectangle()
                    .fill(Color.gray)
                    .frame(width: 4)
                Text(LocalizedStringKey(block.content))
                    .font(.system(size: fontSize))
                    .italic()
            }
            .padding(.vertical, 4)
        case .horizontalRule:
            Rectangle()
                .fill(Color.gray)
                .frame(height: 1)
                .padding(.vertical, 8)
        case .table(let headers, let rows):
            VStack(alignment: .leading, spacing: 8) {
                // Headers
                HStack {
                    ForEach(headers, id: \.self) { header in
                        Text(LocalizedStringKey(header))
                            .font(.system(size: fontSize, weight: .bold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Rows
                ForEach(rows, id: \.self) { row in
                    HStack {
                        ForEach(row, id: \.self) { cell in
                            Text(LocalizedStringKey(cell))
                                .font(.system(size: fontSize))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        case .formattedText(let style):
            switch style {
            case .bold:
                Text(block.content)
                    .font(.system(size: fontSize, weight: .bold))
            case .italic:
                Text(block.content)
                    .font(.system(size: fontSize))
                    .italic()
            case .boldItalic:
                Text(block.content)
                    .font(.system(size: fontSize, weight: .bold))
                    .italic()
            case .strikethrough:
                Text(block.content)
                    .font(.system(size: fontSize))
                    .strikethrough()
            case .link(let url):
                Link(block.content, destination: URL(string: url) ?? URL(string: "about:blank")!)
                    .font(.system(size: fontSize))
            case .image(let url, _):
                AsyncImage(url: URL(string: url)) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    ProgressView()
                }
            }
        }
    }
}

// MARK: - Down View
struct DownView: UIViewRepresentable {
    let markdown: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isScrollEnabled = false
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        let down = Down(markdownString: markdown)
        if let attributedString = try? down.toAttributedString() {
            uiView.attributedText = attributedString
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
        VStack(spacing: 0) {
            // Header with title
            HStack {
                Text("Transcript")
                    .font(Theme.Typography.h2)
                    .foregroundColor(Theme.Colors.primary)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, Theme.Spacing.md)

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
                    LazyVStack(alignment: .leading, spacing: 16) {
                        let paragraphs = transcript.components(separatedBy: "\n\n")
                        ForEach(Array(zip(paragraphs.indices, paragraphs)), id: \.0) { index, paragraph in
                            if !paragraph.isEmpty {
                                // Try to find a timestamp in the format [MM:SS]
                                if let timeRange = paragraph.range(of: "\\[\\d+:\\d{2}\\]", options: [.regularExpression]) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(String(paragraph[timeRange]))
                                            .font(.caption)
                                            .foregroundColor(.secondary)

                                        Text(String(paragraph[paragraph.index(after: timeRange.upperBound)...])
                                            .trimmingCharacters(in: CharacterSet.whitespaces))
                                        .font(.body)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Theme.Colors.secondaryBackground.opacity(0.5))
                                    .cornerRadius(12)
                                    .padding(.horizontal, 8)
                                } else {
                                    // If no timestamp found, just display the paragraph
                                    VStack(alignment: .leading, spacing: 4) {
                                        // Add a paragraph number for reference
                                        Text("Paragraph \(index + 1)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)

                                        Text(paragraph)
                                            .font(.body)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Theme.Colors.secondaryBackground.opacity(0.3))
                                    .cornerRadius(12)
                                    .padding(.horizontal, 8)
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
        .padding(.vertical)
    }
}
