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
            Text(LocalizedStringKey(cleanMarkdown(question.question)))
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
                        
                        Text(LocalizedStringKey(isCorrect ? "Correct!" : "Incorrect"))
                            .font(Theme.Typography.body)
                            .foregroundColor(isCorrect ? Theme.Colors.success : Theme.Colors.error)
                    }
                    
                    if !isCorrect {
                        Text(LocalizedStringKey("Correct answer: \(cleanMarkdown(question.options[question.correctAnswer]))"))
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
    
    // Enhanced helper function to process markdown for display
    private func cleanMarkdown(_ text: String) -> String {
        var cleanedText = text
        
        // Remove code blocks which don't render well in quiz questions
        let codeBlockPattern = "```[\\s\\S]*?```"
        if let regex = try? NSRegularExpression(pattern: codeBlockPattern, options: []) {
            cleanedText = regex.stringByReplacingMatches(
                in: cleanedText,
                options: [],
                range: NSRange(location: 0, length: cleanedText.utf16.count),
                withTemplate: ""
            )
        }
        
        // Remove horizontal rules
        let hrPattern = "^\\s*[\\*\\-\\_]{3,}\\s*$"
        if let regex = try? NSRegularExpression(pattern: hrPattern, options: [.anchorsMatchLines]) {
            cleanedText = regex.stringByReplacingMatches(
                in: cleanedText,
                options: [],
                range: NSRange(location: 0, length: cleanedText.utf16.count),
                withTemplate: ""
            )
        }
        
        // Clean up excessive whitespace
        cleanedText = cleanedText.replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
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
                Text(LocalizedStringKey(text))
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
