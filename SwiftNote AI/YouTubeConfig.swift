import SwiftUI

// MARK: - YouTube Configuration
enum YouTubeConfig {
    // MARK: - API Constants
    static let apiBaseURL = "https://www.googleapis.com/youtube/v3"
    static let maxDuration: TimeInterval = 14400 // 4 hours
    
    // MARK: - Cache Configuration
    static let cacheDuration: TimeInterval = 3600 // 1 hour
    static let maxCacheSize: Int = 100 // Max number of cached responses
    
    // MARK: - Rate Limiting
    static let requestsPerMinute: Int = 60
    static let quotaPerDay: Int = 10000
    
    // MARK: - Error Messages
    static let errorMessages = [
        "quotaExceeded": "We are experiencing. Please try again tomorrow.",
        "invalidAPIKey": "Invalid YouTube API key. Please check your configuration.",
        "networkError": "Network error occurred. Please check your connection.",
        "videoUnavailable": "This video is unavailable or private.",
        "noTranscript": "No transcript available for this video.",
        "rateLimited": "Too many requests. Please try again in a few minutes."
    ]
    
    // MARK: - API Response Models
    struct VideoMetadata: Codable {
        let id: String
        let title: String
        let duration: String?
        let thumbnailURL: String?
        
        var videoID: String { id }
        
        enum CodingKeys: String, CodingKey {
            case id
            case snippet
            case contentDetails
        }
        
        enum SnippetKeys: String, CodingKey {
            case title
            case thumbnails
        }
        
        enum ThumbnailKeys: String, CodingKey {
            case standard
            case high
            case maxres
        }
        
        enum ThumbnailDetailKeys: String, CodingKey {
            case url
        }
        
        enum ContentDetailsKeys: String, CodingKey {
            case duration
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            
            // Decode snippet
            let snippet = try container.nestedContainer(keyedBy: SnippetKeys.self, forKey: .snippet)
            title = try snippet.decode(String.self, forKey: .title)
            
            // Decode thumbnails (optional)
            if let thumbnails = try? snippet.nestedContainer(keyedBy: ThumbnailKeys.self, forKey: .thumbnails) {
                if let maxres = try? thumbnails.nestedContainer(keyedBy: ThumbnailDetailKeys.self, forKey: .maxres) {
                    thumbnailURL = try maxres.decode(String.self, forKey: .url)
                } else if let high = try? thumbnails.nestedContainer(keyedBy: ThumbnailDetailKeys.self, forKey: .high) {
                    thumbnailURL = try high.decode(String.self, forKey: .url)
                } else if let standard = try? thumbnails.nestedContainer(keyedBy: ThumbnailDetailKeys.self, forKey: .standard) {
                    thumbnailURL = try standard.decode(String.self, forKey: .url)
                } else {
                    thumbnailURL = nil
                }
            } else {
                thumbnailURL = nil
            }
            
            // Decode content details (optional)
            if let contentDetails = try? container.nestedContainer(keyedBy: ContentDetailsKeys.self, forKey: .contentDetails) {
                duration = try contentDetails.decode(String.self, forKey: .duration)
            } else {
                duration = nil
            }
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            
            // Encode snippet
            var snippet = container.nestedContainer(keyedBy: SnippetKeys.self, forKey: .snippet)
            try snippet.encode(title, forKey: .title)
            
            // Encode thumbnails (if available)
            if let thumbnailURL = thumbnailURL {
                var thumbnails = snippet.nestedContainer(keyedBy: ThumbnailKeys.self, forKey: .thumbnails)
                var standard = thumbnails.nestedContainer(keyedBy: ThumbnailDetailKeys.self, forKey: .standard)
                try standard.encode(thumbnailURL, forKey: .url)
            }
            
            // Encode content details (if available)
            if let duration = duration {
                var contentDetails = container.nestedContainer(keyedBy: ContentDetailsKeys.self, forKey: .contentDetails)
                try contentDetails.encode(duration, forKey: .duration)
            }
        }
    }
}

// MARK: - YouTube Cache Manager
final class YouTubeCacheManager {
    static let shared = YouTubeCacheManager()
    private var cache: NSCache<NSString, CachedResponse>
    
    private init() {
        cache = NSCache<NSString, CachedResponse>()
        cache.countLimit = YouTubeConfig.maxCacheSize
        
        #if DEBUG
        print("📺 YouTubeCacheManager: Initialized with max size: \(YouTubeConfig.maxCacheSize)")
        #endif
    }
    
    func setCachedResponse(_ response: Data, for key: String) {
        let cachedResponse = CachedResponse(data: response, timestamp: Date())
        cache.setObject(cachedResponse, forKey: key as NSString)
        
        #if DEBUG
        print("📺 YouTubeCacheManager: Cached response for key: \(key)")
        #endif
    }
    
    func getCachedResponse(for key: String) -> Data? {
        guard let cachedResponse = cache.object(forKey: key as NSString),
              Date().timeIntervalSince(cachedResponse.timestamp) < YouTubeConfig.cacheDuration else {
            #if DEBUG
            print("📺 YouTubeCacheManager: Cache miss or expired for key: \(key)")
            #endif
            return nil
        }
        
        #if DEBUG
        print("📺 YouTubeCacheManager: Cache hit for key: \(key)")
        #endif
        return cachedResponse.data
    }
}

// MARK: - Cache Models
private final class CachedResponse: NSObject {
    let data: Data
    let timestamp: Date
    
    init(data: Data, timestamp: Date) {
        self.data = data
        self.timestamp = timestamp
        super.init()
    }
}
