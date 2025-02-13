import SwiftUI
import Combine

// MARK: - YouTube Transcript ViewModel
@MainActor
final class YouTubeTranscriptViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var urlInput: String = ""
    @Published var metadata: YouTubeConfig.VideoMetadata?
    @Published private(set) var processState: TranscriptProcessState = .idle
    @Published var generatedNote: NoteCardConfiguration?
    @Published var shouldNavigateToNote = false
    @Published var errorMessage: String?
    @Published var isLoading = false
    
    // MARK: - Private Properties
    private let transcriptService: YouTubeTranscriptService
    private let noteGenerationService: NoteGenerationService
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(initialURL: String = "") {
        self.transcriptService = YouTubeTranscriptService()
        self.noteGenerationService = NoteGenerationService()

        self.urlInput = initialURL
        setupURLInputSubscriber()
        
        if !initialURL.isEmpty {
            Task {
                await fetchVideoMetadata()
                await processVideo()
            }
        }
    }
    
    // MARK: - Private Methods
    private func setupURLInputSubscriber() {
        $urlInput
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.fetchVideoMetadata()
                }
            }
            .store(in: &cancellables)
    }
    
    private func extractVideoID(from url: String) -> String? {
        // Handle various YouTube URL formats
        let patterns = [
            "(?<=v=)[^&#]+",           // Standard YouTube URL
            "(?<=youtu.be/)[^&#]+",    // Shortened YouTube URL
            "(?<=embed/)[^&#]+"        // Embedded YouTube URL
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
               let range = Range(match.range, in: url) {
                return String(url[range])
            }
        }
        
        // If the input is just the video ID itself
        if url.count == 11 && url.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil {
            return url
        }
        
        return nil
    }
    
    // MARK: - Public Methods
    func fetchVideoMetadata() async {
        guard let videoId = extractVideoID(from: urlInput) else {
            errorMessage = YouTubeTranscriptError.invalidVideoId.localizedDescription
            return
        }
        
        do {
            processState = .extractingTranscript
            metadata = try await transcriptService.getVideoMetadata(videoId: videoId)
        } catch {
            errorMessage = error.localizedDescription
            processState = .idle
        }
    }
    
    func processVideo() async {
        guard let videoId = extractVideoID(from: urlInput) else {
            errorMessage = YouTubeTranscriptError.invalidVideoId.localizedDescription
            return
        }
        
        do {
            processState = .extractingTranscript
            let transcript = try await transcriptService.getTranscript(videoId: videoId)
            
            processState = .generatingNote
            try await generateNote(from: transcript)
            
            processState = .completed
            shouldNavigateToNote = true
            
            #if DEBUG
            print("🎥 Successfully processed video and generated note")
            #endif
        } catch {
            errorMessage = error.localizedDescription
            processState = .idle
            
            #if DEBUG
            print("🎥 Error processing video: \(error)")
            #endif
        }
    }
    
    private func generateNote(from transcript: String) async throws {
        let noteContent = try await noteGenerationService.generateNote(from: transcript)
        
        generatedNote = NoteCardConfiguration(
            title: metadata?.title ?? "YouTube Note",
            date: Date(),
            preview: String(noteContent.prefix(100)),
            sourceType: .video,
            tags: ["YouTube"]
        )
    }
}

// MARK: - Transcript Process State
enum TranscriptProcessState {
    case idle
    case extractingTranscript
    case generatingNote
    case completed
    
    var message: String {
        switch self {
        case .idle: return ""
        case .extractingTranscript: return "Extracting video transcript..."
        case .generatingNote: return "Generating your note..."
        case .completed: return "Note created!"
        }
    }
}

// MARK: - YouTube Transcript View
struct YouTubeTranscriptView: View {
    @StateObject private var viewModel: YouTubeTranscriptViewModel
    @Environment(\.dismiss) private var dismiss
    
    init(initialURL: String = "") {
        _viewModel = StateObject(wrappedValue: YouTubeTranscriptViewModel(initialURL: initialURL))
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                // URL Input Section
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Text("Enter YouTube URL")
                        .font(Theme.Typography.h2)
                    
                    TextField("YouTube URL", text: $viewModel.urlInput)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    if let metadata = viewModel.metadata {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("Video Details")
                                .font(Theme.Typography.h3)
                            
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                Text(metadata.title)
                                    .font(Theme.Typography.body)
                                    .lineLimit(2)
                                
                                if let description = metadata.description {
                                    Text(description)
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.secondaryText)
                                        .lineLimit(2)
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.Colors.secondaryBackground)
                            .cornerRadius(Theme.Layout.cornerRadius)
                        }
                    }
                }
                .padding()
                
                Spacer()
                
                // Process Button
                Button {
                    Task {
                        await viewModel.processVideo()
                    }
                } label: {
                    if viewModel.processState == .idle {
                        Text("Process Video")
                            .frame(maxWidth: .infinity)
                    } else {
                        HStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                            Text(viewModel.processState.message)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.urlInput.isEmpty || viewModel.processState != .idle)
                .padding()
            }
            .navigationTitle("YouTube Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
            .navigationDestination(isPresented: $viewModel.shouldNavigateToNote) {
                if let note = viewModel.generatedNote {
                    NoteStudyTabs(note: note)
                        .navigationBarBackButtonHidden()
                }
            }
        }
    }
}
