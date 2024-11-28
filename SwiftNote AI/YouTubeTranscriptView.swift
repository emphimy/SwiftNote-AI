import SwiftUI
import Combine

// MARK: - YouTube Transcript ViewModel
@MainActor
final class YouTubeTranscriptViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var urlInput: String = ""
    @Published var metadata: YouTubeConfig.VideoMetadata?
    @Published var transcript: String?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    private let transcriptService: YouTubeTranscriptService
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(initialURL: String = "") {
        self.transcriptService = YouTubeTranscriptService()
        self.urlInput = initialURL
        setupURLInputSubscriber()
        
        if !initialURL.isEmpty {
            Task {
                await fetchVideoMetadata()
                await fetchTranscript()
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
            isLoading = true
            metadata = try await transcriptService.getVideoMetadata(videoId: videoId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
    
    func fetchTranscript() async {
        guard let videoId = extractVideoID(from: urlInput) else {
            errorMessage = YouTubeTranscriptError.invalidVideoId.localizedDescription
            return
        }
        
        do {
            isLoading = true
            transcript = try await transcriptService.getTranscript(videoId: videoId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
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
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    Spacer(minLength: 160)
                    
                    VStack(spacing: 16) {
                        // URL Input Section
                        urlInputSection
                        
                        // Video Details Section
                        if let metadata = viewModel.metadata {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Video Details")
                                    .font(.title3)
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(metadata.title)
                                        .font(.body)
                                        .lineLimit(2)
                                }
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(12)
                            }
                        }
                        
                        // Transcript Section
                        if let transcript = viewModel.transcript {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Transcript")
                                    .font(.title3)
                                
                                ScrollView {
                                    Text(transcript)
                                        .font(.body)
                                        .lineLimit(nil)
                                }
                                .frame(maxHeight: 200)
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                        }
                    }
                    .padding()
                    
                    Spacer(minLength: 80)
                }
            }
            .navigationTitle("YouTube Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onChange(of: viewModel.urlInput) { _ in
                checkClipboard()
            }
        }
    }
    
    // MARK: - View Components
    private var urlInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("YouTube URL", text: $viewModel.urlInput)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            
            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            Button("Fetch Transcript") {
                Task {
                    await viewModel.fetchTranscript()
                }
            }
            .disabled(viewModel.urlInput.isEmpty || viewModel.isLoading)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Helper Methods
    private func checkClipboard() {
        if let clipboardString = UIPasteboard.general.string,
           clipboardString.contains("youtube.com") || clipboardString.contains("youtu.be") {
            viewModel.urlInput = clipboardString
        }
    }
}
