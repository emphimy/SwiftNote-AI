import SwiftUI

// MARK: - Imports
import Foundation
import UIKit

// MARK: - YouTube View
struct YouTubeView: View {
    @StateObject private var viewModel = YouTubeViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
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
            .navigationDestination(isPresented: $viewModel.shouldNavigateToNote) {
                if let note = viewModel.generatedNote {
                    NoteDetailsView(note: note, context: viewContext)
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
    @Published var shouldNavigateToNote = false
    @Published var generatedNote: NoteCardConfiguration?
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

            var savedNoteId: UUID?

            try context.performAndWait {
                let note = Note(context: context)
                note.id = UUID()
                savedNoteId = note.id
                note.title = title
                note.timestamp = Date()
                note.lastModified = Date()
                note.originalContent = transcript.data(using: .utf8)  // Store the raw transcript
                note.aiGeneratedContent = noteContent.data(using: .utf8)  // Store the AI-generated note
                note.sourceType = "video"
                note.isFavorite = false
                note.processingStatus = "completed"

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

            generatedNote = NoteCardConfiguration(
                id: savedNoteId ?? UUID(),
                title: title,
                date: Date(),
                preview: noteContent,
                sourceType: .video,
                metadata: [
                    "rawTranscript": transcript,  // Make sure the transcript is saved in metadata
                    "aiGeneratedContent": noteContent,
                    "videoId": videoId,  // Include video ID for possible player embedding
                    "language": selectedLanguage.code,
                    "languageName": selectedLanguage.name
                ]
            )

            loadingState = .success(message: "Note created successfully")
            shouldNavigateToNote = true

            #if DEBUG
            print("🎥 YouTubeViewModel: Note generation completed")
            print("- Title: \"\(title)\"")
            print("- Content Length: \(noteContent.count)")
            #endif
        } catch {
            #if DEBUG
            print("🎥 YouTubeViewModel: Error processing video - \(error)")
            #endif
            loadingState = .error(message: error.localizedDescription)
            throw error
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
