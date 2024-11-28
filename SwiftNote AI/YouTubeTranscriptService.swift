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
    
    func getTranscript(videoId: String) async throws -> String {
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
    
    private func fetchTranscript(videoId: String, playerResponse: [String: Any]) async throws -> String {
        let url = URL(string: "\(baseURL)/youtubei/v1/get_transcript")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        
        // Get necessary data from player response
        guard let captions = playerResponse["captions"] as? [String: Any],
              let playerCaptionsTracklistRenderer = captions["playerCaptionsTracklistRenderer"] as? [String: Any],
              let captionsArray = playerCaptionsTracklistRenderer["captionTracks"] as? [[String: Any]],
              let firstCaption = captionsArray.first,
              let baseUrl = firstCaption["baseUrl"] as? String else {
            throw YouTubeTranscriptError.transcriptNotAvailable
        }
        
        #if DEBUG
        print("📺 YouTubeTranscriptService: Found caption URL: \(baseUrl)")
        #endif
        
        // Fetch the actual transcript
        let transcriptURL = URL(string: baseUrl)!
        let (transcriptData, _) = try await session.data(from: transcriptURL)
        
        guard let xmlString = String(data: transcriptData, encoding: .utf8) else {
            throw YouTubeTranscriptError.invalidResponse
        }
        
        // Parse the XML to get transcript text
        var transcript = ""
        let pattern = "<text[^>]*>([^<]*)</text>"
        let regex = try NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: xmlString, range: NSRange(xmlString.startIndex..., in: xmlString))
        
        for match in matches {
            if let range = Range(match.range(at: 1), in: xmlString) {
                let text = String(xmlString[range])
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "&quot;", with: "\"")
                    .replacingOccurrences(of: "&#39;", with: "'")
                    .replacingOccurrences(of: "&lt;", with: "<")
                    .replacingOccurrences(of: "&gt;", with: ">")
                transcript += text + "\n"
            }
        }
        
        guard !transcript.isEmpty else {
            throw YouTubeTranscriptError.transcriptNotAvailable
        }
        
        return transcript
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
