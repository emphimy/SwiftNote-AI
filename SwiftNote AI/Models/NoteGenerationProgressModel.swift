import SwiftUI
import Foundation

// MARK: - Note Generation Progress Model
@MainActor
class NoteGenerationProgressModel: ObservableObject {
    @Published var currentStep: GenerationStep = .idle
    @Published var steps: [GenerationStep] = []
    @Published var progress: Double = 0.0
    @Published var isComplete: Bool = false
    @Published var error: String?

    // Flag to prevent reset during completion transition
    private var isTransitioning: Bool = false

    // MARK: - Generation Steps
    enum GenerationStep: Identifiable, Equatable {
        case idle
        case uploading(progress: Double)
        case transcribing(progress: Double)
        case processing(progress: Double)
        case generating(progress: Double)
        case saving(progress: Double)
        case complete
        case error(String)

        var id: String {
            switch self {
            case .idle: return "idle"
            case .uploading: return "uploading"
            case .transcribing: return "transcribing"
            case .processing: return "processing"
            case .generating: return "generating"
            case .saving: return "saving"
            case .complete: return "complete"
            case .error: return "error"
            }
        }

        var title: String {
            switch self {
            case .idle: return "Preparing..."
            case .uploading: return "Uploading content"
            case .transcribing: return "Transcribing audio"
            case .processing: return "Processing content"
            case .generating: return "Generating note"
            case .saving: return "Saving note"
            case .complete: return "Complete"
            case .error: return "Error occurred"
            }
        }

        var subtitle: String {
            switch self {
            case .idle: return "Getting ready to process your content"
            case .uploading: return "This may take a few seconds"
            case .transcribing: return "Converting speech to text"
            case .processing: return "Analyzing your content"
            case .generating: return "Creating AI-powered notes"
            case .saving: return "Finalizing your note"
            case .complete: return "Your note has been created successfully"
            case .error(let message): return message
            }
        }

        var icon: String {
            switch self {
            case .idle: return "clock"
            case .uploading: return "arrow.up.circle"
            case .transcribing: return "waveform"
            case .processing: return "gearshape"
            case .generating: return "brain"
            case .saving: return "checkmark.circle"
            case .complete: return "checkmark.circle.fill"
            case .error: return "exclamationmark.triangle"
            }
        }

        var isCompleted: Bool {
            switch self {
            case .complete: return true
            case .error: return true
            default: return false
            }
        }

        var isInProgress: Bool {
            switch self {
            case .uploading, .transcribing, .processing, .generating, .saving:
                return true
            default:
                return false
            }
        }

        var progressValue: Double {
            switch self {
            case .uploading(let progress): return progress
            case .transcribing(let progress): return progress
            case .processing(let progress): return progress
            case .generating(let progress): return progress
            case .saving(let progress): return progress
            case .complete: return 1.0
            default: return 0.0
            }
        }
    }

    // MARK: - Note Creation Types
    enum NoteCreationType {
        case audioRecording
        case audioUpload
        case textScan
        case pdfImport
        case youtubeVideo
        case webLink

        var steps: [GenerationStep] {
            switch self {
            case .audioRecording:
                return [
                    .transcribing(progress: 0.0),
                    .generating(progress: 0.0),
                    .saving(progress: 0.0)
                ]
            case .audioUpload:
                return [
                    .uploading(progress: 0.0),
                    .transcribing(progress: 0.0),
                    .generating(progress: 0.0),
                    .saving(progress: 0.0)
                ]
            case .textScan:
                return [
                    .processing(progress: 0.0),
                    .generating(progress: 0.0),
                    .saving(progress: 0.0)
                ]
            case .pdfImport:
                return [
                    .uploading(progress: 0.0),
                    .processing(progress: 0.0),
                    .generating(progress: 0.0),
                    .saving(progress: 0.0)
                ]
            case .youtubeVideo:
                return [
                    .transcribing(progress: 0.0),
                    .generating(progress: 0.0),
                    .saving(progress: 0.0)
                ]
            case .webLink:
                return [
                    .processing(progress: 0.0),
                    .generating(progress: 0.0),
                    .saving(progress: 0.0)
                ]
            }
        }

