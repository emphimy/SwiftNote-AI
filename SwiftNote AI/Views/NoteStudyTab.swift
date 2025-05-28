import SwiftUI
import CoreData
import AVKit
import Combine
@preconcurrency import WebKit
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
                    .fill(Theme.Colors.secondaryBackground.opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Theme.Colors.primary.opacity(0.1), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
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
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
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

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        ForEach(content.formattedContent) { block in
                            ContentBlockView(block: block, fontSize: viewModel.textSize)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
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
    @State private var playerHeight: CGFloat = 220

    var body: some View {
        EnhancedYouTubeWebView(videoId: videoId)
            .frame(height: playerHeight)
            .cornerRadius(Theme.Layout.cornerRadius)
            .shadow(radius: 4)
    }
}

// MARK: - Enhanced YouTube Web View
struct EnhancedYouTubeWebView: UIViewRepresentable {
    let videoId: String

    func makeUIView(context: Context) -> WKWebView {
        // Create configuration with required settings
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        // Create preferences
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences

        // Create web view with configuration
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false

        // Load the HTML with embedded player
        loadYouTubePlayer(webView: webView, videoId: videoId)

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Only reload if video ID changes
        if context.coordinator.currentVideoId != videoId {
            context.coordinator.currentVideoId = videoId
            loadYouTubePlayer(webView: webView, videoId: videoId)
        }
    }

    private func loadYouTubePlayer(webView: WKWebView, videoId: String) {
        // Create HTML with iframe that includes all necessary parameters
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                body, html {
                    margin: 0;
                    padding: 0;
                    width: 100%;
                    height: 100%;
                    background-color: #000;
                    overflow: hidden;
                }
                .container {
                    position: relative;
                    width: 100%;
                    height: 0;
                    padding-bottom: 56.25%;
                    overflow: hidden;
                }
                iframe {
                    position: absolute;
                    top: 0;
                    left: 0;
                    width: 100%;
                    height: 100%;
                    border: 0;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <iframe
                    src="https://www.youtube.com/embed/\(videoId)?playsinline=1&rel=0&showinfo=0&autoplay=0&enablejsapi=1&origin=\(getOrigin())"
                    frameborder="0"
                    allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
                    allowfullscreen>
                </iframe>
            </div>
        </body>
        </html>
        """

        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
    }

    private func getOrigin() -> String {
        // Use a valid origin that matches your app's domain
        // For local testing, we'll use a placeholder
        return "https://swiftnote.app"
    }

    // MARK: - Coordinator
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: EnhancedYouTubeWebView
        var currentVideoId: String

        init(_ parent: EnhancedYouTubeWebView) {
            self.parent = parent
            self.currentVideoId = parent.videoId
        }

        // Handle navigation events
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Allow the initial load
            if navigationAction.navigationType == .other {
                decisionHandler(.allow)
                return
            }

            // If it's a link to YouTube, allow it
            if let url = navigationAction.request.url, url.host?.contains("youtube.com") == true {
                decisionHandler(.allow)
                return
            }

            // Block other navigation
            decisionHandler(.cancel)
        }
    }
}

// MARK: - Standard Web View (for other uses)
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
                .lineSpacing(2)
                .padding(.vertical, 3)
        case .bulletList:
            HStack(alignment: .top, spacing: 10) {
                Text("•")
                    .font(.system(size: fontSize))
                    .foregroundColor(Theme.Colors.primary)
                Text(LocalizedStringKey(block.content))
                    .font(.system(size: fontSize))
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 3)
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
            VStack(alignment: .leading, spacing: 0) {
                // Headers
                HStack(spacing: 0) {
                    ForEach(Array(headers.enumerated()), id: \.offset) { index, header in
                        Text(LocalizedStringKey(header))
                            .font(.system(size: fontSize * 0.9, weight: .semibold))
                            .foregroundColor(Theme.Colors.text)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(
                                Rectangle()
                                    .fill(Theme.Colors.primary.opacity(0.1))
                                    .frame(width: index < headers.count - 1 ? 1 : 0)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            )
                    }
                }
                .background(Theme.Colors.secondaryBackground)
                .overlay(
                    Rectangle()
                        .fill(Theme.Colors.primary.opacity(0.2))
                        .frame(height: 1)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                )

                // Rows
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { cellIndex, cell in
                            Text(LocalizedStringKey(cell))
                                .font(.system(size: fontSize * 0.85))
                                .foregroundColor(Theme.Colors.text)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .overlay(
                                    Rectangle()
                                        .fill(Theme.Colors.primary.opacity(0.1))
                                        .frame(width: cellIndex < row.count - 1 ? 1 : 0)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                )
                        }
                    }
                    .background(rowIndex % 2 == 0 ? Theme.Colors.background : Theme.Colors.cardBackground)
                    .overlay(
                        Rectangle()
                            .fill(Theme.Colors.primary.opacity(0.1))
                            .frame(height: 1)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    )
                }
            }
            .background(Theme.Colors.background)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.Colors.primary.opacity(0.2), lineWidth: 1)
            )
            .padding(.vertical, 8)
        case .feynmanSimplification:
            VStack(alignment: .leading, spacing: 12) {
                // Header with lightbulb icon inside the box
                HStack(spacing: 10) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: fontSize * 1.2, weight: .medium))
                        .foregroundColor(.orange)

                    Text("Feynman Simplification")
                        .font(.system(size: fontSize * 1.1, weight: .bold))
                        .foregroundColor(.orange)
                }
                .padding(.bottom, 4)

                // Content text
                Text(LocalizedStringKey(block.content))
                    .font(.system(size: fontSize * 0.9))
                    .foregroundColor(Theme.Colors.text)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.orange.opacity(0.08),
                                Color.orange.opacity(0.04)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                    )
            )
            .padding(.vertical, 6)
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
                    // Process transcript into conversation blocks
                    let blocks = processTranscriptIntoBlocks(transcript)

                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(blocks) { block in
                            VStack(alignment: .leading, spacing: 8) {
                                // Time range header
                                Text(block.timeRange)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Theme.Colors.primary)

                                // Consolidated text content
                                Text(block.consolidatedText)
                                    .font(.system(size: 13))
                                    .foregroundColor(Theme.Colors.text)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .lineSpacing(3)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Theme.Colors.cardBackground)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Theme.Colors.primary.opacity(0.1), lineWidth: 1)
                                    )
                            )
                            .padding(.horizontal, 8)
                        }
                    }
                    .padding(.vertical)
                } else {
                    // Show empty state when no transcript is available
                    VStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 40))
                            .foregroundColor(Theme.Colors.secondaryText)

                        Text("No Transcript Available")
                            .font(Theme.Typography.h3)
                            .foregroundColor(Theme.Colors.text)

                        Text("This note doesn't have a transcript.")
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            }
            .task {
                #if DEBUG
                print("📝 TranscriptTabView: Loading transcript on appear")
                #endif
                await viewModel.loadTranscript()
            }
        }
        .padding(.vertical)
    }

    // Process transcript into conversation blocks with time ranges
    private func processTranscriptIntoBlocks(_ transcript: String) -> [TranscriptBlock] {
        // Split transcript into lines
        let lines = transcript.components(separatedBy: .newlines)

        // Extract all timestamps and text first
        var allTimestampedLines: [TranscriptLine] = []

        // Regex for timestamp extraction
        let timestampPattern = "\\[(\\d{2}:\\d{2})\\]"
        let regex = try? NSRegularExpression(pattern: timestampPattern)

        // First pass: extract all timestamped lines
        for line in lines {
            // Skip empty lines
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }

            // Extract timestamp using regex
            let nsString = line as NSString
            let matches = regex?.matches(in: line, range: NSRange(location: 0, length: nsString.length))

            if let match = matches?.first, let range = Range(match.range(at: 1), in: line) {
                let timestamp = String(line[range])
                let fullTimestamp = "[\(timestamp)]"

                // Extract text after timestamp
                let textStartIndex = line.index(after: line.range(of: "]")?.upperBound ?? line.startIndex)
                let text = String(line[textStartIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)

                // Add line to collection
                allTimestampedLines.append(TranscriptLine(
                    id: UUID(),
                    timestamp: fullTimestamp,
                    text: text
                ))
            }
        }

        // If no timestamped lines were found, treat as plain text transcript
        if allTimestampedLines.isEmpty {
            #if DEBUG
            print("📝 TranscriptTabView: No timestamps found, treating as plain text transcript")
            #endif
            return processPlainTextTranscript(transcript)
        }

        // Second pass: group lines into 50-second blocks based on original timestamps
        var blocks: [TranscriptBlock] = []
        var currentBlockLines: [TranscriptLine] = []
        var currentBlockStartTime: String = ""
        var currentBlockStartSeconds: Int = 0

        for line in allTimestampedLines {
            // Extract timestamp without brackets
            let timestamp = line.timestamp.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")

            // Convert timestamp to seconds
            guard let timestampSeconds = timeToSeconds(timestamp) else {
                continue
            }

            // If this is the first line or we're starting a new block
            if currentBlockLines.isEmpty {
                currentBlockStartTime = timestamp
                currentBlockStartSeconds = timestampSeconds
                currentBlockLines.append(line)
                continue
            }

            // Check if we should start a new block (if more than 50 seconds have passed)
            let timeDifference = timestampSeconds - currentBlockStartSeconds

            if timeDifference >= 50 {
                // Create a block with the accumulated lines
                if !currentBlockLines.isEmpty {
                    // Get the last timestamp in the current block
                    let lastLine = currentBlockLines.last!
                    let lastTimestamp = lastLine.timestamp.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")

                    // Create time range
                    let timeRange = "\(currentBlockStartTime) - \(lastTimestamp)"

                    // Consolidate text
                    let consolidatedText = createConsolidatedText(from: currentBlockLines)

                    // Create block
                    blocks.append(TranscriptBlock(
                        id: UUID(),
                        timeRange: timeRange,
                        consolidatedText: consolidatedText,
                        lines: currentBlockLines
                    ))

                    // Start a new block
                    currentBlockLines = [line]
                    currentBlockStartTime = timestamp
                    currentBlockStartSeconds = timestampSeconds
                }
            } else {
                // Add to current block
                currentBlockLines.append(line)
            }
        }

        // Add the final block if not empty
        if !currentBlockLines.isEmpty {
            // Get the last timestamp in the current block
            let lastLine = currentBlockLines.last!
            let lastTimestamp = lastLine.timestamp.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")

            // Create time range
            let timeRange = "\(currentBlockStartTime) - \(lastTimestamp)"

            // Consolidate text
            let consolidatedText = createConsolidatedText(from: currentBlockLines)

            // Create block
            blocks.append(TranscriptBlock(
                id: UUID(),
                timeRange: timeRange,
                consolidatedText: consolidatedText,
                lines: currentBlockLines
            ))
        }

        // Ensure each block has a reasonable amount of text (at least 100 characters)
        // If not, merge with adjacent blocks
        if blocks.count > 1 {
            var mergedBlocks: [TranscriptBlock] = []
            var currentMergedBlock: TranscriptBlock? = nil

            for block in blocks {
                if currentMergedBlock == nil {
                    currentMergedBlock = block
                    continue
                }

                // If current merged block has less than 100 characters, merge with next block
                if currentMergedBlock!.consolidatedText.count < 100 {
                    // Parse time ranges
                    let currentTimeRange = parseTimeRange(currentMergedBlock!.timeRange)
                    let nextTimeRange = parseTimeRange(block.timeRange)

                    if let currentStart = currentTimeRange.start, let nextEnd = nextTimeRange.end {
                        // Create new merged time range
                        let newTimeRange = "\(currentStart) - \(nextEnd)"

                        // Combine lines and text
                        var combinedLines = currentMergedBlock!.lines
                        combinedLines.append(contentsOf: block.lines)

                        let combinedText = currentMergedBlock!.consolidatedText + " " + block.consolidatedText

                        // Create new merged block
                        currentMergedBlock = TranscriptBlock(
                            id: UUID(),
                            timeRange: newTimeRange,
                            consolidatedText: combinedText,
                            lines: combinedLines
                        )
                    }
                } else {
                    // Add current merged block to result and start a new one
                    mergedBlocks.append(currentMergedBlock!)
                    currentMergedBlock = block
                }
            }

            // Add the final merged block if not nil
            if let finalBlock = currentMergedBlock {
                mergedBlocks.append(finalBlock)
            }

            return mergedBlocks
        }

        return blocks
    }

    // Process plain text transcript (without timestamps) into readable blocks
    private func processPlainTextTranscript(_ transcript: String) -> [TranscriptBlock] {
        #if DEBUG
        print("📝 TranscriptTabView: Processing plain text transcript with \(transcript.count) characters")
        #endif

        // Clean up the transcript
        let cleanedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        // If transcript is empty, return empty array
        if cleanedTranscript.isEmpty {
            return []
        }

        // Split into paragraphs (double newlines) or sentences if no paragraphs
        var paragraphs: [String] = []

        // First try to split by double newlines (paragraph breaks)
        let paragraphCandidates = cleanedTranscript.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if paragraphCandidates.count > 1 {
            paragraphs = paragraphCandidates
        } else {
            // If no paragraph breaks, split by sentences
            let sentences = cleanedTranscript.components(separatedBy: ". ")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if sentences.count > 1 {
                // Group sentences into paragraphs (3-4 sentences each)
                let sentencesPerParagraph = 3
                var currentParagraph = ""
                var sentenceCount = 0

                for sentence in sentences {
                    if currentParagraph.isEmpty {
                        currentParagraph = sentence
                    } else {
                        currentParagraph += ". " + sentence
                    }

                    sentenceCount += 1

                    if sentenceCount >= sentencesPerParagraph {
                        paragraphs.append(currentParagraph + ".")
                        currentParagraph = ""
                        sentenceCount = 0
                    }
                }

                // Add remaining sentences
                if !currentParagraph.isEmpty {
                    paragraphs.append(currentParagraph + ".")
                }
            } else {
                // If no sentence breaks, split by character count
                let maxCharsPerBlock = 300
                var startIndex = cleanedTranscript.startIndex

                while startIndex < cleanedTranscript.endIndex {
                    let endDistance = min(maxCharsPerBlock, cleanedTranscript.distance(from: startIndex, to: cleanedTranscript.endIndex))
                    var endIndex = cleanedTranscript.index(startIndex, offsetBy: endDistance)

                    // Try to find a space to break at
                    if endIndex < cleanedTranscript.endIndex {
                        let spaceRange = cleanedTranscript[..<endIndex].lastIndex(of: " ")
                        if let spaceIndex = spaceRange {
                            endIndex = cleanedTranscript.index(after: spaceIndex)
                        }
                    }

                    let paragraph = String(cleanedTranscript[startIndex..<endIndex])
                    paragraphs.append(paragraph)
                    startIndex = endIndex
                }
            }
        }

        #if DEBUG
        print("📝 TranscriptTabView: Created \(paragraphs.count) paragraphs from plain text")
        #endif

        // Convert paragraphs to TranscriptBlocks
        var blocks: [TranscriptBlock] = []

        for (index, paragraph) in paragraphs.enumerated() {
            let blockNumber = index + 1
            let timeRange = "Section \(blockNumber)"

            blocks.append(TranscriptBlock(
                id: UUID(),
                timeRange: timeRange,
                consolidatedText: paragraph,
                lines: [] // No individual lines for plain text
            ))
        }

        return blocks
    }

    // Create consolidated text from multiple transcript lines
    private func createConsolidatedText(from lines: [TranscriptLine]) -> String {
        var result = ""

        for line in lines {
            // Add the text with appropriate spacing
            if result.isEmpty {
                result = line.text
            } else {
                // Check if we need a space between sentences
                let needsSpace = !result.hasSuffix(".") && !result.hasSuffix("!") && !result.hasSuffix("?") &&
                                !result.hasSuffix(" ") && !line.text.hasPrefix(" ")

                if needsSpace {
                    result += " " + line.text
                } else {
                    result += line.text
                }
            }
        }

        return result
    }

    // Format time range in a consistent way (e.g., "00:00 - 00:50")
    private func formatTimeRange(startTime: String, endTime: String) -> String {
        // Parse start time
        let startComponents = startTime.components(separatedBy: ":")
        guard startComponents.count == 2,
              let startMinutes = Int(startComponents[0]),
              let startSeconds = Int(startComponents[1]) else {
            return "\(startTime) - \(endTime)"
        }

        // Parse end time
        let endComponents = endTime.components(separatedBy: ":")
        guard endComponents.count == 2,
              let endMinutes = Int(endComponents[0]),
              let endSeconds = Int(endComponents[1]) else {
            return "\(startTime) - \(endTime)"
        }

        // Calculate total seconds for start and end
        let startTotalSeconds = startMinutes * 60 + startSeconds
        let endTotalSeconds = endMinutes * 60 + endSeconds

        // If end time is the same or earlier than start time, add 50 seconds to create a proper range
        let adjustedEndTotalSeconds = endTotalSeconds <= startTotalSeconds ?
                                      startTotalSeconds + 50 : endTotalSeconds

        // Convert back to minutes and seconds
        let adjustedEndMinutes = adjustedEndTotalSeconds / 60
        let adjustedEndSeconds = adjustedEndTotalSeconds % 60

        // Format times with leading zeros
        let formattedStartTime = String(format: "%02d:%02d", startMinutes, startSeconds)

        // For end time, round up to nearest 10 seconds for cleaner time ranges
        var roundedEndSeconds = ((adjustedEndSeconds + 9) / 10) * 10
        var roundedEndMinutes = adjustedEndMinutes

        // Handle case where seconds roll over to next minute
        if roundedEndSeconds >= 60 {
            roundedEndSeconds = 0
            roundedEndMinutes += 1
        }

        let formattedEndTime = String(format: "%02d:%02d", roundedEndMinutes, roundedEndSeconds)

        return "\(formattedStartTime) - \(formattedEndTime)"
    }

    // Parse a time range string into start and end components
    private func parseTimeRange(_ timeRange: String) -> (start: String?, end: String?) {
        let components = timeRange.components(separatedBy: " - ")
        if components.count == 2 {
            return (components[0], components[1])
        }
        return (nil, nil)
    }

    // Convert time string (MM:SS) to seconds
    private func timeToSeconds(_ timeString: String) -> Int? {
        let components = timeString.components(separatedBy: ":")
        guard components.count == 2,
              let minutes = Int(components[0]),
              let seconds = Int(components[1]) else {
            return nil
        }

        return minutes * 60 + seconds
    }

    // Convert seconds to time string (MM:SS)
    private func secondsToTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    // Determine if we should start a new conversation block
    private func shouldCreateNewBlock(currentTime: String, currentText: String, currentBlockLines: [TranscriptLine]) -> Bool {
        // If this is the first line or block is empty, don't create a new block
        guard !currentBlockLines.isEmpty else {
            return false
        }

        // Get the first line of the current block to determine block start time
        guard let firstLine = currentBlockLines.first else {
            return false
        }

        // Extract timestamps without brackets
        let firstTimestampStr = firstLine.timestamp.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
        let currentTimestampStr = currentTime

        // Convert timestamps to seconds for comparison
        let firstTimeComponents = firstTimestampStr.components(separatedBy: ":")
        let currentTimeComponents = currentTimestampStr.components(separatedBy: ":")

        guard firstTimeComponents.count == 2, currentTimeComponents.count == 2,
              let firstMinutes = Int(firstTimeComponents[0]),
              let firstSeconds = Int(firstTimeComponents[1]),
              let currentMinutes = Int(currentTimeComponents[0]),
              let currentSeconds = Int(currentTimeComponents[1]) else {
            return false
        }

        let firstTotalSeconds = firstMinutes * 60 + firstSeconds
        let currentTotalSeconds = currentMinutes * 60 + currentSeconds

        // Calculate how long this block has been running
        let blockDuration = currentTotalSeconds - firstTotalSeconds

        // Start a new block if:
        // 1. Block duration is 50 seconds or more
        if blockDuration >= 50 {
            return true
        }

        // 2. We've crossed a major time boundary (e.g., 1:00 to 2:00)
        // This ensures we don't have blocks that span across major time boundaries
        if firstMinutes / 1 != currentMinutes / 1 {
            return true
        }

        // For all other cases, keep adding to the current block
        return false
    }
}

// MARK: - Transcript Models
struct TranscriptLine: Identifiable {
    let id: UUID
    let timestamp: String
    let text: String
}

struct TranscriptBlock: Identifiable {
    let id: UUID
    let timeRange: String
    let consolidatedText: String
    let lines: [TranscriptLine]
}
