import SwiftUI
import Foundation

// MARK: - Note Generation Wrapper
struct NoteGenerationWrapper: View {
    let creationType: NoteGenerationProgressModel.NoteCreationType
    let processAction: (@MainActor @escaping (NoteGenerationProgressModel.GenerationStep, Double) -> Void, @MainActor @escaping () -> Void, @MainActor @escaping (String) -> Void) async -> Void
    let onComplete: @MainActor () -> Void
    let onCancel: @MainActor () -> Void

    @StateObject private var progressModel = NoteGenerationProgressModel()
    @State private var isProcessing = false

    var body: some View {
        NoteGenerationLoadingView(
            creationType: creationType,
            progressModel: progressModel,
            onComplete: onComplete,
            onCancel: onCancel
        )
        .onAppear {
            progressModel.initialize(for: creationType)
            startProcessing()
        }
    }

    private func startProcessing() {
        guard !isProcessing else { return }
        isProcessing = true

        Task {
            await processAction(
                updateProgress,
                completeGeneration,
                setError
            )
        }
    }

    @MainActor
    private func updateProgress(_ step: NoteGenerationProgressModel.GenerationStep, _ progress: Double) {
        progressModel.updateProgress(for: step, progress: progress)
    }

    @MainActor
    private func completeGeneration() {
        progressModel.completeStep()
    }

    @MainActor
    private func setError(_ message: String) {
        progressModel.setError(message)
    }
}

// MARK: - Note Generation Coordinator
@MainActor
class NoteGenerationCoordinator: ObservableObject {
    @Published var isShowingLoadingView = false
    @Published var currentCreationType: NoteGenerationProgressModel.NoteCreationType?

    @Published var progressModel = NoteGenerationProgressModel()
    private var onCompleteCallback: (@MainActor () -> Void)?
    private var onCancelCallback: (@MainActor () -> Void)?
    private var isCompleting = false // Flag to prevent resets during completion

    // MARK: - Public Methods
    func startGeneration(
        type: NoteGenerationProgressModel.NoteCreationType,
        onComplete: @MainActor @escaping () -> Void,
        onCancel: @MainActor @escaping () -> Void
    ) {
        // Only reset if we're not currently showing a loading view and not completing
        // This prevents reset during view transitions
        if !isShowingLoadingView && !isCompleting {
            reset()
        }

        self.currentCreationType = type
        self.onCompleteCallback = onComplete
        self.onCancelCallback = onCancel

        // Initialize the progress model for this creation type
        progressModel.initialize(for: type)

        self.isShowingLoadingView = true

        #if DEBUG
        print("🎬 NoteGenerationCoordinator: Starting generation for \(type.title)")
        #endif
    }

    func updateProgress(step: NoteGenerationProgressModel.GenerationStep, progress: Double = 0.0) {
        #if DEBUG
        print("🎬 NoteGenerationCoordinator: Updating progress for \(step.title) with progress \(progress)")
        #endif
        progressModel.updateProgress(for: step, progress: progress)
    }

    func updateStep(_ step: NoteGenerationProgressModel.GenerationStep) {
        #if DEBUG
        print("🎬 NoteGenerationCoordinator: Updating step to \(step.title)")
        #endif
        progressModel.updateStep(step)
    }

    func completeGeneration() {
        #if DEBUG
        print("🎬 NoteGenerationCoordinator: Completing generation")
        #endif
        progressModel.completeStep()
    }

    func setError(_ message: String) {
        #if DEBUG
        print("🎬 NoteGenerationCoordinator: Setting error: \(message)")
        #endif
        progressModel.setError(message)
    }

    func cancel() {
        isShowingLoadingView = false
        onCancelCallback?()
        // Force reset on cancel since user explicitly cancelled
        progressModel.forceReset()
        reset()
    }

    func complete() {
        // Set flag to prevent any resets during completion
        isCompleting = true

        // Call completion callback first
        onCompleteCallback?()

        // Delay dismissal to allow smooth transition animation
        Task {
            // Wait for navigation to start
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

            await MainActor.run {
                // Dismiss the loading view after navigation starts
                isShowingLoadingView = false
            }

            // Wait longer before reset to ensure view is fully dismissed
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

            await MainActor.run {
                isCompleting = false
                // Allow progress model reset and perform clean reset
                if !isShowingLoadingView {
                    progressModel.allowReset()
                    reset()
                }
            }
        }
    }

    private func reset() {
        // Don't reset if we're in the middle of completing
        guard !isCompleting else {
            #if DEBUG
            print("🎬 NoteGenerationCoordinator: Skipping reset - completion in progress")
            #endif
            return
        }

        #if DEBUG
        print("🎬 NoteGenerationCoordinator: Performing reset")
        #endif

        currentCreationType = nil
        progressModel.reset()
        onCompleteCallback = nil
        onCancelCallback = nil
    }

    // MARK: - View Builder
    func makeLoadingView() -> some View {
        Group {
            if let creationType = currentCreationType {
                NoteGenerationLoadingView(
                    creationType: creationType,
                    progressModel: progressModel,
                    onComplete: complete,
                    onCancel: cancel
                )
            } else {
                EmptyView()
            }
        }
    }
}

