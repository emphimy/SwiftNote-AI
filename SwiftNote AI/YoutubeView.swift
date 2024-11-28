import SwiftUI
import GoogleSignIn

struct YouTubeView: View {
    @StateObject private var viewModel = YouTubeViewModel()
    @State private var videoUrl: String = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            VStack {
                if viewModel.isSignedIn == false {
                    signInPrompt
                } else {
                    mainContent
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
    
    private var signInPrompt: some View {
        VStack(spacing: 20) {
            Text("Sign in to access YouTube transcripts")
                .font(.headline)
            
            Button(action: signIn) {
                Text("Sign in with Google")
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(8)
            }
        }
    }
    
    private var mainContent: some View {
        VStack(spacing: 20) {
            HStack {
                TextField("Enter YouTube URL", text: $videoUrl)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                
                Button(action: fetchTranscript) {
                    Text("Get Transcript")
                        .foregroundColor(.white)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal)
            
            if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
            } else if !viewModel.transcript.isEmpty {
                ScrollView {
                    Text(viewModel.transcript)
                        .padding()
                }
            }
            
            Spacer()
            
            Button {
                Task { await viewModel.signOut() }
            } label: {
                Text("Sign Out")
                    .foregroundColor(.red)
                    .padding()
            }
        }
    }
    
    private func signIn() {
        Task {
            do {
                try await viewModel.signIn()
            } catch {
                showError(error)
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
        guard !url.isEmpty else { return nil }
        
        // Handle different YouTube URL formats
        let patterns = [
            "(?<=v=)[^&#]+",           // Standard YouTube URL
            "(?<=be/)[^&#]+",          // youtu.be URL
            "(?<=embed/)[^&#]+",       // Embedded URL
            "(?<=shorts/)[^&#]+"       // Shorts URL
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) {
                let range = Range(match.range, in: url)!
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

// MARK: - ViewModel
@MainActor
class YouTubeViewModel: ObservableObject {
    private let youtubeService: YouTubeService
    
    @Published var transcript: String = ""
    @Published var isLoading: Bool = false
    @Published private(set) var isSignedIn: Bool = false
    
    init() {
        self.youtubeService = YouTubeService()
        self.isSignedIn = youtubeService.isSignedIn
    }
    
    func signIn() async throws {
        try await youtubeService.signIn()
        isSignedIn = youtubeService.isSignedIn
    }
    
    func signOut() async {
        youtubeService.signOut()
        isSignedIn = false
        transcript = ""
    }
    
    func fetchTranscript(videoId: String) async throws {
        isLoading = true
        transcript = ""
        
        do {
            transcript = try await youtubeService.getTranscript(videoId: videoId)
        } catch {
            isLoading = false
            throw error
        }
        
        isLoading = false
    }
}

#if DEBUG
struct YouTubeView_Previews: PreviewProvider {
    static var previews: some View {
        YouTubeView()
    }
}
#endif
