import SwiftUI
import CoreData
import Combine
import AVFoundation

// MARK: - YouTube Input Error
enum YouTubeInputError: LocalizedError {
    case invalidURL
    case metadataFetchFailed
    case extractionFailed(Error)
    case invalidVideoID
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid YouTube URL"
        case .metadataFetchFailed:
            return "Failed to fetch video information"
        case .extractionFailed(let error):
            return "Failed to extract audio: \(error.localizedDescription)"
        case .invalidVideoID:
            return "Could not find video ID"
        }
    }
}

// MARK: - YouTube Video Metadata
struct YouTubeMetadata: Codable {
    let title: String
    let duration: TimeInterval
    let thumbnailURL: URL?
    let videoID: String
}

// MARK: - YouTube Input ViewModel
@MainActor
final class YouTubeInputViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var urlInput: String = ""
    @Published var metadata: YouTubeMetadata?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var extractionProgress: Double = 0
    @Published var saveLocally = false
    @Published var isExtracting = false
    @Published private(set) var loadingState: LoadingState = .idle
    
    // MARK: - Private Properties
    private let viewContext: NSManagedObjectContext
    private var extractionTask: Task<Void, Never>?
    private let cleanupManager = AudioCleanupManager.shared
    private var tempFileURL: URL?
    
    init(context: NSManagedObjectContext) {
        self.viewContext = context
        
        #if DEBUG
        print("📺 YouTubeInputVM: Initializing")
        #endif
    }
    
    // MARK: - URL Validation
    func validateAndFetchMetadata() async throws {
        guard let url = URL(string: urlInput),
              let videoID = extractVideoID(from: url) else {
            #if DEBUG
            print("📺 YouTubeInputVM: Invalid URL format")
            #endif
            throw YouTubeInputError.invalidURL
        }
        
        loadingState = .loading(message: "Fetching video information...")
        
        do {
            // Simulate metadata fetch for now
            // In production, this would call actual YouTube API
            try await Task.sleep(nanoseconds: 1_000_000_000)
            
            let metadata = YouTubeMetadata(
                title: "Sample Video",
                duration: 180,
                thumbnailURL: URL(string: "https://example.com/thumbnail.jpg"),
                videoID: videoID
            )
            
            await MainActor.run {
                self.metadata = metadata
                self.loadingState = .success(message: "Video found")
            }
            
            #if DEBUG
            print("📺 YouTubeInputVM: Metadata fetched successfully for video: \(videoID)")
            #endif
        } catch {
            #if DEBUG
            print("📺 YouTubeInputVM: Error fetching metadata - \(error)")
            #endif
            loadingState = .error(message: error.localizedDescription)
            throw YouTubeInputError.metadataFetchFailed
        }
    }
    
    // MARK: - Extraction
    func extractAudio() async throws {
        guard let metadata = metadata else {
            #if DEBUG
            print("📺 YouTubeInputVM: Cannot extract - no metadata available")
            #endif
            throw YouTubeInputError.metadataFetchFailed
        }
        
        isExtracting = true
        loadingState = .loading(message: "Extracting audio...")
        
        defer {
            isExtracting = false
        }
        
        do {
            // Simulate extraction process
            for progress in stride(from: 0.0, through: 1.0, by: 0.1) {
                try await Task.sleep(nanoseconds: 500_000_000)
                extractionProgress = progress
            }
            
            // Create temporary file
            let temporaryDir = FileManager.default.temporaryDirectory
            tempFileURL = temporaryDir.appendingPathComponent("\(metadata.videoID).m4a")
            
            // Save to Core Data
            try await saveNote(title: metadata.title)
            
            loadingState = .success(message: "Extraction complete")
            
            #if DEBUG
            print("📺 YouTubeInputVM: Audio extracted successfully")
            #endif
        } catch {
            #if DEBUG
            print("📺 YouTubeInputVM: Extraction failed - \(error)")
            #endif
            loadingState = .error(message: error.localizedDescription)
            throw YouTubeInputError.extractionFailed(error)
        }
    }
    
    // MARK: - Save Note
    private func saveNote(title: String) async throws {
        guard let audioURL = tempFileURL else {
            #if DEBUG
            print("📺 YouTubeInputVM: No audio URL available for saving")
            #endif
            throw YouTubeInputError.extractionFailed(NSError(domain: "YouTubeInput", code: -1))
        }
        
        try await viewContext.perform { [weak self] in
            guard let self = self else { return }
            
            let note = NSEntityDescription.insertNewObject(forEntityName: "Note", into: self.viewContext)
            note.setValue(title, forKey: "title")
            note.setValue(Date(), forKey: "timestamp")
            note.setValue("audio", forKey: "sourceType")
            
            if self.saveLocally {
                // Move file to permanent storage
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let destinationURL = documentsPath.appendingPathComponent("\(UUID().uuidString).m4a")
                try FileManager.default.moveItem(at: audioURL, to: destinationURL)
            }
            
            try self.viewContext.save()
            
            #if DEBUG
            print("📺 YouTubeInputVM: Note saved successfully")
            #endif
        }
    }
    
    // MARK: - Helper Methods
    private func extractVideoID(from url: URL) -> String? {
        // Handle various YouTube URL formats
        if let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            return queryItems.first(where: { $0.name == "v" })?.value
        }
        return nil
    }
    
    // MARK: - Cleanup
    func cleanup() async {
        #if DEBUG
        print("📺 YouTubeInputViewModel: Starting cleanup")
        #endif
        
        if let url = tempFileURL {
            await cleanupManager.cleanup(url: url)
        }
    }
    
    deinit {
        #if DEBUG
        print("📺 YouTubeInputViewModel: Deinitializing")
        #endif
        
        // Create a separate Task that won't retain self
        let tempURL = tempFileURL
        Task.detached { [cleanupManager] in
            await cleanupManager.cleanup(url: tempURL)
            
            #if DEBUG
            print("📺 YouTubeInputViewModel: Completed deinit cleanup")
            #endif
        }
    }
}

