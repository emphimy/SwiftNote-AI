import SwiftUI

// MARK: - Imports
import Foundation
import SwiftUI
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
                    VStack(spacing: Theme.Spacing.md) {
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
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.Colors.text)

                        Text("Create AI-powered notes from YouTube videos")
                            .font(.body)
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
            let (transcript, language) = try await youtubeService.getTranscript(videoId: videoId)
            let metadata = try await youtubeService.getVideoMetadata(videoId: videoId)
            
            loadingState = .loading(message: "Generating note...")
            let noteContent = try await noteGenerationService.generateNote(from: transcript, detectedLanguage: language)
            
            loadingState = .loading(message: "Generating title...")
            let title = try await noteGenerationService.generateTitle(from: transcript, detectedLanguage: language)
            
            generatedNote = NoteCardConfiguration(
                title: title,
                date: Date(),
                preview: noteContent,
                sourceType: .video,
                tags: ["YouTube", "AI Generated"],
                metadata: [
                    "rawTranscript": transcript,
                    "videoId": videoId,
                    "videoTitle": metadata.title,
                    "aiGeneratedContent": noteContent
                ]
            )
            
            #if DEBUG
            print("🎥 YouTubeViewModel: Note generation completed")
            print("- Title: \(title)")
            print("- Content Length: \(noteContent.count)")
            #endif
            
            shouldNavigateToNote = true
            loadingState = .success(message: "Note created successfully")
            
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
