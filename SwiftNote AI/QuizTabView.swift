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
    
    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text("Question \(currentIndex + 1) of \(totalQuestions)")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
            
            Text(question.question)
                .font(Theme.Typography.h3)
                .multilineTextAlignment(.center)
                .padding(.vertical, Theme.Spacing.sm)
            
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(question.options.indices, id: \.self) { index in
                    AnswerOptionButton(
                        text: question.options[index],
                        isSelected: selectedAnswer == index,
                        action: { onSelect(index) }
                    )
                }
            }
            
            Button("Submit Answer", action: onSubmit)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selectedAnswer == nil)
        }
    }
}

// MARK: - Answer Option Button
private struct AnswerOptionButton: View {
    let text: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(text)
                    .font(Theme.Typography.body)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.Colors.primary)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius)
                    .fill(isSelected ? Theme.Colors.primary.opacity(0.1) : Theme.Colors.secondaryBackground)
            )
        }
        .buttonStyle(PlainButtonStyle())
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
