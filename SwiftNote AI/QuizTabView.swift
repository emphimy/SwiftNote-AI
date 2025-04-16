import SwiftUI
import CoreData
import Combine

// MARK: - Quiz Tab View
struct QuizTabView: View {
    let note: NoteCardConfiguration
    @StateObject private var viewModel: QuizGeneratorViewModel
    @Environment(\.toastManager) private var toastManager
    
    init(note: NoteCardConfiguration) {
        self.note = note
        self._viewModel = StateObject(wrappedValue: QuizGeneratorViewModel(
            context: PersistenceController.shared.container.viewContext,
            noteId: note.id,
            content: note.preview
        ))
    }
    
    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            switch viewModel.loadingState {
            case .loading(let message):
                LoadingIndicator(message: message)
                
            case .error(let message):
                ErrorView(
                    error: NSError(domain: "Quiz", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: message
                    ])
                ) {
                    Task { @MainActor in
                        try? await viewModel.generateQuiz()
                    }
                }
                
            case .success, .idle:
                if viewModel.questions.isEmpty {
                    EmptyQuizView {
                        Task { @MainActor in
                            try? await viewModel.generateQuiz()
                        }
                    }
                } else {
                    QuizContentView(viewModel: viewModel)
                }
            }
            
            if let analytics = viewModel.analytics {
                QuizAnalyticsView(analytics: analytics)
            }
        }
        .padding()
    }
}

// MARK: - Empty Quiz View
private struct EmptyQuizView: View {
    let onGenerate: () -> Void
    
    var body: some View {
        EmptyStateView(
            icon: "questionmark.circle",
            title: "No Quiz Available",
            message: "Tap to generate quiz questions from your note.",
            actionTitle: "Generate Quiz",
            action: onGenerate
        )
    }
}

// MARK: - Quiz Content View
private struct QuizContentView: View {
    @ObservedObject var viewModel: QuizGeneratorViewModel
    @Environment(\.toastManager) private var toastManager
    
    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView(
                value: Double(viewModel.currentQuestionIndex + 1),
                total: Double(viewModel.questions.count)
            )
            .tint(Theme.Colors.primary)
            
            if let question = viewModel.questions[safe: viewModel.currentQuestionIndex] {
                QuizQuestionView(
                    question: question,
                    currentIndex: viewModel.currentQuestionIndex,
                    totalQuestions: viewModel.questions.count,
                    selectedAnswer: viewModel.selectedAnswer,
                    onSelect: { viewModel.selectedAnswer = $0 },
                    onSubmit: submitAnswer
                )
            }
        }
    }
    
    private func submitAnswer() {
        guard let selectedAnswer = viewModel.selectedAnswer else {
            toastManager.show("Please select an answer", type: .warning)
            return
        }
        
        Task {
            do {
                try await viewModel.submitAnswer(selectedAnswer)
            } catch {
                toastManager.show(error.localizedDescription, type: .error)
            }
        }
    }
}

// MARK: - Quiz Question View
private struct QuizQuestionView: View {
    let question: QuizQuestion
    let currentIndex: Int
    let totalQuestions: Int
    let selectedAnswer: Int?
    let onSelect: (Int) -> Void
    let onSubmit: () -> Void
    
    // Add state to track if answer is submitted and feedback is showing
    @State private var isAnswerSubmitted = false
    @State private var isCorrect = false
    
    // Check if this is the final question
    private var isFinalQuestion: Bool {
        return currentIndex == totalQuestions - 1
    }
    
    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text("Question \(currentIndex + 1) of \(totalQuestions)")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
            
