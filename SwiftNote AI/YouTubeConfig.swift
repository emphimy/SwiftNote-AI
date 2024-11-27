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
            case title = "snippet"
            case duration = "contentDetails"
            case thumbnailURL = "thumbnails"
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
