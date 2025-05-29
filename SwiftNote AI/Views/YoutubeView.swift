import SwiftUI

// MARK: - Imports
import Foundation
import UIKit

// MARK: - YouTube View
struct YouTubeView: View {
    @StateObject private var viewModel = YouTubeViewModel()
    @StateObject private var loadingCoordinator = NoteGenerationCoordinator()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.toastManager) private var toastManager
    @FocusState private var isURLFieldFocused: Bool
    @State private var videoUrl: String = ""
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    // Header Section
                    NoteCreationHeader(
                        icon: "play.circle.fill",
                        title: "YouTube Notes",
                        subtitle: "Create AI-powered notes from YouTube videos"
                    )

                    // URL Input Section
                    VStack(spacing: Theme.Spacing.md) {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "link")
                                .foregroundColor(isURLFieldFocused ? Theme.Colors.primary : .gray)
                                .animation(.easeInOut, value: isURLFieldFocused)

                            TextField("Enter YouTube URL", text: $videoUrl)
                                .textFieldStyle(PlainTextFieldStyle())
                                .autocapitalization(.none)
                                .focused($isURLFieldFocused)

                            if !videoUrl.isEmpty {
                                Button(action: { videoUrl = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                }
                                .transition(.scale.combined(with: .opacity))
                            }

                            Button(action: {
                                if let clipboardString = UIPasteboard.general.string {
                                    videoUrl = clipboardString
                                }
                            }) {
                                Image(systemName: "doc.on.clipboard")
                                    .foregroundColor(Theme.Colors.primary)
                            }
                        }
                        .padding()
                        .background(Theme.Colors.secondaryBackground)
                        .cornerRadius(Theme.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius)
                                .stroke(isURLFieldFocused ? Theme.Colors.primary : Color.clear, lineWidth: 1)
                        )
                        .animation(.easeInOut, value: isURLFieldFocused)

                        // Language Picker Section
                        StandardLanguagePicker(selectedLanguage: $viewModel.selectedLanguage)

                        PrimaryActionButton(
                            title: viewModel.isProcessing ? viewModel.processState : "Create Note",
                            icon: viewModel.isProcessing ? nil : "arrow.right.circle.fill",
                            isEnabled: !videoUrl.isEmpty,
                            isLoading: viewModel.isProcessing,
                            action: processVideo
                        )
                    }
                    .padding(.horizontal)

                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") {
                    errorMessage = ""
                    showingError = false
                }
            } message: {
                Text(errorMessage)
            }
            .onChange(of: viewModel.isProcessingComplete) { isComplete in
                if isComplete {
                    // Start the new loading experience
                    loadingCoordinator.startGeneration(
                        type: .youtubeVideo,
                        onComplete: {
                            dismiss()
                            toastManager.show("YouTube note created successfully", type: .success)
                        },
                        onCancel: {
                            // Reset the processing state
                            viewModel.isProcessingComplete = false
                        }
                    )

                    // Start the actual processing
                    Task {
                        await viewModel.processVideoWithProgress(
                            url: videoUrl,
                            updateProgress: loadingCoordinator.updateProgress,
                            onComplete: loadingCoordinator.completeGeneration,
                            onError: loadingCoordinator.setError
                        )
                    }
                }
            }
            .noteGenerationLoading(coordinator: loadingCoordinator)
        }
    }

    private func processVideo() {
        // Trigger the new loading experience
        viewModel.isProcessingComplete = true
    }
}

// MARK: - YouTube ViewModel
@MainActor
class YouTubeViewModel: ObservableObject {
    private let youtubeService: YouTubeService
    private let noteGenerationService: NoteGenerationService

    @Published var isProcessing = false
    @Published var processState = ""
    @Published var isProcessingComplete = false
    @Published private(set) var loadingState: LoadingState = .idle
    @Published var selectedLanguage: Language = Language.supportedLanguages[0] // Default to English
    private var videoId: String?

    init() {
        self.youtubeService = YouTubeService()
        self.noteGenerationService = NoteGenerationService()
    }

