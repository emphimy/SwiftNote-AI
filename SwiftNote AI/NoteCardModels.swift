import SwiftUI

// MARK: - Note Card Configuration
struct NoteCardConfiguration: Identifiable {
    let id: UUID
    var title: String
    let date: Date
    var preview: String
    let sourceType: NoteSourceType
    let isFavorite: Bool
    var tags: [String]
    var metadata: [String: Any]?
    var sourceURL: URL?

    var audioURL: URL? {
        // For audio and recording types, we need to find the audio file
        if sourceType == .audio || sourceType == .recording {
            // First try to use the actual sourceURL if available
            if let url = sourceURL {
                // Check if the file exists at the stored URL
                if FileManager.default.fileExists(atPath: url.path) {
                    #if DEBUG
                    print("📝 NoteCardConfiguration: Using stored sourceURL: \(url.path)")
                    #endif
                    return url
                } else {
                    #if DEBUG
                    print("📝 NoteCardConfiguration: Stored sourceURL not found: \(url.path)")
                    #endif
                }
            }

            // Fallback to trying multiple possible paths
            let fileManager = FileManager.default
            let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]

            // Try multiple possible filename formats
            var possibleFilenames = [
                "\(id).m4a"  // Standard format for recorded files
            ]

            // If we have a sourceURL, also try variations based on its filename
            if let originalURL = sourceURL {
                let originalFilename = originalURL.lastPathComponent

                // Add more possible filenames
                possibleFilenames.append(contentsOf: [
                    originalFilename,                    // Original filename
                    "\(id)-\(originalFilename)"          // ID-prefixed format
                ])

                // If we can extract a UUID from the filename, try those formats too
                if let uuid = extractUUID(from: originalFilename) {
                    possibleFilenames.append(contentsOf: [
                        "\(uuid).m4a",                   // Simple UUID format
                        "\(uuid)-\(originalFilename)"    // UUID-prefixed format for imported files
                    ])
                }
            }

            #if DEBUG
            print("📝 NoteCardConfiguration: Trying multiple possible filenames: \(possibleFilenames)")
            #endif

            // Try each possible filename
            for filename in possibleFilenames {
                let possibleURL = documentsPath.appendingPathComponent(filename)

                #if DEBUG
                print("📝 NoteCardConfiguration: Checking path: \(possibleURL.path)")
                print("📝 NoteCardConfiguration: File exists: \(FileManager.default.fileExists(atPath: possibleURL.path))")
                #endif

                if FileManager.default.fileExists(atPath: possibleURL.path) {
                    #if DEBUG
                    print("📝 NoteCardConfiguration: Found file at: \(possibleURL.path)")
                    #endif
                    return possibleURL
                }
            }

            // If we didn't find any existing file, return the standard path anyway
            // (this maintains backward compatibility with the original implementation)
            let standardURL = documentsPath.appendingPathComponent("\(id).m4a")

            #if DEBUG
            print("📝 NoteCardConfiguration: No existing file found, returning standard path: \(standardURL.path)")
            #endif

            return standardURL
        }

