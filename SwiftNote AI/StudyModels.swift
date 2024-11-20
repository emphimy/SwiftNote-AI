// MARK: - Study Models
import SwiftUI

// MARK: - Note Content Model
struct NoteContent: Equatable {
    let rawText: String
    let formattedContent: [ContentBlock]
    let summary: String?
    let highlights: [TextHighlight]
}

// MARK: - Content Block Model
struct ContentBlock: Identifiable, Equatable {
    let id = UUID()
    let type: BlockType
    let content: String
    
    enum BlockType: Equatable {
        case heading1
        case heading2
        case paragraph
        case bulletList
        case numberedList
        case codeBlock(language: String?)
        case quote
    }
}

// MARK: - Text Highlight Model
struct TextHighlight: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let range: Range<String.Index>
    let color: Color
    let note: String?
}

// MARK: - Quiz Models
struct QuizResultsView: View {
    let questions: [QuizViewModel.QuizQuestion]
    let answers: [UUID: Int]
    
    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                Text("Quiz Results")
                    .font(Theme.Typography.h2)
                    .padding()
                
                ForEach(questions) { question in
                    ResultCard(
                        question: question,
                        selectedAnswer: answers[question.id],
                        isCorrect: answers[question.id] == question.correctAnswer
                    )
                }
            }
            .padding()
        }
    }
}

private struct ResultCard: View {
    let question: QuizViewModel.QuizQuestion
    let selectedAnswer: Int?
    let isCorrect: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(question.question)
                .font(Theme.Typography.body)
            
            if let selected = selectedAnswer {
                HStack {
                    Text("Your answer: \(question.options[selected])")
                    Spacer()
                    Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(isCorrect ? Theme.Colors.success : Theme.Colors.error)
                }
            }
            
            if !isCorrect {
                Text("Correct answer: \(question.options[question.correctAnswer])")
                    .foregroundColor(Theme.Colors.success)
            }
        }
        .padding()
        .background(Theme.Colors.secondaryBackground)
        .cornerRadius(Theme.Layout.cornerRadius)
    }
}
