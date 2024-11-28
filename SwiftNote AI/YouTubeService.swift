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
    private let transcriptProcessor: TranscriptProcessor
    private var currentUser: GIDGoogleUser?
    
    // MARK: - Initialization
    init() {
        self.service = GTLRYouTubeService()
        self.session = URLSession.shared
        self.transcriptProcessor = TranscriptProcessor()
        
#if DEBUG
        print("📺 YouTubeService: Initialized with Google Sign-In")
#endif
    }
    
    // MARK: - Public Methods
    func getTranscript(videoId: String) async throws -> String {
        guard !videoId.isEmpty else {
            throw YouTubeError.invalidVideoId
        }
        
#if DEBUG
        print("📺 YouTubeService: Fetching transcript for video: \(videoId)")
#endif
        
        return try await fetchRawTranscript(videoId: videoId)
    }
    
    func getVideoMetadata(videoId: String) async throws -> YouTubeConfig.VideoMetadata {
        guard !videoId.isEmpty else {
#if DEBUG
            print("📺 YouTubeService: Invalid video ID provided")
#endif
            throw YouTubeError.invalidVideoId
        }
        
        guard isSignedIn() else {
            throw YouTubeError.apiError("Not signed in with Google")
        }
        
        let parts = ["snippet", "contentDetails"]
        let query = GTLRYouTubeQuery_VideosList.query(withPart: parts)
        query.identifier = [videoId]
        
        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<YouTubeConfig.VideoMetadata, Error>) in
            
            service.executeQuery(query) { (ticket, response, error) in
                if let error = error {
                    continuation.resume(throwing: YouTubeError.apiError(error.localizedDescription))
                    return
                }
                
                // Cast response to GTLRYouTube_VideoListResponse
                guard let videoList = response as? GTLRYouTube_VideoListResponse,
                      let video = videoList.items?.first else {
                    continuation.resume(throwing: YouTubeError.invalidVideoId)
                    return
                }
                
                let metadata = YouTubeConfig.VideoMetadata(
                    id: video.identifier ?? "",
                    title: video.snippet?.title ?? "",
                    duration: video.contentDetails?.duration,
                    thumbnailURL: video.snippet?.thumbnails?.high?.url,
                    description: video.snippet?.descriptionProperty
                )
                
                continuation.resume(returning: metadata)
            }
        }
        
        return result
    }
    
    // MARK: - Authentication Methods
    func signIn() async throws {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            throw YouTubeError.apiError("No window scene available")
        }
        
        let gidSignInResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: window.rootViewController!)
        self.currentUser = gidSignInResult.user
        
        // Configure the YouTube service with the user's authentication
        if let user = currentUser {
            service.authorizer = user.fetcherAuthorizer
        }
        
#if DEBUG
        print("📺 YouTubeService: Successfully signed in with Google")
#endif
    }
    
    func isSignedIn() -> Bool {
        return currentUser != nil
    }
    
    // MARK: - Private Methods
    private func fetchRawTranscript(videoId: String) async throws -> String {
#if DEBUG
        print("📺 YouTubeService: Fetching raw transcript for video: \(videoId)")
#endif
        
        let query = GTLRYouTubeQuery_CaptionsList.query(withPart: ["snippet"], videoId: videoId)
        
        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            service.executeQuery(query) { (ticket, response, error) in
                if let error = error {
#if DEBUG
                    print("📺 YouTubeService: Error fetching captions - \(error)")
#endif
                    continuation.resume(throwing: YouTubeError.apiError(error.localizedDescription))
                    return
                }
                
                guard let captionList = response as? GTLRYouTube_CaptionListResponse,
                      let captions = captionList.items,
                      !captions.isEmpty else {
                    continuation.resume(throwing: YouTubeError.transcriptNotAvailable)
                    return
                }
                
                guard let firstCaption = captions.first,
                      let captionId = firstCaption.identifier else {
                    continuation.resume(throwing: YouTubeError.transcriptNotAvailable)
                    return
                }
                
                // Create a direct URL request for caption download
                guard let user = self.currentUser else {
                    continuation.resume(throwing: YouTubeError.apiError("Not authenticated"))
                    return
                }

                let accessToken = user.accessToken.tokenString
                
                let urlString = "https://www.googleapis.com/youtube/v3/captions/\(captionId)/download"
                guard var urlComponents = URLComponents(string: urlString) else {
                    continuation.resume(throwing: YouTubeError.apiError("Invalid URL"))
                    return
                }
                
                urlComponents.queryItems = [URLQueryItem(name: "tfmt", value: "srt")]
                
                guard let url = urlComponents.url else {
                    continuation.resume(throwing: YouTubeError.apiError("Invalid URL"))
                    return
                }
                
                var request = URLRequest(url: url)
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                
#if DEBUG
                print("📺 YouTubeService: Requesting caption download from: \(url)")
#endif
                
                URLSession.shared.dataTask(with: request) { data, response, error in
                    if let error = error {
#if DEBUG
                        print("📺 YouTubeService: Caption download error - \(error)")
#endif
                        continuation.resume(throwing: YouTubeError.apiError(error.localizedDescription))
                        return
                    }
                    
                    guard let data = data,
                          let transcript = String(data: data, encoding: .utf8) else {
                        continuation.resume(throwing: YouTubeError.invalidResponse)
                        return
                    }
                    
#if DEBUG
                    print("📺 YouTubeService: Successfully downloaded caption data")
#endif
                    
                    continuation.resume(returning: transcript)
                }.resume()
            }
        }
        
        return result
    }
}

// MARK: - URL Extension
private extension URL {
    func appendingQueryItems(_ items: [String: String]) -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: true)!
        components.queryItems = items.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }
}
