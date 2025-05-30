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

// MARK: - Video Metadata
struct YouTubeVideoMetadata {
    let title: String
    let description: String
    let videoId: String
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
    func getTranscript(videoId: String, preferredLanguage: String? = nil) async throws -> (transcript: String, language: String?) {
        return try await transcriptService.getTranscript(videoId: videoId, preferredLanguage: preferredLanguage)
    }

    func getVideoMetadata(videoId: String) async throws -> YouTubeVideoMetadata {
        // For now, return a basic metadata object with just the video ID as title
        // This can be expanded later to fetch actual metadata from YouTube API
        return YouTubeVideoMetadata(
            title: "YouTube Video \(videoId)",
            description: "Video content from YouTube",
            videoId: videoId
        )
    }
}
