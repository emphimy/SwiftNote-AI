import SwiftUI
import UIKit

struct TextView: UIViewRepresentable {
    let text: String
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .preferredFont(forTextStyle: .body)
        textView.backgroundColor = .clear
        textView.textColor = .label
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = .zero
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.text = text
    }
}

struct YouTubeView: View {
    @StateObject private var viewModel = YouTubeViewModel()
    @State private var videoUrl: String = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // URL Input Section
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "link")
                            .foregroundColor(.gray)
                        TextField("Paste YouTube URL", text: $videoUrl)
                            .textFieldStyle(PlainTextFieldStyle())
                            .autocapitalization(.none)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    
                    Button(action: fetchTranscript) {
                        if viewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Get Transcript")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .disabled(viewModel.isLoading)
                }
                .padding()
                
                // Transcript Section
                if !viewModel.transcript.isEmpty {
                    VStack(spacing: 8) {
                        // Info Bar
                        HStack {
                            Label("\(viewModel.transcript.count) characters", systemImage: "character.cursor.ibeam")
                            Spacer()
                            Button(action: {
                                UIPasteboard.general.string = viewModel.transcript
                            }) {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        
                        // Transcript Content
                        ScrollView {
                            TextView(text: viewModel.transcript)
                                .padding()
                                .background(Color(.systemBackground))
                                .cornerRadius(10)
                                .padding(.horizontal)
                        }
                    }
                    .background(Color(.systemGray6))
                } else if !viewModel.isLoading {
                    VStack(spacing: 12) {
                        Image(systemName: "text.quote")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                        Text("Enter a YouTube URL to get started")
                            .foregroundColor(.gray)
                    }
                }
            }
            .navigationTitle("YouTube Transcript")
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func fetchTranscript() {
        guard let videoId = extractVideoId(from: videoUrl) else {
            showError(YouTubeError.invalidVideoId)
            return
        }
        
        Task {
            do {
                try await viewModel.fetchTranscript(videoId: videoId)
            } catch {
                showError(error)
            }
        }
    }
    
    private func showError(_ error: Error) {
        errorMessage = error.localizedDescription
        showingError = true
    }
    
    private func extractVideoId(from url: String) -> String? {
        // Handle various YouTube URL formats
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

@MainActor
class YouTubeViewModel: ObservableObject {
    private let youtubeService: YouTubeService
    @Published var transcript: String = ""
    @Published var isLoading: Bool = false
    
    init() {
        self.youtubeService = YouTubeService()
    }
    
    private func cleanupTranscript(_ text: String) -> String {
        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
            .replacingOccurrences(of: "[Music]", with: "🎵 [Music]")
            .replacingOccurrences(of: "\u{200B}", with: "") // Zero-width space
            .replacingOccurrences(of: "\u{FEFF}", with: "") // Zero-width non-breaking space
    }
    
    func fetchTranscript(videoId: String) async throws {
        isLoading = true
        transcript = ""
        
        do {
            let fetchedTranscript = try await youtubeService.getTranscript(videoId: videoId)
            transcript = cleanupTranscript(fetchedTranscript)
            isLoading = false
        } catch {
            isLoading = false
            throw error
        }
    }
}

#if DEBUG
struct YouTubeView_Previews: PreviewProvider {
    static var previews: some View {
        YouTubeView()
    }
}
#endif