// MARK: - YouTube Input View
struct YouTubeInputView: View {
    @StateObject private var viewModel: YouTubeInputViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.toastManager) private var toastManager
    @Environment(\.scenePhase) private var scenePhase
    
    init(context: NSManagedObjectContext) {
        self._viewModel = StateObject(wrappedValue: YouTubeInputViewModel(context: context))
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack {
                    Spacer(minLength: 160)
                    
                    VStack(spacing: Theme.Spacing.lg) {
                        // URL Input Section
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("YouTube URL")
                                .font(Theme.Typography.h3)
                            
                            HStack {
                                CustomTextField(
                                    placeholder: "https://youtube.com/watch?v=...",
                                    text: $viewModel.urlInput,
                                    keyboardType: .URL
                                )
                                
                                // Paste Button
                                Button(action: {
                                    #if DEBUG
                                    print("📺 YouTubeInputView: Attempting to paste from clipboard")
                                    #endif
                                    if let clipboardString = UIPasteboard.general.string {
                                        viewModel.urlInput = clipboardString
                                        #if DEBUG
                                        print("📺 YouTubeInputView: Pasted text: \(clipboardString)")
                                        #endif
                                    } else {
                                        #if DEBUG
                                        print("📺 YouTubeInputView: Clipboard empty or contains non-text content")
                                        #endif
                                        toastManager.show("No text in clipboard", type: .warning)
                                    }
                                }) {
                                    Image(systemName: "doc.on.clipboard")
                                        .foregroundColor(Theme.Colors.primary)
                                }
                                .padding(.horizontal, Theme.Spacing.sm)
                            }
                            
                            // Validate URL Button
                            Button("Validate URL") {
                                validateURL()
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                        
                        // Metadata Preview
                        if let metadata = viewModel.metadata {
                            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                                Text("Video Details")
                                    .font(Theme.Typography.h3)
                                
                                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                    Text(metadata.title)
                                        .font(Theme.Typography.body)
                                    
                                    Text(formatDuration(metadata.duration))
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.secondaryText)
                                }
                                .padding()
                                .background(Theme.Colors.secondaryBackground)
                                .cornerRadius(Theme.Layout.cornerRadius)
                            }
                            
                            // Local Storage Toggle
                            Toggle("Save audio file locally", isOn: $viewModel.saveLocally)
                                .padding()
                                .background(Theme.Colors.secondaryBackground)
                                .cornerRadius(Theme.Layout.cornerRadius)
                        }
                        
                        // Extract Button
                        if !viewModel.isExtracting {
                            Button("Extract Audio") {
                                extractAudio()
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(viewModel.urlInput.isEmpty)
                        }
                        
                        // Progress Indicator
                        if viewModel.isExtracting {
                            VStack(spacing: Theme.Spacing.md) {
                                ProgressView(value: viewModel.extractionProgress)
                                    .tint(Theme.Colors.primary)
                                
                                Text("Extracting audio...")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.secondaryText)
                            }
                            .padding()
                        }
                        // YouTube App Button
                        Button(action: {
                            #if DEBUG
                            print("📺 YouTubeInputView: Attempting to open YouTube app")
                            #endif
                            
                            // YouTube app URL scheme
                            if let youtubeURL = URL(string: "youtube://") {
                                UIApplication.shared.open(youtubeURL) { success in
                                    #if DEBUG
                                    print("📺 YouTubeInputView: YouTube app open attempt success: \(success)")
                                    #endif
                                    
                                    if !success {
                                        // Fallback to App Store if YouTube app is not installed
                                        if let appStoreURL = URL(string: "https://apps.apple.com/app/youtube/id544007664") {
                                            #if DEBUG
                                            print("📺 YouTubeInputView: YouTube app not installed, opening App Store")
                                            #endif
                                            UIApplication.shared.open(appStoreURL)
                                        } else {
                                            toastManager.show("Could not open YouTube app", type: .error)
                                        }
                                    }
                                }
                            }
                        }) {
                            HStack {
                                Image(systemName: "play.rectangle.fill")
                                    .font(.title3)
                                Text("Open YouTube App")
                            }
                            .foregroundColor(Theme.Colors.primary)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .padding(.vertical, Theme.Spacing.sm)

                    }
                    .padding()
                    
                    Spacer(minLength: 80)
                }
            }
            .navigationTitle("YouTube Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        #if DEBUG
                        print("📺 YouTubeInputView: Canceling extraction")
                        #endif
                        Task {
                            await viewModel.cleanup()
                            dismiss()
                        }
                    }
                }
            }
        }
        .onChange(of: scenePhase) { newPhase in
            #if DEBUG
            print("📺 YouTubeInputView: Scene phase changed to \(newPhase)")
            #endif
            if newPhase == .active {
                checkClipboard()
            }
        }
    }
    
    // MARK: - Helper Methods
    private func checkClipboard() {
        #if DEBUG
        print("📺 YouTubeInputView: Checking clipboard for YouTube URL")
        #endif
        if let clipboardString = UIPasteboard.general.string,
           clipboardString.contains("youtube.com") || clipboardString.contains("youtu.be") {
            toastManager.show("YouTube URL detected in clipboard", type: .info, action: ToastAction(title: "Paste") {
                viewModel.urlInput = clipboardString
                #if DEBUG
                print("📺 YouTubeInputView: Auto-pasted YouTube URL from clipboard")
                #endif
            })
        }
    }
    
    private func validateURL() {
        Task {
            do {
                try await viewModel.validateAndFetchMetadata()
            } catch {
                toastManager.show(error.localizedDescription, type: .error)
            }
        }
    }
    
    private func extractAudio() {
        Task {
            do {
                try await viewModel.extractAudio()
                toastManager.show("Audio extracted successfully", type: .success)
                dismiss()
            } catch {
                toastManager.show(error.localizedDescription, type: .error)
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Preview Provider
#if DEBUG
struct YouTubeInputView_Previews: PreviewProvider {
    static var previews: some View {
        YouTubeInputView(context: PersistenceController.preview.container.viewContext)
    }
}
#endif
