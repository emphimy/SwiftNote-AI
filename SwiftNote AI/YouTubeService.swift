import Foundation
import UIKit
import GoogleSignIn
import GoogleAPIClientForREST

// MARK: - YouTube Error
enum YouTubeError: LocalizedError {
    case invalidVideoId
    case transcriptNotAvailable
    case apiError(String)
    case rateLimitExceeded
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .invalidVideoId: return "Invalid YouTube video ID"
        case .transcriptNotAvailable: return "Transcript not available for this video"
        case .apiError(let message): return message
        case .rateLimitExceeded: return "API rate limit exceeded"
        case .invalidResponse: return "Invalid response from YouTube API"
        }
    }
}

// MARK: - YouTube Service
@MainActor
final class YouTubeService {
    // MARK: - Private Properties
    private let service: GTLRYouTubeService
    private let session: URLSession
    private let transcriptService: YouTubeTranscriptService
    private static let scopes = [
        "https://www.googleapis.com/auth/youtube.readonly",
        "https://www.googleapis.com/auth/youtube.force-ssl",
        "https://www.googleapis.com/auth/youtubepartner"
    ]
    private var currentUser: GIDGoogleUser?
    
    // MARK: - Initialization
    init() {
        self.service = GTLRYouTubeService()
        self.session = URLSession.shared
        self.transcriptService = YouTubeTranscriptService()
        
        // Try to restore previous sign-in
        if let previousUser = GIDSignIn.sharedInstance.currentUser {
            self.currentUser = previousUser
            self.service.authorizer = previousUser.fetcherAuthorizer
        }
    }
    
    // MARK: - Public Methods
    func signIn() async throws {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first as? UIWindowScene
        guard let rootViewController = windowScene?.windows.first?.rootViewController else {
            throw YouTubeError.apiError("No root view controller found")
        }
        
        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: rootViewController,
            hint: nil,
            additionalScopes: Self.scopes
        )
        
        self.currentUser = result.user
        self.service.authorizer = result.user.fetcherAuthorizer
        UserDefaults.standard.set(true, forKey: "isSignedInToGoogle")
    }
    
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        self.currentUser = nil
        self.service.authorizer = nil
        UserDefaults.standard.removeObject(forKey: "isSignedInToGoogle")
    }
    
    var isSignedIn: Bool {
        return currentUser != nil
    }
    
    func getTranscript(videoId: String) async throws -> String {
        guard !videoId.isEmpty else {
            throw YouTubeError.invalidVideoId
        }
        
        // First get video details to ensure we have access
        let query = GTLRYouTubeQuery_VideosList.query(withPart: ["snippet"])
        query.identifier = [videoId]
        
        let response: GTLRYouTube_VideoListResponse = try await withCheckedThrowingContinuation { continuation in
            service.executeQuery(query) { (ticket: GTLRServiceTicket, response: Any?, error: Error?) in
                if let error = error {
                    continuation.resume(throwing: YouTubeError.apiError(error.localizedDescription))
                    return
                }
                
                guard let response = response as? GTLRYouTube_VideoListResponse else {
                    continuation.resume(throwing: YouTubeError.invalidResponse)
                    return
                }
                
                continuation.resume(returning: response)
            }
        }
        
        guard let _ = response.items?.first else {
            throw YouTubeError.invalidResponse
        }
        
        // Use the transcript service to get the actual transcript
        return try await transcriptService.getTranscript(videoId: videoId)
    }
    
    func getVideoMetadata(videoId: String) async throws -> YouTubeConfig.VideoMetadata {
        guard !videoId.isEmpty else {
            throw YouTubeError.invalidVideoId
        }
        
        let query = GTLRYouTubeQuery_VideosList.query(withPart: ["snippet", "contentDetails"])
        query.identifier = [videoId]
        
        let response: GTLRYouTube_VideoListResponse = try await withCheckedThrowingContinuation { continuation in
            service.executeQuery(query) { (ticket: GTLRServiceTicket, response: Any?, error: Error?) in
                if let error = error {
                    continuation.resume(throwing: YouTubeError.apiError(error.localizedDescription))
                    return
                }
                
                guard let response = response as? GTLRYouTube_VideoListResponse else {
                    continuation.resume(throwing: YouTubeError.invalidResponse)
                    return
                }
                
                continuation.resume(returning: response)
            }
        }
        
        guard let video = response.items?.first,
              let snippet = video.snippet else {
            throw YouTubeError.invalidResponse
        }
        
        return YouTubeConfig.VideoMetadata(
            id: videoId,
            title: snippet.title ?? "Untitled",
            duration: nil,
            thumbnailURL: snippet.thumbnails?.high?.url ?? "",
            description: snippet.descriptionProperty
        )
    }
}
