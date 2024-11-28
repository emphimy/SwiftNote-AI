import Foundation

// MARK: - YouTube Error
enum YouTubeError: LocalizedError {
    case invalidVideoId
    case transcriptNotAvailable
    case networkError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidVideoId: return "Invalid YouTube video ID"
        case .transcriptNotAvailable: return "Transcript not available for this video"
        case .networkError(let message): return "Network error: \(message)"
        }
    }
}

// MARK: - YouTube Service
class YouTubeService {
    // MARK: - Private Properties
    private let transcriptService: YouTubeTranscriptService
    
    // MARK: - Initialization
    init() {
        self.transcriptService = YouTubeTranscriptService()
    }
    
    // MARK: - Public Methods
    func getTranscript(videoId: String) async throws -> String {
        return try await transcriptService.getTranscript(videoId: videoId)
    }
}