    private func validateURL(_ urlString: String) throws -> String {
        guard let videoId = extractVideoId(from: urlString) else {
            #if DEBUG
            print("🎥 YouTubeViewModel: Invalid URL format: \(urlString)")
            #endif
            throw YouTubeError.invalidVideoId
        }
        self.videoId = videoId
        return urlString
    }

    func processVideo(url: String) async throws {
        // Legacy method - now just triggers completion
        isProcessingComplete = true
    }

    // MARK: - Process Video with Progress Tracking
    func processVideoWithProgress(
        url: String,
        updateProgress: @escaping (NoteGenerationProgressModel.GenerationStep, Double) -> Void,
        onComplete: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) async {
        do {
            _ = try validateURL(url)
            guard let videoId = self.videoId else {
                onError("Invalid YouTube video URL or ID. Please check the URL and try again.")
                return
            }

            #if DEBUG
            print("🎥 YouTubeViewModel: Starting video processing for ID: \(videoId)")
            #endif

            // Step 1: Transcribing
            await MainActor.run { updateProgress(.transcribing(progress: 0.0), 0.0) }
            let (transcript, _) = try await youtubeService.getTranscript(videoId: videoId)
            await MainActor.run { updateProgress(.transcribing(progress: 1.0), 1.0) }

            // Step 2: Generating note
            await MainActor.run { updateProgress(.generating(progress: 0.0), 0.0) }

            // Generate note content with progress simulation
            let noteContent = try await generateNoteWithProgress(
                transcript: transcript,
                selectedLanguage: selectedLanguage,
                updateProgress: updateProgress
            )

            // Don't set fixed 0.5 progress here, let title generation continue from where note generation left off

            // Generate title with progress simulation
            let title = try await generateTitleWithProgress(
                transcript: transcript,
                selectedLanguage: selectedLanguage,
                updateProgress: updateProgress
            )

            await MainActor.run { updateProgress(.generating(progress: 1.0), 1.0) }

            // Step 3: Saving
            await MainActor.run { updateProgress(.saving(progress: 0.0), 0.0) }
            let context = PersistenceController.shared.container.viewContext

            try context.performAndWait {
                let note = Note(context: context)
                note.id = UUID()
                note.title = title
                note.timestamp = Date()
                note.lastModified = Date()
                note.originalContent = transcript.data(using: .utf8)
                note.transcript = transcript
                note.aiGeneratedContent = noteContent.data(using: .utf8)
                note.sourceType = "video"
                note.isFavorite = false
                note.processingStatus = "completed"
                note.syncStatus = "pending"
                note.transcriptLanguage = selectedLanguage.code
                note.videoId = videoId

                // Assign to All Notes folder
                if let allNotesFolder = FolderListViewModel.getAllNotesFolder(context: context) {
                    note.setValue(allNotesFolder, forKey: "folder")
                    #if DEBUG
                    print("🎥 YouTubeViewModel: Assigned note to All Notes folder")
                    #endif
                }

                try context.save()
                #if DEBUG
                print("📝 YouTubeViewModel: Note saved successfully")
                #endif
            }

            await MainActor.run { updateProgress(.saving(progress: 1.0), 1.0) }

            #if DEBUG
            print("🎥 YouTubeViewModel: Note generation completed")
            print("- Title: \"\(title)\"")
            print("- Content Length: \(noteContent.count)")
            #endif

            await MainActor.run { onComplete() }

        } catch {
            #if DEBUG
            print("🎥 YouTubeViewModel: Error processing video - \(error)")
            #endif

            // Provide user-friendly error messages
            let userFriendlyMessage: String
            if let youtubeError = error as? YouTubeTranscriptError {
                switch youtubeError {
                case .emptyData:
                    userFriendlyMessage = "Unable to get transcript for this video. The video may not have captions available."
                case .transcriptNotAvailable:
                    userFriendlyMessage = "This video doesn't have captions available. Please try a different video."
                case .invalidVideoId:
                    userFriendlyMessage = "Invalid YouTube video URL or ID. Please check the URL and try again."
                case .networkError(let details):
                    userFriendlyMessage = "Network error: \(details). Please check your internet connection."
                case .parsingError, .jsonParsingError:
                    userFriendlyMessage = "Unable to process the video transcript. Please try a different video."
                case .invalidResponse:
                    userFriendlyMessage = "Received an invalid response from YouTube. Please try again later."
                }
            } else if let youtubeError = error as? YouTubeError {
                switch youtubeError {
                case .invalidVideoId:
                    userFriendlyMessage = "Invalid YouTube video URL or ID. Please check the URL and try again."
                case .transcriptNotAvailable:
                    userFriendlyMessage = "This video doesn't have captions available. Please try a different video."
                case .networkError(let message):
                    userFriendlyMessage = "Network error: \(message). Please check your internet connection."
                }
            } else {
                userFriendlyMessage = "An error occurred: \(error.localizedDescription)"
            }

            await MainActor.run { onError(userFriendlyMessage) }
        }
    }

