import Foundation

// MARK: - YouTube Transcript Error
enum YouTubeTranscriptError: LocalizedError {
    case invalidVideoId
    case transcriptNotAvailable
    case networkError(String)
    case parsingError(String)
    case invalidResponse
    case jsonParsingError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidVideoId:
            return "Invalid YouTube video ID"
        case .transcriptNotAvailable:
            return "Transcript not available for this video"
        case .networkError(let message):
            return "Network error: \(message)"
        case .parsingError(let message):
            return "Parsing error: \(message)"
        case .invalidResponse:
            return "Invalid response from YouTube"
        case .jsonParsingError(let details):
            return "Failed to parse JSON: \(details)"
        }
    }
}

// MARK: - YouTube Transcript Service
final class YouTubeTranscriptService {
    private let session: URLSession
    private let baseURL = "https://www.youtube.com"
    private let clientVersion = "2.20230602.01.00"
    private let clientName = "3"
    
    init(session: URLSession = .shared) {
        self.session = session
    }
    
    // MARK: - Public Methods
    func getTranscript(videoId: String) async throws -> (transcript: String, language: String?) {
        #if DEBUG
        print("📺 YouTubeTranscriptService: Fetching transcript for video: \(videoId)")
        #endif
        
        // First get the initial player response to get context
        let playerResponse = try await fetchPlayerResponse(videoId: videoId)
        
        // Then get the transcript using the context
        return try await fetchTranscript(videoId: videoId, playerResponse: playerResponse)
    }
    
    private func fetchPlayerResponse(videoId: String) async throws -> [String: Any] {
        let url = URL(string: "\(baseURL)/watch?v=\(videoId)")!
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Safari/537.36", forHTTPHeaderField: "User-Agent")
        
        let (data, _) = try await session.data(for: request)
        
        guard let htmlString = String(data: data, encoding: .utf8) else {
            throw YouTubeTranscriptError.invalidResponse
        }
        
        #if DEBUG
        print("📺 YouTubeTranscriptService: Searching for ytInitialPlayerResponse in HTML...")
        #endif
        
        // Extract ytInitialPlayerResponse using a more robust approach
        if let startRange = htmlString.range(of: "ytInitialPlayerResponse = ") {
            let startIndex = startRange.upperBound
            var bracketCount = 0
            var foundStart = false
            var jsonString = ""
            
            // Iterate through characters to properly handle nested brackets
            for char in htmlString[startIndex...] {
                if !foundStart {
                    if char == "{" {
                        foundStart = true
                        bracketCount += 1
                        jsonString.append(char)
                    }
                    continue
                }
                
                jsonString.append(char)
                
                if char == "{" {
                    bracketCount += 1
                } else if char == "}" {
                    bracketCount -= 1
                    if bracketCount == 0 {
                        break
                    }
                }
            }
            
            #if DEBUG
            print("📺 YouTubeTranscriptService: Found JSON string, attempting to parse...")
            #endif
            
            if let jsonData = jsonString.data(using: .utf8),
               let playerResponse = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                return playerResponse
            } else {
                #if DEBUG
                print("📺 YouTubeTranscriptService: JSON parsing failed. JSON string length: \(jsonString.count)")
                if jsonString.count < 1000 {
                    print("📺 YouTubeTranscriptService: JSON string: \(jsonString)")
                }
                #endif
                throw YouTubeTranscriptError.jsonParsingError("Failed to parse player response JSON")
            }
        }
        
