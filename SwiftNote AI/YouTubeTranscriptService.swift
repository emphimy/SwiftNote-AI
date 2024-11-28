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
        
        // Configure URLSession with timeout
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 900
        let sessionWithTimeout = URLSession(configuration: config)
        
        // Fetch the actual transcript
        let transcriptURL = URL(string: baseUrl)!
        var request = URLRequest(url: transcriptURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Safari/537.36", forHTTPHeaderField: "User-Agent")
        
        let (transcriptData, _) = try await sessionWithTimeout.data(from: transcriptURL)
        
        guard let xmlString = String(data: transcriptData, encoding: .utf8) else {
            throw YouTubeTranscriptError.invalidResponse
        }
        
        // Process transcript with larger chunks and better memory management
        let pattern = "<text[^>]*>([^<]*)</text>"
        let regex = try NSRegularExpression(pattern: pattern)
        
        var transcriptParts: [String] = []
        transcriptParts.reserveCapacity(1000) // Pre-allocate for better performance
        
        // Process XML in chunks
        var currentIndex = xmlString.startIndex
        let totalSize = xmlString.count
        let chunkSize = 100000
        
        while currentIndex < xmlString.endIndex {
            autoreleasepool {
                let endIndex = xmlString.index(currentIndex, offsetBy: min(chunkSize, xmlString.distance(from: currentIndex, to: xmlString.endIndex)))
                let chunk = String(xmlString[currentIndex..<endIndex])
                
                let range = NSRange(chunk.startIndex..., in: chunk)
                let matches = regex.matches(in: chunk, range: range)
                
                for match in matches {
                    if let range = Range(match.range(at: 1), in: chunk) {
                        let text = String(chunk[range])
                            .replacingOccurrences(of: "&amp;", with: "&")
                            .replacingOccurrences(of: "&quot;", with: "\"")
                            .replacingOccurrences(of: "&#39;", with: "'")
                            .replacingOccurrences(of: "&lt;", with: "<")
                            .replacingOccurrences(of: "&gt;", with: ">")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty {
                            transcriptParts.append(text)
                        }
                    }
                }
                
                currentIndex = endIndex
            }
        }
        
        // Combine transcript parts into proper paragraphs
        let formattedTranscript = transcriptParts
            .enumerated()
            .map { index, text in
                // Add period if the text doesn't end with punctuation
                let needsPeriod = !text.hasSuffix(".") && !text.hasSuffix("!") && !text.hasSuffix("?")
                let punctuatedText = needsPeriod ? text + "." : text
                
                // Add space or newline based on context
                if index % 5 == 4 { // Create paragraphs every 5 sentences
                    return punctuatedText + "\n\n"
                } else {
                    return punctuatedText + " "
                }
            }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return formattedTranscript
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