    // MARK: - Progress Simulation Helpers
    private func generateNoteWithProgress(
        transcript: String,
        selectedLanguage: Language,
        updateProgress: @escaping (NoteGenerationProgressModel.GenerationStep, Double) -> Void
    ) async throws -> String {
        // Start progress simulation task
        let progressTask = Task {
            await simulateNoteGenerationProgress(updateProgress: updateProgress)
        }

        // Start the actual API call
        let noteContent = try await noteGenerationService.generateNote(from: transcript, detectedLanguage: selectedLanguage.code)

        // Cancel progress simulation since API call completed
        progressTask.cancel()

        return noteContent
    }

    private func simulateNoteGenerationProgress(
        updateProgress: @escaping (NoteGenerationProgressModel.GenerationStep, Double) -> Void
    ) async {
        // More realistic progress simulation that continues until API completes
        // Simulate progress from 5% to 90% over expected duration (10-12 seconds)
        let progressSteps = [0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.35, 0.4, 0.45, 0.5, 0.55, 0.6, 0.65, 0.7, 0.75, 0.8, 0.85, 0.9]

        for (index, progress) in progressSteps.enumerated() {
            // Variable timing: faster at start, slower towards end (more realistic)
            let delay: UInt64 = index < 8 ? 500_000_000 : 800_000_000 // 0.5s then 0.8s
            try? await Task.sleep(nanoseconds: delay)

            await MainActor.run {
                updateProgress(.generating(progress: progress), progress)
            }
        }

        // Continue with small increments until cancelled
        var finalProgress = 0.9
        while finalProgress < 0.98 {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            finalProgress += 0.02

            await MainActor.run {
                updateProgress(.generating(progress: finalProgress), finalProgress)
            }
        }
    }

    private func generateTitleWithProgress(
        transcript: String,
        selectedLanguage: Language,
        updateProgress: @escaping (NoteGenerationProgressModel.GenerationStep, Double) -> Void
    ) async throws -> String {
        // Start progress simulation task
        let progressTask = Task {
            await simulateTitleGenerationProgress(updateProgress: updateProgress)
        }

        // Start the actual API call
        let title = try await noteGenerationService.generateTitle(from: transcript, detectedLanguage: selectedLanguage.code)

        // Cancel progress simulation since API call completed
        progressTask.cancel()

        return title
    }

    private func simulateTitleGenerationProgress(
        updateProgress: @escaping (NoteGenerationProgressModel.GenerationStep, Double) -> Void
    ) async {
        // Continue from where note generation left off (around 90-98%)
        // Small increments to show final progress
        let progressSteps = [0.91, 0.93, 0.95, 0.97, 0.99]

        for progress in progressSteps {
            // Shorter delays for title generation (total ~3 seconds)
            try? await Task.sleep(nanoseconds: 600_000_000) // 0.6 seconds

            await MainActor.run {
                updateProgress(.generating(progress: progress), progress)
            }
        }
    }

    private func extractVideoId(from url: String) -> String? {
        let patterns = [
            "(?<=v=)[^&]+",           // Standard YouTube URL
            "(?<=be/)[^&]+",          // Shortened youtu.be URL
            "(?<=embed/)[^&]+",       // Embedded player URL
            "(?<=videos/)[^&]+"       // Alternative video URL
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
               let range = Range(match.range, in: url) {
                return String(url[range])
            }
        }

        // If no patterns match, check if the input is a direct video ID
        if url.count == 11 && url.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil {
            return url
        }

        return nil
    }
}