        throw YouTubeTranscriptError.jsonParsingError("Could not find ytInitialPlayerResponse in page")
    }
    
    private func fetchTranscript(videoId: String, playerResponse: [String: Any]) async throws -> (transcript: String, language: String?) {
        // Get necessary data from player response
        guard let captions = playerResponse["captions"] as? [String: Any],
              let playerCaptionsTracklistRenderer = captions["playerCaptionsTracklistRenderer"] as? [String: Any],
              let captionsArray = playerCaptionsTracklistRenderer["captionTracks"] as? [[String: Any]],
              let firstCaption = captionsArray.first,
              let baseUrl = firstCaption["baseUrl"] as? String else {
            throw YouTubeTranscriptError.transcriptNotAvailable
        }
        
        // Extract language code from the first caption
        let language = (firstCaption["languageCode"] as? String) ?? (firstCaption["vssId"] as? String)?.components(separatedBy: ".").first
        
        #if DEBUG
        print("📺 YouTubeTranscriptService: Detected language: \(language ?? "unknown")")
        #endif
        
        // Create URL for transcript
        guard let url = URL(string: baseUrl + "&fmt=json3") else {
            throw YouTubeTranscriptError.invalidVideoId
        }
        
        // Fetch transcript data
        let (data, _) = try await session.data(from: url)
        
        // Parse transcript JSON
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = json["events"] as? [[String: Any]] else {
            throw YouTubeTranscriptError.jsonParsingError("Invalid transcript format")
        }
        
        #if DEBUG
        print("📝 YouTubeTranscriptService: First event structure:")
        if let firstEvent = events.first {
            print(firstEvent)
        }
        #endif
        
        // Group segments by timestamp
        var currentGroup: [String] = []
        var currentStartTime: Int = 0
        var formattedTranscript = ""
        
        for event in events {
            if let segs = event["segs"] as? [[String: Any]],
               let startTime = event["tStartMs"] as? Int {
                
                // Combine all segments in this event
                let textParts = segs.compactMap { seg -> String? in
                    guard let text = seg["utf8"] as? String else { return nil }
                    return text.trimmingCharacters(in: .whitespacesAndNewlines)
                }.filter { !$0.isEmpty }
                
                if !textParts.isEmpty {
                    let combinedText = textParts.joined(separator: " ")
                    
                    let seconds = startTime / 1000
                    let minutes = seconds / 60
                    let remainingSeconds = seconds % 60
                    
                    formattedTranscript += String(format: "[%02d:%02d] %@\n", minutes, remainingSeconds, combinedText)
                }
            }
        }
        
        #if DEBUG
        print("📝 YouTubeTranscriptService: Sample of formatted transcript:")
        print(formattedTranscript.prefix(500))
        #endif
        
        return (formattedTranscript, language)
    }
    
    func getVideoMetadata(videoId: String) async throws -> YouTubeConfig.VideoMetadata {
        guard !videoId.isEmpty else {
            throw YouTubeTranscriptError.invalidVideoId
        }
        
        let videoUrl = "https://www.youtube.com/watch?v=\(videoId)"
        var request = URLRequest(url: URL(string: videoUrl)!)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw YouTubeTranscriptError.networkError("Invalid response type")
        }
        
        if httpResponse.statusCode != 200 {
            throw YouTubeTranscriptError.networkError("Server returned status code: \(httpResponse.statusCode)")
        }
        
        guard let htmlContent = String(data: data, encoding: .utf8) else {
            throw YouTubeTranscriptError.parsingError("Failed to decode HTML content")
        }
        
        // Extract title using regex
        let titlePattern = "<title>([^<]*)</title>"
        guard let titleRegex = try? NSRegularExpression(pattern: titlePattern),
              let titleMatch = titleRegex.firstMatch(in: htmlContent, range: NSRange(htmlContent.startIndex..., in: htmlContent)),
              let titleRange = Range(titleMatch.range(at: 1), in: htmlContent) else {
            throw YouTubeTranscriptError.parsingError("Failed to extract title")
        }
        
        var title = String(htmlContent[titleRange])
        if title.hasSuffix(" - YouTube") {
            title = String(title.dropLast(" - YouTube".count))
        }
        
        return YouTubeConfig.VideoMetadata(
            id: videoId,
            title: title,
            duration: nil,
            thumbnailURL: "https://img.youtube.com/vi/\(videoId)/hqdefault.jpg",
            description: nil
        )
    }
}
