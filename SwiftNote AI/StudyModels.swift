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
        case heading3
        case heading4
        case heading5
        case heading6
        case paragraph
        case bulletList
        case numberedList
        case codeBlock(language: String?)
        case quote
        case horizontalRule
        case table(headers: [String], rows: [[String]])
        case taskList(checked: Bool)
        case formattedText(style: TextStyle)
    }
}

enum TextStyle: Equatable {
    case bold
    case italic
    case boldItalic
    case strikethrough
    case link(url: String)
    case image(url: String, alt: String)
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
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                // Performance Summary
                performanceSummary
                
                // Question Results
                questionResults
                
                // Action Buttons
                actionButtons
            }
            .padding()
        }
        .navigationTitle("Quiz Results")
    }
    
    private var performanceSummary: some View {
        let score = calculateScore()
        
        return VStack(spacing: Theme.Spacing.sm) {
            Text("\(Int(score.percentage))%")
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(score.color)
            
            Text("\(score.correct) correct out of \(questions.count)")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
        }
        .padding()
        .background(Theme.Colors.secondaryBackground)
        .cornerRadius(Theme.Layout.cornerRadius)
    }
    
    private var questionResults: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Question Review")
                .font(Theme.Typography.h3)
            
            ForEach(questions) { question in
                ResultCard(
                    question: question,
                    selectedAnswer: answers[question.id],
                    isCorrect: answers[question.id] == question.correctAnswer
                )
            }
        }
    }
    
    private var actionButtons: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button("Review Incorrect") {
                #if DEBUG
                print("📝 QuizResults: Review incorrect answers requested")
                #endif
                // Scroll to first incorrect answer
            }
            .buttonStyle(SecondaryButtonStyle())
            
            Button("Done") {
                #if DEBUG
                print("📝 QuizResults: Dismissing results view")
                #endif
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.top, Theme.Spacing.lg)
    }
    
    private func calculateScore() -> (percentage: Double, correct: Int, color: Color) {
        let correctCount = answers.filter { pair in
            guard let question = questions.first(where: { $0.id == pair.key }) else {
                #if DEBUG
                print("📝 QuizResults: Warning - No matching question found for id: \(pair.key)")
                #endif
                return false
            }
            return pair.value == question.correctAnswer
        }.count
        
        let percentage = Double(correctCount) / Double(questions.count) * 100
        
        #if DEBUG
        print("""
        📝 QuizResults: Score calculation:
        - Correct answers: \(correctCount)
        - Total questions: \(questions.count)
        - Percentage: \(percentage)%
        """)
        #endif
        
        let color: Color = {
            #if DEBUG
            print("📝 QuizResults: Calculating color for percentage: \(percentage)%")
            #endif
            
            switch percentage {
            case 90...100:
                #if DEBUG
                print("📝 QuizResults: Excellent performance - using success color")
                #endif
                return Theme.Colors.success
            case 70..<90:
                #if DEBUG
                print("📝 QuizResults: Good performance - using primary color")
                #endif
                return Theme.Colors.primary
            default:
                #if DEBUG
                print("📝 QuizResults: Needs improvement - using error color")
                #endif
                return Theme.Colors.error
            }
        }()
        
        return (percentage, correctCount, color)
    }
}

private struct ResultCard: View {
    let question: QuizViewModel.QuizQuestion
    let selectedAnswer: Int?
    let isCorrect: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(isCorrect ? Theme.Colors.success : Theme.Colors.error)
                
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(question.question)
                        .font(Theme.Typography.body)
                    
                    if let selected = selectedAnswer {
                        Text("Your answer: \(question.options[selected])")
                            .font(Theme.Typography.caption)
                            .foregroundColor(isCorrect ? Theme.Colors.success : Theme.Colors.error)
                        
                        if !isCorrect {
                            Text("Correct: \(question.options[question.correctAnswer])")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.success)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Theme.Colors.secondaryBackground)
        .cornerRadius(Theme.Layout.cornerRadius)
    }
}