            // Clean markdown from question text
            Text(cleanMarkdown(question.question))
                .font(Theme.Typography.h3)
                .multilineTextAlignment(.center)
                .padding(.vertical, Theme.Spacing.sm)
            
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(question.options.indices, id: \.self) { index in
                    AnswerOptionButton(
                        text: cleanMarkdown(question.options[index]),
                        isSelected: selectedAnswer == index,
                        isCorrect: isAnswerSubmitted ? index == question.correctAnswer : nil,
                        isIncorrect: isAnswerSubmitted ? selectedAnswer == index && index != question.correctAnswer : nil,
                        action: { 
                            if !isAnswerSubmitted {
                                onSelect(index)
                            }
                        }
                    )
                }
            }
            
            if isAnswerSubmitted {
                // Show feedback when answer is submitted
                VStack(spacing: Theme.Spacing.sm) {
                    HStack {
                        Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(isCorrect ? Theme.Colors.success : Theme.Colors.error)
                        
                        Text(isCorrect ? "Correct!" : "Incorrect")
                            .font(Theme.Typography.body)
                            .foregroundColor(isCorrect ? Theme.Colors.success : Theme.Colors.error)
                    }
                    
                    if !isCorrect {
                        Text("Correct answer: \(cleanMarkdown(question.options[question.correctAnswer]))")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.secondaryText)
                    }
                    
                    if isFinalQuestion {
                        Button("View Results") {
                            onSubmit()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.top, Theme.Spacing.sm)
                    } else {
                        Button("Next Question") {
                            isAnswerSubmitted = false
                            onSubmit()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.top, Theme.Spacing.sm)
                    }
                }
                .padding()
                .background(Theme.Colors.secondaryBackground)
                .cornerRadius(Theme.Layout.cornerRadius)
            } else {
                // Show submit button when answer is not submitted
                Button("Submit Answer") {
                    guard let selected = selectedAnswer else { return }
                    isCorrect = selected == question.correctAnswer
                    isAnswerSubmitted = true
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selectedAnswer == nil)
            }
        }
    }
    
    // Enhanced helper function to clean markdown from text
    private func cleanMarkdown(_ text: String) -> String {
        var cleanedText = text
        
        // First, specifically handle header markdown (## and ###)
        let headerPattern = "(#{1,6})\\s+(.+?)(?:\\n|$)"
        if let headerRegex = try? NSRegularExpression(pattern: headerPattern, options: [.anchorsMatchLines]) {
            let range = NSRange(location: 0, length: cleanedText.utf16.count)
            let matches = headerRegex.matches(in: cleanedText, options: [], range: range)
            
            for match in matches.reversed() {
                if let contentRange = Range(match.range(at: 2), in: cleanedText),
                   let matchRange = Range(match.range, in: cleanedText) {
                    let headerContent = String(cleanedText[contentRange])
                    cleanedText.replaceSubrange(matchRange, with: headerContent)
                }
            }
        }
        
        // Remove markdown formatting with more comprehensive patterns
        let markdownPatterns = [
            // Headers (already handled above, but keeping as fallback)
            "#{1,6}\\s+(.+?)(?:\\n|$)",
            
            // Emphasis
            "\\*\\*(.+?)\\*\\*", // Bold
            "\\*(.+?)\\*",       // Italic
            "__(.+?)__",         // Bold with underscores
            "_(.+?)_",           // Italic with underscores
            
            // Code
            "```[\\s\\S]*?```", // Code blocks
            "`(.+?)`",       // Inline code
            
            // Links
            "\\[(.+?)\\]\\(.+?\\)", // Links with text
            "<(.+?)>",         // Bare links
            
            // Lists
            "^\\s*[\\*\\-\\+]\\s+(.+?)$", // Unordered list items
            "^\\s*\\d+\\.\\s+(.+?)$",     // Ordered list items
            
            // Blockquotes
            "^\\s*>\\s+(.+?)$",
            
            // Horizontal rules
            "^\\s*[\\*\\-\\_]{3,}\\s*$"
        ]
        
        // Handle special cases that need specific replacements
        if let linkRegex = try? NSRegularExpression(pattern: "\\[(.+?)\\]\\((.+?)\\)", options: []) {
            let range = NSRange(location: 0, length: cleanedText.utf16.count)
            let matches = linkRegex.matches(in: cleanedText, options: [], range: range)
            
            for match in matches.reversed() {
                if let textRange = Range(match.range(at: 1), in: cleanedText),
                   let matchRange = Range(match.range, in: cleanedText) {
                    let linkText = String(cleanedText[textRange])
                    cleanedText.replaceSubrange(matchRange, with: linkText)
                }
            }
        }
        
        // Then handle general patterns
        for pattern in markdownPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) {
                let range = NSRange(location: 0, length: cleanedText.utf16.count)
                let matches = regex.matches(in: cleanedText, options: [], range: range)
                
                for match in matches.reversed() {
                    if match.numberOfRanges > 1, 
                       let captureRange = Range(match.range(at: 1), in: cleanedText),
                       let matchRange = Range(match.range, in: cleanedText) {
                        let capturedText = String(cleanedText[captureRange])
                        cleanedText.replaceSubrange(matchRange, with: capturedText)
                    } else if let matchRange = Range(match.range, in: cleanedText) {
                        // For patterns without capture groups, just remove the markdown
                        cleanedText.replaceSubrange(matchRange, with: "")
                    }
                }
            }
        }
        
        // Simple direct replacement for any remaining ## or ### that might be escaped or not caught by regex
        cleanedText = cleanedText.replacingOccurrences(of: "##", with: "")
        cleanedText = cleanedText.replacingOccurrences(of: "###", with: "")
        
        // Clean up any remaining special characters and extra whitespace
        cleanedText = cleanedText.replacingOccurrences(of: "\\", with: "")
        cleanedText = cleanedText.replacingOccurrences(of: "  ", with: " ")
        cleanedText = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleanedText
    }
}

