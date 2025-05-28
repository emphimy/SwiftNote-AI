import SwiftUI

// MARK: - Imports
import Foundation
import UIKit

// MARK: - YouTube View
struct YouTubeView: View {
    @StateObject private var viewModel = YouTubeViewModel()
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
                    VStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Theme.Colors.primary, Theme.Colors.primary.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .padding(.top, Theme.Spacing.xl)

                        Text("YouTube Notes")
                            .font(Theme.Typography.h2)
                            .foregroundColor(Theme.Colors.text)

                        Text("Create AI-powered notes from YouTube videos")
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

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
                        LanguagePicker(selectedLanguage: $viewModel.selectedLanguage)
                            .padding(.vertical, Theme.Spacing.sm)
                            .padding(.horizontal, Theme.Spacing.xs)

                        Button(action: processVideo) {
                            HStack {
                                if viewModel.isProcessing {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                        .tint(.white)
                                    Text(viewModel.processState)
                                } else {
                                    Text("Create Note")
                                    Image(systemName: "arrow.right.circle.fill")
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(videoUrl.isEmpty ? Theme.Colors.primary.opacity(0.5) : Theme.Colors.primary)
                            .foregroundColor(.white)
                            .cornerRadius(Theme.Layout.cornerRadius)
                        }
                        .disabled(videoUrl.isEmpty || viewModel.isProcessing)
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
                    // Automatically dismiss the view when processing is complete
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        dismiss()
                        toastManager.show("YouTube note created successfully", type: .success)
                    }
                }
            }
        }
    }

    private func processVideo() {
        Task {
            do {
                try await viewModel.processVideo(url: videoUrl)
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
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
        isProcessing = true
        defer { isProcessing = false }

        do {
            _ = try validateURL(url)
            guard let videoId = self.videoId else {
                throw YouTubeError.invalidVideoId
            }

            #if DEBUG
            print("🎥 YouTubeViewModel: Starting video processing for ID: \(videoId)")
            #endif

            loadingState = .loading(message: "Extracting transcript...")
            let (transcript, _) = try await youtubeService.getTranscript(videoId: videoId)

            loadingState = .loading(message: "Generating note...")
            let noteContent = try await noteGenerationService.generateNote(from: transcript, detectedLanguage: selectedLanguage.code)

            loadingState = .loading(message: "Generating title...")
            let title = try await noteGenerationService.generateTitle(from: transcript, detectedLanguage: selectedLanguage.code)

            // Save to Core Data
            loadingState = .loading(message: "Saving note...")
            let context = PersistenceController.shared.container.viewContext

            try context.performAndWait {
                let note = Note(context: context)
                note.id = UUID()
                note.title = title
                note.timestamp = Date()
                note.lastModified = Date()
                note.originalContent = transcript.data(using: .utf8)  // Store the raw transcript
                note.transcript = transcript  // Store transcript in the dedicated field
                note.aiGeneratedContent = noteContent.data(using: .utf8)  // Store the AI-generated note
                note.sourceType = "video"
                note.isFavorite = false
                note.processingStatus = "completed"
                note.syncStatus = "pending" // Mark for sync

                // Store language information
                note.transcriptLanguage = selectedLanguage.code

                // Store video ID directly
                note.videoId = videoId

                // Assign to All Notes folder
                if let allNotesFolder = FolderListViewModel.getAllNotesFolder(context: context) {
                    note.setValue(allNotesFolder, forKey: "folder")
                    #if DEBUG
                    print("🎥 YouTubeViewModel: Assigned note to All Notes folder")
                    #endif
                }

                try context.save()
                print("📝 YouTubeViewModel: Note saved successfully")
                print("📝 YouTubeViewModel: Note ID: \(note.id?.uuidString ?? "unknown")")
                print("📝 YouTubeViewModel: Video ID: \(videoId)")

                #if DEBUG
                // Verify save
                let request = Note.fetchRequest()
                let count = try context.count(for: request)
                print("- Total notes in CoreData: \(count)")
                #endif
            }

            loadingState = .success(message: "Note created successfully")
            isProcessingComplete = true

            #if DEBUG
            print("🎥 YouTubeViewModel: Note generation completed")
            print("- Title: \"\(title)\"")
            print("- Content Length: \(noteContent.count)")
            #endif
        } catch {
            #if DEBUG
            print("🎥 YouTubeViewModel: Error processing video - \(error)")
            #endif

            // Provide more user-friendly error messages
            let userFriendlyMessage: String

            if let youtubeError = error as? YouTubeTranscriptError {
                switch youtubeError {
                case .emptyData:
                    userFriendlyMessage = "Unable to get transcript for this video. The video may not have captions available or YouTube may be restricting access to the transcript."
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

            loadingState = .error(message: userFriendlyMessage)
            throw NSError(domain: "YouTubeViewModel",
                         code: 1,
                         userInfo: [NSLocalizedDescriptionKey: userFriendlyMessage])
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
