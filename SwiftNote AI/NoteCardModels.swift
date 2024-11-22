import SwiftUI

// MARK: - Note Card Configuration
struct NoteCardConfiguration: Identifiable, Equatable {
    let id = UUID()
    var title: String
    let date: Date
    var preview: String
    let sourceType: NoteSourceType
    let isFavorite: Bool
    var tags: [String]
    var audioURL: URL? {
        switch sourceType {
        case .audio, .video:
            let fileManager = FileManager.default
            let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            return documentsPath.appendingPathComponent("\(id).m4a")
        case .text, .upload:
            return nil
        }
    }
    
    var folderName: String? {
        folder?.name
    }
    
    private var folder: Folder?
    
    var folderColor: Color? {
        guard let colorName = folder?.color else { return nil }
        return Color(colorName)
    }
    
    static func == (lhs: NoteCardConfiguration, rhs: NoteCardConfiguration) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.date == rhs.date &&
        lhs.preview == rhs.preview &&
        lhs.sourceType == rhs.sourceType &&
        lhs.isFavorite == rhs.isFavorite &&
        lhs.tags == rhs.tags &&
        lhs.audioURL == rhs.audioURL
    }
    
    // MARK: - Initialization
    init(
        title: String,
        date: Date,
        preview: String,
        sourceType: NoteSourceType,
        isFavorite: Bool = false,
        tags: [String] = [],
        folder: Folder? = nil
    ) {
        self.title = title
        self.date = date
        self.preview = preview
        self.sourceType = sourceType
        self.isFavorite = isFavorite
        self.tags = tags
        self.folder = folder
        
        #if DEBUG
        print("""
        📝 NoteCardConfiguration: Created new configuration
        - Title: \(title)
        - Source Type: \(sourceType)
        - Tags Count: \(tags.count)
        """)
        #endif
    }
    
    // MARK: - Debug Description
    var debugDescription: String {
        """
        NoteCard:
        - ID: \(id)
        - Title: \(title)
        - Date: \(date)
        - Preview: \(preview)
        - Source: \(sourceType)
        - Favorite: \(isFavorite)
        - Tags: \(tags.joined(separator: ", "))
        - Audio URL: \(audioURL?.absoluteString ?? "none")
        """
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
        @State private var currentIndex = 0
        @State private var isShowingAnswer = false
        
        var body: some View {
            VStack(spacing: Theme.Spacing.lg) {
                if !flashcards.isEmpty {
                    ZStack {
                        ForEach(flashcards.indices, id: \.self) { index in
                            if index == currentIndex {
                                FlashcardView(
                                    card: flashcards[index],
                                    isShowingAnswer: $isShowingAnswer
                                )
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing),
                                    removal: .move(edge: .leading)
                                ))
                            }
                        }
                    }
                    .animation(.spring(), value: currentIndex)
                    
                    // Navigation controls
                    HStack(spacing: Theme.Spacing.xl) {
                        Button {
                            withAnimation {
                                currentIndex = max(0, currentIndex - 1)
                                isShowingAnswer = false
                            }
                        } label: {
                            Image(systemName: "arrow.left.circle.fill")
                                .font(.title)
                        }
                        .disabled(currentIndex == 0)
                        
                        Text("\(currentIndex + 1)/\(flashcards.count)")
                            .font(Theme.Typography.caption)
                        
                        Button {
                            withAnimation {
                                currentIndex = min(flashcards.count - 1, currentIndex + 1)
                                isShowingAnswer = false
                            }
                        } label: {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.title)
                        }
                        .disabled(currentIndex == flashcards.count - 1)
                    }
                    .foregroundColor(Theme.Colors.primary)
                }
            }
        }
    }

    private struct FlashcardView: View {
        let card: FlashcardsViewModel.Flashcard
        @Binding var isShowingAnswer: Bool
        
        var body: some View {
            VStack {
                Text(isShowingAnswer ? card.back : card.front)
                    .font(Theme.Typography.body)
                    .padding(Theme.Spacing.xl)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Colors.background)
                    .cornerRadius(Theme.Layout.cornerRadius)
                    .standardShadow()
                    .rotation3DEffect(
                        .degrees(isShowingAnswer ? 180 : 0),
                        axis: (x: 0, y: 1, z: 0)
                    )
                    .onTapGesture {
                        withAnimation(.spring()) {
                            isShowingAnswer.toggle()
                        }
                    }
            }
            .rotation3DEffect(
                .degrees(isShowingAnswer ? 180 : 0),
                axis: (x: 0, y: 1, z: 0)
            )
        }
    }
}

// MARK: - Note Source Type
enum NoteSourceType: String {
    case audio = "mic.fill"
    case text = "doc.text.fill"
    case video = "video.fill"
    case upload = "arrow.up.circle.fill"
    
    var icon: Image {
        Image(systemName: self.rawValue)
    }
    
    var color: Color {
        switch self {
        case .audio: return .blue
        case .text: return .green
        case .video: return .red
        case .upload: return .orange
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