        var title: String {
            switch self {
            case .audioRecording: return "Audio Recording"
            case .audioUpload: return "Audio Import"
            case .textScan: return "Text Scanning"
            case .pdfImport: return "PDF Import"
            case .youtubeVideo: return "YouTube Video"
            case .webLink: return "Web Content"
            }
        }

        var icon: String {
            switch self {
            case .audioRecording: return "mic.circle.fill"
            case .audioUpload: return "waveform.circle.fill"
            case .textScan: return "doc.text.viewfinder"
            case .pdfImport: return "doc.circle.fill"
            case .youtubeVideo: return "play.circle.fill"
            case .webLink: return "link.circle.fill"
            }
        }
    }

    // MARK: - Initialization
    func initialize(for type: NoteCreationType) {
        self.steps = type.steps
        self.currentStep = .idle
        self.progress = 0.0
        self.isComplete = false
        self.error = nil

        #if DEBUG
        print("📊 NoteGenerationProgress: Initialized for \(type.title) with \(steps.count) steps")
        #endif
    }

    // MARK: - Reset
    func reset() {
        // Don't reset if we're transitioning to prevent visual flash
        guard !isTransitioning else {
            #if DEBUG
            print("📊 NoteGenerationProgress: Skipping reset - transition in progress")
            #endif
            return
        }

        self.steps = []
        self.currentStep = .idle
        self.progress = 0.0
        self.isComplete = false
        self.error = nil

        #if DEBUG
        print("📊 NoteGenerationProgress: Reset to initial state")
        #endif
    }

    // MARK: - Progress Updates
    func updateStep(_ step: GenerationStep) {
        withAnimation(.easeInOut(duration: 0.3)) {
            self.currentStep = step

            // Update overall progress
            if let stepIndex = steps.firstIndex(where: { $0.id == step.id }) {
                let baseProgress = Double(stepIndex) / Double(steps.count)
                let stepProgress = step.progressValue / Double(steps.count)
                self.progress = baseProgress + stepProgress
            }

            // Check if complete
            if case .complete = step {
                self.isComplete = true
                self.progress = 1.0
            } else if case .error(let message) = step {
                self.error = message
            }
        }

        #if DEBUG
        print("📊 NoteGenerationProgress: Updated to step \(step.title) with progress \(progress)")
        #endif
    }

    func updateProgress(for stepType: GenerationStep, progress: Double) {
        let clampedProgress = max(0.0, min(1.0, progress))

        let updatedStep: GenerationStep
        switch stepType {
        case .uploading:
            updatedStep = .uploading(progress: clampedProgress)
        case .transcribing:
            updatedStep = .transcribing(progress: clampedProgress)
        case .processing:
            updatedStep = .processing(progress: clampedProgress)
        case .generating:
            updatedStep = .generating(progress: clampedProgress)
        case .saving:
            updatedStep = .saving(progress: clampedProgress)
        default:
            return
        }

        updateStep(updatedStep)
    }

    func completeStep() {
        // Set transitioning flag to prevent reset during completion
        isTransitioning = true
        updateStep(.complete)
    }

    func setError(_ message: String) {
        updateStep(.error(message))
    }

    // MARK: - Transition Management
    func allowReset() {
        isTransitioning = false
        #if DEBUG
        print("📊 NoteGenerationProgress: Transition complete, reset allowed")
        #endif
    }

    func forceReset() {
        isTransitioning = false
        reset()
    }

    // MARK: - Helper Methods
    func getStepStatus(for step: GenerationStep) -> StepStatus {
        // If we're in complete state, all steps should be marked as completed
        if case .complete = currentStep {
            return .completed
        }

        // If we're in error state, mark current step as error
        if case .error = currentStep, step.id == currentStep.id {
            return .error
        }

        guard let currentIndex = steps.firstIndex(where: { $0.id == currentStep.id }),
              let stepIndex = steps.firstIndex(where: { $0.id == step.id }) else {
            return .pending
        }

        if stepIndex < currentIndex {
            return .completed
        } else if stepIndex == currentIndex {
            return currentStep.isInProgress ? .inProgress : .pending
        } else {
            return .pending
        }
    }

    enum StepStatus {
        case pending
        case inProgress
        case completed
        case error
    }
}
