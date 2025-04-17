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
                HStack(spacing: Theme.Spacing.xs) {
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
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xs)
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
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? Theme.Colors.primary : Theme.Colors.secondaryText)
                
                Text(title)
                    .font(Theme.Typography.caption)
                    .foregroundColor(isSelected ? Theme.Colors.primary : Theme.Colors.secondaryText)
            }
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.vertical, Theme.Spacing.xxs)
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
                    // Show video player if it's a YouTube note
                    if note.sourceType == .video,
                       let metadata = note.metadata,
                       let videoId = metadata["videoId"] as? String {
                        YouTubeVideoPlayerView(videoId: videoId)
                            .padding(.bottom, Theme.Spacing.md)
                    }
                    
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
                if viewModel.isLoading {
                    LoadingIndicator(message: "Creating flashcards...")
                } else if viewModel.flashcards.isEmpty {
                    emptyStateView
                } else {
                    flashcardsView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Controls
            if !viewModel.flashcards.isEmpty {
                flashcardControls
            }
        }
        .padding(.vertical)
        .task {
            #if DEBUG
            print("🎴 FlashcardsTab: Generating flashcards for note: \(note.title)")
            #endif
            await viewModel.generateFlashcards(from: note)
        }
        .alert("About Flashcards", isPresented: $showingInfo) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Tap a card to flip it and reveal the answer. Use the buttons below to navigate between cards.")
        }
    }
    
    // Empty state view when no flashcards are available
    private var emptyStateView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .font(.system(size: 60))
                .foregroundColor(Theme.Colors.secondaryText)
            
            Text("No Flashcards Available")
                .font(Theme.Typography.h3)
                .foregroundColor(Theme.Colors.text)
            
            Text("We couldn't create flashcards from this note. Try adding more structured content like terms and definitions.")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)
            
            Button {
                Task {
                    await viewModel.generateFlashcards(from: note)
                }
            } label: {
                Text("Try Again")
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.sm)
            }
            .buttonStyle(PrimaryButtonStyle())
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
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("AI Study Assistant")
                        .font(Theme.Typography.h2)
                        .foregroundColor(Theme.Colors.primary)
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, Theme.Spacing.sm)
                
                Divider()
                
                // Chat Messages
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVStack(spacing: Theme.Spacing.md) {
                            ForEach(viewModel.messages) { message in
                                ChatMessageBubble(message: message, viewModel: viewModel)
                                    .id(message.id)
                            }
                            
                            // Typing indicator
                            if viewModel.isTyping {
                                HStack {
                                    // AI avatar
                                    Image(systemName: "sparkles")
                                        .foregroundColor(Theme.Colors.primary)
                                        .padding(8)
                                        .background(Theme.Colors.background)
                                        .clipShape(Circle())
                                    
                                    // Message bubble with typing animation
                                    VStack(alignment: .leading) {
                                        Text(viewModel.parseMarkdown(viewModel.typingMessage))
                                            .padding()
                                            .background(Theme.Colors.secondaryBackground)
                                            .foregroundColor(Theme.Colors.text)
                                            .cornerRadius(Theme.Layout.cornerRadius)
                                    }
                                    
                                    Spacer()
                                }
                                .id("typingIndicator")
                            }
                            
                            // Spacer at the bottom to ensure content can scroll above the input bar
                            Color.clear
                                .frame(height: 60)
                                .id("bottomSpacer")
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) { _ in
                        if let lastMessage = viewModel.messages.last {
                            withAnimation {
                                scrollProxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: viewModel.typingMessage) { _ in
                        if viewModel.isTyping {
                            withAnimation {
                                scrollProxy.scrollTo("typingIndicator", anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: keyboardHeight) { _ in
                        withAnimation {
                            scrollProxy.scrollTo("bottomSpacer", anchor: .bottom)
                        }
                    }
                }
                
                Spacer()
            }
            
            VStack(spacing: 0) {
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
                
                // Thinking indicator (moved to bottom)
                if viewModel.chatState.isProcessing && !viewModel.isTyping {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "sparkles")
                            .foregroundColor(Theme.Colors.primary)
                        
                        ProgressView()
                            .scaleEffect(0.8)
                        
                        Text("AI is thinking...")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.secondaryText)
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Colors.secondaryBackground)
                }
                
                // Input Bar
                HStack(spacing: Theme.Spacing.md) {
                    TextField("Ask a question...", text: $viewModel.inputMessage, axis: .vertical)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .focused($isInputFocused)
                        .disabled(viewModel.chatState.isProcessing && !viewModel.isTyping)
                        .submitLabel(.send)
                        .onSubmit {
                            sendMessage()
                        }
                    
                    if viewModel.isTyping {
                        // Stop button
                        Button(action: {
                            viewModel.stopResponse()
                        }) {
                            Image(systemName: "stop.circle.fill")
                                .font(.title2)
                                .foregroundColor(Theme.Colors.error)
                        }
                    } else {
                        // Send button
                        Button(action: sendMessage) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                                .foregroundColor(viewModel.inputMessage.isEmpty || viewModel.chatState.isProcessing ? 
                                                Theme.Colors.secondaryText : Theme.Colors.primary)
                        }
                        .disabled(viewModel.inputMessage.isEmpty || (viewModel.chatState.isProcessing && !viewModel.isTyping))
                    }
                }
                .padding()
                .background(Theme.Colors.secondaryBackground)
            }
        }
        .onAppear {
            #if DEBUG
            print("💬 ChatTab: View appeared for note: \(note.title)")
            #endif
            
            // Add keyboard observers
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { notification in
                if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    keyboardHeight = keyboardFrame.height
                }
            }
            
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in
                keyboardHeight = 0
            }
        }
        .onDisappear {
            // Remove keyboard observers
            NotificationCenter.default.removeObserver(self)
        }
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