// MARK: - Answer Option Button
private struct AnswerOptionButton: View {
    let text: String
    let isSelected: Bool
    let isCorrect: Bool?
    let isIncorrect: Bool?
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(text)
                    .font(Theme.Typography.body)
                    .multilineTextAlignment(.leading)
                Spacer()
                
                // Show appropriate icon based on state
                if let isCorrect = isCorrect, isCorrect {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.Colors.success)
                } else if let isIncorrect = isIncorrect, isIncorrect {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.Colors.error)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.Colors.primary)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius)
                    .fill(backgroundColor)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // Compute background color based on state
    private var backgroundColor: Color {
        if let isCorrect = isCorrect, isCorrect {
            return Theme.Colors.success.opacity(0.1)
        } else if let isIncorrect = isIncorrect, isIncorrect {
            return Theme.Colors.error.opacity(0.1)
        } else if isSelected {
            return Theme.Colors.primary.opacity(0.1)
        } else {
            return Theme.Colors.secondaryBackground
        }
    }
}

// MARK: - Quiz Analytics View
private struct QuizAnalyticsView: View {
    let analytics: QuizPerformanceData
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(analytics.title ?? "Quiz Performance")
                .font(Theme.Typography.h3)
            
            HStack {
                ScoreCard(
                    title: "Score",
                    value: "\(Int(analytics.averageScore))%",
                    detail: nil
                )
                
                Spacer()
                
                ScoreCard(
                    title: "Correct Answers",
                    value: "\(analytics.correctAnswers)",
                    detail: "of \(analytics.totalQuestions)"
                )
            }
            .padding()
            .background(Theme.Colors.secondaryBackground)
            .cornerRadius(Theme.Layout.cornerRadius)
        }
        .padding()
        .background(Theme.Colors.background)
        .cornerRadius(Theme.Layout.cornerRadius)
        .standardShadow()
    }
}

// MARK: - Score Card
private struct ScoreCard: View {
    let title: String
    let value: String
    let detail: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
            
            Text(value)
                .font(Theme.Typography.h2)
                .foregroundColor(Theme.Colors.primary)
            
            if let detail = detail {
                Text(detail)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.tertiaryText)
            }
        }
    }
}

// MARK: - Array Extension
private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
