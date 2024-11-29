import SwiftUI

struct YouTubeView: View {
    @StateObject private var viewModel = YouTubeViewModel()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isURLFieldFocused: Bool
    @State private var videoUrl: String = ""
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationView {
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

                        Text("YouTube Transcript")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.Colors.text)

                        Text("Enter a YouTube URL to get its transcript")
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

                        Button(action: fetchTranscript) {
                            HStack {
                                Text("Get Transcript")
                                Image(systemName: "arrow.right.circle.fill")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(videoUrl.isEmpty ? Theme.Colors.primary.opacity(0.5) : Theme.Colors.primary)
                            .foregroundColor(.white)
                            .cornerRadius(Theme.Layout.cornerRadius)
                        }
                        .disabled(videoUrl.isEmpty)
                    }
                    .padding(.horizontal)

                    // Transcript Section
                    if !viewModel.transcript.isEmpty {
                        VStack(spacing: Theme.Spacing.md) {
                            // Info Bar
                            HStack {
                                Label("\(viewModel.transcript.count) characters", systemImage: "character.cursor.ibeam")
                                    .font(.caption)
                                    .foregroundColor(Theme.Colors.secondaryText)
                                Spacer()
                                Button(action: {
                                    UIPasteboard.general.string = viewModel.transcript
                                }) {
                                    Label("Copy", systemImage: "doc.on.doc")
                                        .font(.caption)
                                        .foregroundColor(Theme.Colors.primary)
                                }
                            }
                            .padding(.horizontal)

                            // Transcript Content
                            ScrollView {
                                VStack(alignment: .leading) {
                                    ForEach(viewModel.transcript.components(separatedBy: "\n\n"), id: \.self) { paragraph in
                                        if !paragraph.isEmpty {
                                            Text(paragraph)
                                                .font(.body)
                                                .foregroundColor(Theme.Colors.text)
                                                .textSelection(.enabled)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.vertical, 4)
                                        }
                                    }
                                }
                                .padding()
                                .background(Theme.Colors.secondaryBackground)
                                .cornerRadius(Theme.Layout.cornerRadius)
                                .padding(.horizontal)
                            }
                        }
                    } else if !viewModel.isLoading {
                        VStack(spacing: Theme.Spacing.md) {
                            Image(systemName: "text.quote")
                                .font(.largeTitle)
                                .foregroundColor(Theme.Colors.secondaryText)
                            Text("Enter a YouTube URL to get started")
                                .font(.body)
                                .foregroundColor(Theme.Colors.secondaryText)
                        }
                        .padding(.top, Theme.Spacing.xl)
                    }

                    if viewModel.isLoading {
                        VStack(spacing: Theme.Spacing.md) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Fetching transcript...")
                                .font(.caption)
                                .foregroundColor(Theme.Colors.secondaryText)
                        }
                        .padding()
                        .background(Theme.Colors.secondaryBackground)
                        .cornerRadius(Theme.Layout.cornerRadius)
                        .padding(.horizontal)
                    }
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
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func fetchTranscript() {
        Task {
            do {
                try await viewModel.fetchTranscript(from: videoUrl)
            } catch {
                showingError = true
                errorMessage = error.localizedDescription
            }
        }
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

    func fetchTranscript(from url: String) async throws {
        isLoading = true
        transcript = ""

        do {
            guard let videoId = extractVideoId(from: url) else {
                throw YouTubeError.invalidVideoId
            }
            let fetchedTranscript = try await youtubeService.getTranscript(videoId: videoId)
            transcript = cleanupTranscript(fetchedTranscript)
            isLoading = false
        } catch {
            isLoading = false
            throw error
        }
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

#if DEBUG
struct YouTubeView_Previews: PreviewProvider {
    static var previews: some View {
        YouTubeView()
    }
}
#endif