// MARK: - Chat Message Bubble
private struct ChatMessageBubble: View {
    let message: ChatMessage
    let viewModel: ChatViewModel
    
    var body: some View {
        VStack(alignment: message.type == .user ? .trailing : .leading, spacing: 4) {
            // Message content
            HStack {
                if message.type == .assistant {
                    // AI avatar
                    Image(systemName: "sparkles")
                        .foregroundColor(Theme.Colors.primary)
                        .padding(8)
                        .background(Theme.Colors.background)
                        .clipShape(Circle())
                    
                    // Message bubble with markdown support
                    VStack(alignment: .leading) {
                        Text(viewModel.parseMarkdown(message.content))
                            .padding()
                            .background(Theme.Colors.secondaryBackground)
                            .foregroundColor(Theme.Colors.text)
                            .cornerRadius(Theme.Layout.cornerRadius)
                    }
                    
                    Spacer()
                } else {
                    Spacer()
                    
                    // Message bubble
                    Text(message.content)
                        .padding()
                        .background(Theme.Colors.primary)
                        .foregroundColor(.white)
                        .cornerRadius(Theme.Layout.cornerRadius)
                    
                    // User avatar
                    Image(systemName: "person.circle.fill")
                        .foregroundColor(Theme.Colors.primary)
                        .padding(8)
                        .background(Theme.Colors.background)
                        .clipShape(Circle())
                }
            }
            
            // Message status and timestamp
            HStack(spacing: 4) {
                if message.type == .user {
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
                
                if message.type == .assistant {
                    Spacer()
                }
            }
            .padding(.horizontal, 8)
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
                .padding(.vertical, 8)
        case .heading2:
            Text(block.content)
                .font(.system(size: fontSize * 1.5, weight: .bold))
                .padding(.vertical, 6)
        case .heading3:
            Text(block.content)
                .font(.system(size: fontSize * 1.25, weight: .bold))
                .padding(.vertical, 4)
        case .heading4:
            Text(block.content)
                .font(.system(size: fontSize * 1.1, weight: .bold))
                .padding(.vertical, 4)
        case .heading5:
            Text(block.content)
                .font(.system(size: fontSize, weight: .bold))
                .padding(.vertical, 4)
        case .heading6:
            Text(block.content)
                .font(.system(size: fontSize * 0.9, weight: .bold))
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
                            // Updated regex to handle any number of digits for minutes
                            if let timeRange = paragraph.range(of: "\\[\\d+:\\d{2}\\]", options: [.regularExpression]) {
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