// MARK: - View Extension for Easy Integration
extension View {
    func noteGenerationLoading(
        coordinator: NoteGenerationCoordinator
    ) -> some View {
        self.fullScreenCover(isPresented: Binding(
            get: { coordinator.isShowingLoadingView },
            set: { coordinator.isShowingLoadingView = $0 }
        )) {
            coordinator.makeLoadingView()
        }
    }
}

// MARK: - Helper Functions for Integration
struct NoteGenerationHelpers {

    // MARK: - Audio Recording Integration
    static func processAudioRecording(
        recordingURL: URL,
        selectedLanguage: Language,
        transcriptionService: AudioTranscriptionService,
        noteGenerationService: NoteGenerationService,
        updateProgress: @MainActor @escaping (NoteGenerationProgressModel.GenerationStep, Double) -> Void,
        onComplete: @MainActor @escaping () -> Void,
        onError: @MainActor @escaping (String) -> Void
    ) async {
        do {
            // Step 1: Transcribing
            await updateProgress(.transcribing(progress: 0.0), 0.0)

            let result = try await transcriptionService.transcribeAudioWithTimestamps(fileURL: recordingURL)
            let transcript = result.text

            await updateProgress(.transcribing(progress: 1.0), 1.0)

            // Step 2: Generating note
            await updateProgress(.generating(progress: 0.0), 0.0)

            let noteContent = try await noteGenerationService.generateNote(from: transcript, detectedLanguage: selectedLanguage.code)

            await updateProgress(.generating(progress: 0.5), 0.5)

            let title = try await noteGenerationService.generateTitle(from: transcript, detectedLanguage: selectedLanguage.code)

            await updateProgress(.generating(progress: 1.0), 1.0)

            // Step 3: Saving
            await updateProgress(.saving(progress: 0.0), 0.0)

            // Save note logic here
            try await saveNoteToDatabase(title: title, content: noteContent, transcript: transcript)

            await updateProgress(.saving(progress: 1.0), 1.0)

            await onComplete()

        } catch {
            await onError(error.localizedDescription)
        }
    }

    // MARK: - YouTube Video Integration
    static func processYouTubeVideo(
        videoId: String,
        selectedLanguage: Language,
        youtubeService: YouTubeService,
        noteGenerationService: NoteGenerationService,
        updateProgress: @MainActor @escaping (NoteGenerationProgressModel.GenerationStep, Double) -> Void,
        onComplete: @MainActor @escaping () -> Void,
        onError: @MainActor @escaping (String) -> Void
    ) async {
        do {
            // Step 1: Transcribing
            await updateProgress(.transcribing(progress: 0.0), 0.0)

            let (transcript, _) = try await youtubeService.getTranscript(videoId: videoId)

            await updateProgress(.transcribing(progress: 1.0), 1.0)

            // Step 2: Generating note
            await updateProgress(.generating(progress: 0.0), 0.0)

            let noteContent = try await noteGenerationService.generateNote(from: transcript, detectedLanguage: selectedLanguage.code)

            await updateProgress(.generating(progress: 0.5), 0.5)

            let title = try await noteGenerationService.generateTitle(from: transcript, detectedLanguage: selectedLanguage.code)

            await updateProgress(.generating(progress: 1.0), 1.0)

            // Step 3: Saving
            await updateProgress(.saving(progress: 0.0), 0.0)

            // Save note logic here
            try await saveNoteToDatabase(title: title, content: noteContent, transcript: transcript)

            await updateProgress(.saving(progress: 1.0), 1.0)

            await onComplete()

        } catch {
            await onError(error.localizedDescription)
        }
    }

    // MARK: - Text Scan Integration
    static func processTextScan(
        combinedText: String,
        selectedLanguage: Language,
        noteGenerationService: NoteGenerationService,
        updateProgress: @MainActor @escaping (NoteGenerationProgressModel.GenerationStep, Double) -> Void,
        onComplete: @MainActor @escaping () -> Void,
        onError: @MainActor @escaping (String) -> Void
    ) async {
        do {
            // Step 1: Processing
            await updateProgress(.processing(progress: 0.5), 0.5)
            await updateProgress(.processing(progress: 1.0), 1.0)

            // Step 2: Generating note
            await updateProgress(.generating(progress: 0.0), 0.0)

            let noteContent = try await noteGenerationService.generateNote(from: combinedText, detectedLanguage: selectedLanguage.code)

            await updateProgress(.generating(progress: 0.5), 0.5)

            let title = try await noteGenerationService.generateTitle(from: combinedText, detectedLanguage: selectedLanguage.code)

            await updateProgress(.generating(progress: 1.0), 1.0)

            // Step 3: Saving
            await updateProgress(.saving(progress: 0.0), 0.0)

            // Save note logic here
            try await saveNoteToDatabase(title: title, content: noteContent, transcript: combinedText)

            await updateProgress(.saving(progress: 1.0), 1.0)

            await onComplete()

        } catch {
            await onError(error.localizedDescription)
        }
    }

    // MARK: - Helper function for saving notes
    private static func saveNoteToDatabase(title: String, content: String, transcript: String) async throws {
        // This would be implemented based on your existing note saving logic
        // For now, this is a placeholder
        try await Task.sleep(nanoseconds: 1_000_000_000) // Simulate save time
    }
}
