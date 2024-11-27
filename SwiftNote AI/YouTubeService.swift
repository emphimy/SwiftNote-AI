import Foundation

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
    private let apiKey: String
    private let session: URLSession
    private let transcriptProcessor: TranscriptProcessor
    
    // MARK: - Initialization
    init(apiKey: String = Bundle.main.infoDictionary?["YouTubeAPIKey"] as? String ?? "") {
        self.apiKey = apiKey
        self.session = URLSession.shared
        self.transcriptProcessor = TranscriptProcessor()
        
        #if DEBUG
        print("""
        📺 YouTubeService: Initialized with API key
        - Key present: \(!apiKey.isEmpty)
        - Key length: \(apiKey.count)
        """)
        #endif
    }
    
    // MARK: - Public Methods
    func getTranscript(videoId: String) async throws -> String {
        guard !videoId.isEmpty else {
            throw YouTubeError.invalidVideoId
        }

        #if DEBUG
        print("📺 YouTubeService: Fetching captions for video: \(videoId)")
        #endif

        // First get available captions
        let captionsURL = URL(string: "\(YouTubeConfig.apiBaseURL)/captions")!
            .appendingQueryItems([
                "videoId": videoId,
                "key": apiKey,
                "part": "snippet"
            ])

        let (captionsData, response) = try await session.data(from: captionsURL)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw YouTubeError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let captionsResponse = try JSONDecoder().decode(CaptionsResponse.self, from: captionsData)
            
            // Priority: Manual captions in any language > Auto-generated captions
            let caption = captionsResponse.items.first { caption in
                caption.snippet.trackKind == "standard"
            } ?? captionsResponse.items.first
            
            guard let selectedCaption = caption else {
                #if DEBUG
                print("📺 YouTubeService: No captions available for video: \(videoId)")
                #endif
                throw YouTubeError.transcriptNotAvailable
            }
            
            #if DEBUG
            print("📺 YouTubeService: Selected caption - Language: \(selectedCaption.snippet.language), Type: \(selectedCaption.snippet.trackKind)")
            #endif

            // Download selected transcript
            let transcriptURL = URL(string: "\(YouTubeConfig.apiBaseURL)/captions/\(selectedCaption.id)")!
                .appendingQueryItems(["key": apiKey])

            let (transcriptData, transcriptResponse) = try await session.data(from: transcriptURL)
            
            guard let transcriptHTTPResponse = transcriptResponse as? HTTPURLResponse else {
                throw YouTubeError.invalidResponse
            }

            switch transcriptHTTPResponse.statusCode {
            case 200:
                return String(decoding: transcriptData, as: UTF8.self)
            case 429:
                throw YouTubeError.rateLimitExceeded
            default:
                throw YouTubeError.apiError("HTTP \(transcriptHTTPResponse.statusCode)")
            }
            
        case 429:
            throw YouTubeError.rateLimitExceeded
        default:
            throw YouTubeError.apiError("HTTP \(httpResponse.statusCode)")
        }
    }
    
    func getVideoMetadata(videoId: String) async throws -> YouTubeConfig.VideoMetadata {
        guard !videoId.isEmpty else {
            #if DEBUG
            print("📺 YouTubeService: Invalid video ID provided")
            #endif
            throw YouTubeError.invalidVideoId
        }
        
        if let cachedData = YouTubeCacheManager.shared.getCachedResponse(for: videoId),
           let metadata = try? JSONDecoder().decode(YouTubeConfig.VideoMetadata.self, from: cachedData) {
            #if DEBUG
            print("📺 YouTubeService: Returning cached metadata for video: \(videoId)")
            #endif
            return metadata
        }
        
        let metadataURL = URL(string: "\(YouTubeConfig.apiBaseURL)/videos")!
            .appendingQueryItems([
                "id": videoId,
                "key": apiKey,
                "part": "snippet,contentDetails"
            ])
        
        #if DEBUG
        print("📺 YouTubeService: Fetching metadata for video: \(videoId)")
        #endif
        
        let (data, response) = try await session.data(from: metadataURL)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw YouTubeError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200:
            let metadata = try JSONDecoder().decode(YouTubeConfig.VideoMetadata.self, from: data)
            YouTubeCacheManager.shared.setCachedResponse(data, for: videoId)
            return metadata
            
        case 403:
            #if DEBUG
            print("""
            📺 YouTubeService: API Error
            - Status Code: 403
            - API Key length: \(apiKey.count)
            - API Key: \(apiKey.prefix(10))...
            """)
            #endif
            
            if apiKey.isEmpty {
                throw YouTubeError.apiError("YouTube API key not configured")
            } else {
                throw YouTubeError.apiError(YouTubeConfig.errorMessages["invalidAPIKey"] ?? "API Error")
            }
            
        case 429:
            #if DEBUG
            print("📺 YouTubeService: Rate limit exceeded")
            #endif
            throw YouTubeError.rateLimitExceeded
            
        default:
            #if DEBUG
            print("📺 YouTubeService: HTTP Error \(httpResponse.statusCode)")
            #endif
            throw YouTubeError.apiError("HTTP \(httpResponse.statusCode)")
        }
    }
    
    // MARK: - Private Methods
    private func fetchRawTranscript(videoId: String) async throws -> String {
        #if DEBUG
        print("📺 YouTubeService: Fetching raw transcript for video: \(videoId)")
        #endif
        
        let captionsURL = URL(string: "\(YouTubeConfig.apiBaseURL)/captions")!
            .appendingQueryItems([
                "videoId": videoId,
                "key": apiKey,
                "part": "snippet"
            ])
        
        let (captionsData, response) = try await session.data(from: captionsURL)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw YouTubeError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200:
            let captionsResponse = try JSONDecoder().decode(CaptionsResponse.self, from: captionsData)
            guard let captionId = captionsResponse.items.first?.id else {
                #if DEBUG
                print("📺 YouTubeService: No captions available for video: \(videoId)")
                #endif
                throw YouTubeError.transcriptNotAvailable
            }
            
            let transcriptURL = URL(string: "\(YouTubeConfig.apiBaseURL)/captions/\(captionId)")!
                .appendingQueryItems(["key": apiKey])
            
            let (transcriptData, transcriptResponse) = try await session.data(from: transcriptURL)
            
            guard let transcriptHTTPResponse = transcriptResponse as? HTTPURLResponse else {
                throw YouTubeError.invalidResponse
            }
            
            switch transcriptHTTPResponse.statusCode {
            case 200:
                return String(decoding: transcriptData, as: UTF8.self)
            case 429:
                #if DEBUG
                print("📺 YouTubeService: Rate limit exceeded while fetching transcript")
                #endif
                throw YouTubeError.rateLimitExceeded
            default:
                #if DEBUG
                print("📺 YouTubeService: HTTP error \(transcriptHTTPResponse.statusCode) while fetching transcript")
                #endif
                throw YouTubeError.apiError("HTTP \(transcriptHTTPResponse.statusCode)")
            }
            
        case 429:
            throw YouTubeError.rateLimitExceeded
        default:
            throw YouTubeError.apiError("HTTP \(httpResponse.statusCode)")
        }
    }
}

// MARK: - Response Models
private extension YouTubeService {
    struct CaptionsResponse: Codable {
        let items: [Caption]
        
        // Add custom decoding
        init(from decoder: Decoder) throws {
            #if DEBUG
            print("📺 YouTubeService: Decoding CaptionsResponse")
            #endif
            
            let container = try decoder.container(keyedBy: CodingKeys.self)
            do {
                items = try container.decode([Caption].self, forKey: .items)
            } catch {
                #if DEBUG
                print("📺 YouTubeService: Error decoding items - \(error)")
                print("📺 YouTubeService: Failed to decode captions response")
                #endif
                items = []
            }
        }
    }

    struct Caption: Codable {
        let id: String
        let snippet: CaptionSnippet
        
        // Add custom decoding
        init(from decoder: Decoder) throws {
            #if DEBUG
            print("📺 YouTubeService: Decoding Caption")
            #endif
            
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            snippet = try container.decode(CaptionSnippet.self, forKey: .snippet)
        }
    }
    
    struct CaptionSnippet: Codable {
        let language: String
        let trackKind: String
        
        enum CodingKeys: String, CodingKey {
            case language
            case trackKind = "kind"
        }
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