        // For text and upload types, no audio URL
        return nil
    }

    private var folder: Folder?

    var folderName: String? {
        folder?.name
    }

    var folderColor: Color? {
        guard let colorName = folder?.color else { return nil }
        return Color(colorName)
    }

    // MARK: - Initialization
    init(
        id: UUID = UUID(),
        title: String,
        date: Date,
        preview: String,
        sourceType: NoteSourceType,
        isFavorite: Bool = false,
        tags: [String] = [],
        folder: Folder? = nil,
        metadata: [String: Any]? = nil,
        sourceURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.preview = preview
        self.sourceType = sourceType
        self.isFavorite = isFavorite
        self.tags = tags
        self.folder = folder
        self.metadata = metadata
        self.sourceURL = sourceURL

        #if DEBUG
        print("""
        📝 NoteCardConfiguration: Created new configuration
        - ID: \(id.uuidString)
        - Title: \(title)
        - Source Type: \(sourceType)
        - Tags Count: \(tags.count)
        - Folder: \(folder?.name ?? "nil")
        """)
        #endif
    }

    // Extract UUID from filename
    private func extractUUID(from filename: String) -> UUID? {
        // Try to find a UUID pattern in the filename
        let pattern = "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}"
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)

        if let match = regex?.firstMatch(in: filename, options: [], range: NSRange(location: 0, length: filename.count)) {
            let matchRange = match.range
            if let range = Range(matchRange, in: filename) {
                let uuidString = String(filename[range])
                return UUID(uuidString: uuidString)
            }
        }
        return nil
    }


    // MARK: - Quiz Components
    struct QuizContent: View {
        let questions: [QuizViewModel.QuizQuestion]
        @State private var selectedAnswers: [UUID: Int] = [:]
        @State private var showingResults = false

        var body: some View {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    ForEach(questions) { question in
                        QuizQuestionCard(
                            question: question,
                            selectedAnswer: selectedAnswers[question.id],
                            onSelect: { answer in
                                selectedAnswers[question.id] = answer
                            }
                        )
                    }

                    if !questions.isEmpty {
                        Button("Check Answers") {
                            showingResults = true
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
                .padding()
            }
            .sheet(isPresented: $showingResults) {
                QuizResultsView(questions: questions, answers: selectedAnswers)
            }
        }
    }

    private struct QuizQuestionCard: View {
        let question: QuizViewModel.QuizQuestion
        let selectedAnswer: Int?
        let onSelect: (Int) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text(question.question)
                    .font(Theme.Typography.h3)

                ForEach(question.options.indices, id: \.self) { index in
                    Button {
                        onSelect(index)
                    } label: {
                        HStack {
                            Text(question.options[index])
                            Spacer()
                            if selectedAnswer == index {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(Theme.Colors.primary)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius)
                                .fill(selectedAnswer == index ?
                                     Theme.Colors.primary.opacity(0.1) :
                                     Theme.Colors.secondaryBackground)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding()
            .background(Theme.Colors.background)
            .cornerRadius(Theme.Layout.cornerRadius)
            .standardShadow()
        }
    }

    // MARK: - Flashcard Components
    struct FlashcardContent: View {
        let flashcards: [FlashcardsViewModel.Flashcard]
        @ObservedObject var viewModel: FlashcardsViewModel

        var body: some View {
            if !flashcards.isEmpty {
                ZStack {
                    ForEach(flashcards.indices, id: \.self) { index in
                        if index == viewModel.currentIndex {
                            FlashcardView(
                                card: flashcards[index],
                                isShowingAnswer: Binding(
                                    get: { flashcards[index].isRevealed },
                                    set: { newValue in
                                        if newValue != flashcards[index].isRevealed {
                                            viewModel.toggleCard()
                                        }
                                    }
                                )
                            )
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing),
                                removal: .move(edge: .leading)
                            ))
                        }
                    }
                }
                .animation(.spring(), value: viewModel.currentIndex)
            }
        }
    }

    private struct FlashcardView: View {
        let card: FlashcardsViewModel.Flashcard
        @Binding var isShowingAnswer: Bool

        // Fixed dimensions for consistent card size
        private let cardWidth: CGFloat = 320
        private let cardHeight: CGFloat = 200
        private let cornerRadius: CGFloat = 16

        var body: some View {
            ZStack {
                // Card front (question)
                cardFace(card.front, isAnswer: false)
                    .opacity(isShowingAnswer ? 0 : 1)

                // Card back (answer)
                cardFace(card.back, isAnswer: true)
                    .opacity(isShowingAnswer ? 1 : 0)
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            }
            .frame(width: cardWidth, height: cardHeight)
            .rotation3DEffect(
                .degrees(isShowingAnswer ? 180 : 0),
                axis: (x: 0, y: 1, z: 0)
            )
            .onTapGesture {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    isShowingAnswer.toggle()
                }
            }
        }

        // Helper function to create consistent card faces
        private func cardFace(_ content: String, isAnswer: Bool) -> some View {
            VStack(spacing: 0) {
                // Card header
                ZStack {
                    Rectangle()
                        .fill(isAnswer ? Theme.Colors.success : Theme.Colors.primary)
                        .frame(height: 40)

                    Text(isAnswer ? "ANSWER" : "QUESTION")
                        .font(Theme.Typography.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }

                // Card content
                ScrollView {
                    Text(LocalizedStringKey(content))
                        .font(Theme.Typography.body)
                        .multilineTextAlignment(.center)
                        .padding(Theme.Spacing.lg)
                        .frame(maxWidth: .infinity, minHeight: cardHeight - 40 - (Theme.Spacing.lg * 2))
                }
                .background(Theme.Colors.background)
            }
            .frame(width: cardWidth, height: cardHeight)
            .cornerRadius(cornerRadius)
            .standardShadow()
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(isAnswer ? Theme.Colors.success : Theme.Colors.primary, lineWidth: 1)
            )
        }
    }

}

extension NoteCardConfiguration: Equatable {
    static func == (lhs: NoteCardConfiguration, rhs: NoteCardConfiguration) -> Bool {
        guard lhs.id == rhs.id,
              lhs.title == rhs.title,
              lhs.date == rhs.date,
              lhs.preview == rhs.preview,
              lhs.sourceType == rhs.sourceType,
              lhs.isFavorite == rhs.isFavorite,
              lhs.tags == rhs.tags,
              lhs.folder?.objectID == rhs.folder?.objectID else {
            return false
        }

        // Compare metadata dictionaries if they exist
        if let lhsMetadata = lhs.metadata, let rhsMetadata = rhs.metadata {
            return NSDictionary(dictionary: lhsMetadata).isEqual(to: rhsMetadata)
        } else {
            // If both are nil, return true. If only one is nil, return false
            return lhs.metadata == nil && rhs.metadata == nil
        }
    }
}

// MARK: - Note Source Type
enum NoteSourceType: String {
    case audio = "audio"
    case text = "text"
    case video = "video"
    case upload = "upload"
    case recording = "recording"
    case web = "web"

    var icon: Image {
        let iconName: String = {
            switch self {
            case .audio: return "waveform"
            case .recording: return "mic"
            case .text: return "doc"
            case .video: return "play.circle.fill"
            case .upload: return "arrow.up.circle.fill"
            case .web: return "globe"
            }
        }()
        return Image(systemName: iconName)
    }

    var color: Color {
        switch self {
        case .audio, .recording: return .blue
        case .text: return .green
        case .video: return .red
        case .upload: return .orange
        case .web: return .purple
        }
    }
}

// MARK: - Card Actions Protocol
protocol CardActions {
    func onFavorite()
    func onShare()
    func onDelete()
    func onTagSelected(_ tag: String)
}

// MARK: - Action Card Item
struct ActionCardItem: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    // MARK: - Debug Description
    var debugDescription: String {
        "ActionCardItem: \(title) with icon \(icon)"
    }
}
