import SwiftUI

// MARK: - Note Generation Loading View
struct NoteGenerationLoadingView: View {
    @ObservedObject var progressModel: NoteGenerationProgressModel
    @Environment(\.dismiss) private var dismiss

    let creationType: NoteGenerationProgressModel.NoteCreationType
    let onComplete: () -> Void
    let onCancel: () -> Void

    @State private var showingCancelAlert = false

    init(
        creationType: NoteGenerationProgressModel.NoteCreationType,
        progressModel: NoteGenerationProgressModel,
        onComplete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.creationType = creationType
        self.progressModel = progressModel
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationView {
            ZStack {
                Theme.Colors.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header Section
                    headerSection
                        .padding(.top, Theme.Spacing.lg)

                    // Progress Steps
                    ScrollView {
                        VStack(spacing: Theme.Spacing.md) {
                            ForEach(progressModel.steps) { step in
                                StepProgressRow(
                                    step: step,
                                    status: progressModel.getStepStatus(for: step),
                                    isCurrentStep: step.id == progressModel.currentStep.id,
                                    currentStep: progressModel.currentStep
                                )
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.vertical, Theme.Spacing.xl)
                    }

                    Spacer()

                    // Bottom Section
                    bottomSection
                        .padding(.bottom, Theme.Spacing.xl)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !progressModel.isComplete && progressModel.error == nil {
                        Button("Cancel") {
                            showingCancelAlert = true
                        }
                        .foregroundColor(Theme.Colors.error)
                    }
                }
            }
            .alert("Cancel Note Generation", isPresented: $showingCancelAlert) {
                Button("Continue", role: .cancel) { }
                Button("Cancel", role: .destructive) {
                    onCancel()
                }
            } message: {
                Text("Are you sure you want to cancel? Your progress will be lost.")
            }
            .onChange(of: progressModel.isComplete) { isComplete in
                if isComplete {
                    // Smooth transition with shorter delay for better UX
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        onComplete()
                    }
                }
            }
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Icon
            Image(systemName: creationType.icon)
                .font(.system(size: 48, weight: .medium))
                .foregroundColor(Theme.Colors.primary)
                .padding(.bottom, Theme.Spacing.xs)

            // Title
            Text("Note Generation")
                .font(Theme.Typography.h2)
                .foregroundColor(Theme.Colors.text)

            // Subtitle
            Text("Don't turn off app while generating note")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }

    // MARK: - Bottom Section
    private var bottomSection: some View {
        VStack(spacing: Theme.Spacing.lg) {
            if progressModel.isComplete {
                // Success Message - No manual button, automatic navigation
                VStack(spacing: Theme.Spacing.sm) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(Theme.Colors.success)
                        Text("Note created successfully!")
                            .font(Theme.Typography.body)
                            .fontWeight(.semibold)
                            .foregroundColor(Theme.Colors.text)
                    }

                    Text("Redirecting to your notes...")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
                .padding(.horizontal, Theme.Spacing.lg)
            } else if progressModel.error != nil {
                // Retry Button
                Button(action: {
                    // Reset and retry
                    progressModel.initialize(for: creationType)
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 18, weight: .medium))
                        Text("Try Again")
                            .font(Theme.Typography.body)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: Theme.Layout.buttonHeight)
                    .background(Theme.Colors.primary)
                    .cornerRadius(Theme.Layout.cornerRadius)
                }
                .padding(.horizontal, Theme.Spacing.lg)
            }
        }
    }

    // MARK: - Public Methods
    func updateProgress(step: NoteGenerationProgressModel.GenerationStep, progress: Double = 0.0) {
        if progress > 0 {
            progressModel.updateProgress(for: step, progress: progress)
        } else {
            progressModel.updateStep(step)
        }
    }

    func completeGeneration() {
        progressModel.completeStep()
    }

    func setError(_ message: String) {
        progressModel.setError(message)
    }
}

// MARK: - Step Progress Row
private struct StepProgressRow: View {
    let step: NoteGenerationProgressModel.GenerationStep
    let status: NoteGenerationProgressModel.StepStatus
    let isCurrentStep: Bool
    let currentStep: NoteGenerationProgressModel.GenerationStep

    // Use the current step's progress value if this is the current step, otherwise use the step's own progress
    private var currentStepProgressValue: Double {
        return isCurrentStep ? currentStep.progressValue : step.progressValue
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Status Icon
            statusIcon

            // Content
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack {
                    Text(step.title)
                        .font(Theme.Typography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.Colors.text)

                    Spacer()

                    if isCurrentStep && step.isInProgress {
                        Text("\(Int(currentStepProgressValue * 100))%")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.secondaryText)
                    }
                }

                Text(step.subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
                    .lineLimit(2)

                // Progress Bar
                if isCurrentStep && step.isInProgress {
                    ProgressView(value: currentStepProgressValue)
                        .progressViewStyle(LinearProgressViewStyle(tint: Theme.Colors.primary))
                        .scaleEffect(y: 1.5)
                        .animation(.easeInOut(duration: 0.3), value: currentStepProgressValue)
                } else if status == .completed {
                    Rectangle()
                        .fill(Theme.Colors.success)
                        .frame(height: 3)
                        .cornerRadius(1.5)
                } else {
                    Rectangle()
                        .fill(Theme.Colors.tertiaryBackground)
                        .frame(height: 3)
                        .cornerRadius(1.5)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius)
                .fill(isCurrentStep ? Theme.Colors.cardBackground : Theme.Colors.secondaryBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius)
                .stroke(
                    isCurrentStep ? Theme.Colors.primary.opacity(0.3) : Color.clear,
                    lineWidth: 1
                )
        )
        .animation(.easeInOut(duration: 0.3), value: isCurrentStep)
    }

    private var statusIcon: some View {
        ZStack {
            Circle()
                .fill(iconBackgroundColor)
                .frame(width: 40, height: 40)

            Image(systemName: iconName)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(iconForegroundColor)
        }
    }

    private var iconBackgroundColor: Color {
        switch status {
        case .completed:
            return Theme.Colors.success
        case .inProgress:
            return Theme.Colors.primary
        case .error:
            return Theme.Colors.error
        case .pending:
            return Theme.Colors.tertiaryBackground
        }
    }

    private var iconForegroundColor: Color {
        switch status {
        case .completed, .inProgress:
            return .white
        case .error:
            return .white
        case .pending:
            return Theme.Colors.secondaryText
        }
    }

    private var iconName: String {
        switch status {
        case .completed:
            return "checkmark"
        case .inProgress:
            return step.icon
        case .error:
            return "exclamationmark"
        case .pending:
            return step.icon
        }
    }
}

// MARK: - Preview
#if DEBUG
struct NoteGenerationLoadingView_Previews: PreviewProvider {
    static var previews: some View {
        let audioProgressModel = NoteGenerationProgressModel()
        let youtubeProgressModel = NoteGenerationProgressModel()

        NoteGenerationLoadingView(
            creationType: .audioRecording,
            progressModel: audioProgressModel,
            onComplete: { print("Complete") },
            onCancel: { print("Cancel") }
        )
        .previewDisplayName("Audio Recording")
        .onAppear {
            audioProgressModel.initialize(for: .audioRecording)
        }

        NoteGenerationLoadingView(
            creationType: .youtubeVideo,
            progressModel: youtubeProgressModel,
            onComplete: { print("Complete") },
            onCancel: { print("Cancel") }
        )
        .previewDisplayName("YouTube Video")
        .onAppear {
            youtubeProgressModel.initialize(for: .youtubeVideo)
        }
    }
}
#endif
