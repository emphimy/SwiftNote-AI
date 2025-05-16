import Foundation

// MARK: - YouTube Transcript Error
enum YouTubeTranscriptError: LocalizedError {
    case invalidVideoId
    case transcriptNotAvailable
    case networkError(String)
    case parsingError(String)
    case invalidResponse
    case jsonParsingError(String)
    case emptyData

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
        case .emptyData:
            return "Received empty data from YouTube"
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

        do {
            // First get the initial player response to get context
            let playerResponse = try await fetchPlayerResponse(videoId: videoId)

            // Then get the transcript using the context
            return try await fetchTranscript(videoId: videoId, playerResponse: playerResponse)
        } catch {
            #if DEBUG
            print("📺 YouTubeTranscriptService: Error fetching transcript: \(error.localizedDescription)")

            // If it's a specific YouTube error, provide more details
            if let youtubeError = error as? YouTubeTranscriptError {
                switch youtubeError {
                case .jsonParsingError(let details):
                    print("📺 YouTubeTranscriptService: JSON parsing error: \(details)")
                case .networkError(let details):
                    print("📺 YouTubeTranscriptService: Network error: \(details)")
                case .parsingError(let details):
                    print("📺 YouTubeTranscriptService: Parsing error: \(details)")
                case .emptyData:
                    print("📺 YouTubeTranscriptService: Empty data error")
                default:
                    print("📺 YouTubeTranscriptService: Other YouTube error: \(youtubeError.localizedDescription)")
                }
            }
            #endif

            // Try alternative approach based on the error type
            if let youtubeError = error as? YouTubeTranscriptError {
                if youtubeError.errorDescription?.contains("JSON") == true ||
                   youtubeError.errorDescription?.contains("parse") == true {

                    #if DEBUG
                    print("📺 YouTubeTranscriptService: Trying alternative direct transcript approach...")
                    #endif

                    // Try the direct approach
                    return try await fetchTranscriptDirect(videoId: videoId)
                } else if case .emptyData = youtubeError {
                    #if DEBUG
                    print("📺 YouTubeTranscriptService: Trying alternative direct transcript approach for empty data...")
                    #endif

                    // Try the direct approach
                    do {
                        return try await fetchTranscriptDirect(videoId: videoId)
                    } catch {
                        // If direct approach fails, try the alternative URL approach
                        #if DEBUG
                        print("📺 YouTubeTranscriptService: Direct approach failed, trying alternative URL approach...")
                        #endif

                        do {
                            return try await fetchTranscriptAlternativeURL(videoId: videoId)
                        } catch {
                            // If alternative URL approach fails, try the transcript list approach
                            #if DEBUG
                            print("📺 YouTubeTranscriptService: Alternative URL approach failed, trying transcript list approach...")
                            #endif

                            do {
                                return try await fetchTranscriptFromList(videoId: videoId)
                            } catch {
                                // If transcript list approach fails, try the browser simulation approach
                                #if DEBUG
                                print("📺 YouTubeTranscriptService: Transcript list approach failed, trying browser simulation approach...")
                                #endif

                                return try await fetchTranscriptWithBrowserSimulation(videoId: videoId)
                            }
                        }
                    }
                }
            }

            // For other errors, wrap them in a YouTube error
            throw YouTubeTranscriptError.networkError("Failed to fetch transcript: \(error.localizedDescription)")
        }
    }

    // Direct transcript fetching approach based on the article
    private func fetchTranscriptDirect(videoId: String) async throws -> (transcript: String, language: String?) {
        #if DEBUG
        print("📺 YouTubeTranscriptService: Using direct transcript fetching approach")
        #endif

        // First, get the video page
        let videoUrl = "https://www.youtube.com/watch?v=\(videoId)"
        var request = URLRequest(url: URL(string: videoUrl)!)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw YouTubeTranscriptError.networkError("Failed to fetch video page")
        }

        guard let htmlString = String(data: data, encoding: .utf8) else {
            throw YouTubeTranscriptError.invalidResponse
        }

        // Extract the caption URL directly using regex
        let pattern = "\"captionTracks\":\\[\\{\"baseUrl\":\"(.*?)\".*?\"languageCode\":\"(.*?)\""

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            throw YouTubeTranscriptError.parsingError("Failed to create regex for direct transcript")
        }

        guard let match = regex.firstMatch(in: htmlString, range: NSRange(htmlString.startIndex..., in: htmlString)) else {
            throw YouTubeTranscriptError.transcriptNotAvailable
        }

        guard let baseUrlRange = Range(match.range(at: 1), in: htmlString),
              let languageCodeRange = Range(match.range(at: 2), in: htmlString) else {
            throw YouTubeTranscriptError.parsingError("Failed to extract caption URL")
        }

        var baseUrl = String(htmlString[baseUrlRange])
        let language = String(htmlString[languageCodeRange])

        // Unescape the URL
        baseUrl = baseUrl.replacingOccurrences(of: "\\u0026", with: "&")

        #if DEBUG
        print("📺 YouTubeTranscriptService: Direct approach - Found caption URL")
        print("📺 YouTubeTranscriptService: Language: \(language)")
        #endif

        // Fetch the transcript
        let transcriptUrl = baseUrl + "&fmt=json3"

        guard let url = URL(string: transcriptUrl) else {
            throw YouTubeTranscriptError.invalidVideoId
        }

        let (transcriptData, transcriptResponse) = try await session.data(from: url)

        guard let transcriptHttpResponse = transcriptResponse as? HTTPURLResponse,
              transcriptHttpResponse.statusCode == 200 else {
            throw YouTubeTranscriptError.networkError("Failed to fetch transcript data")
        }

        if transcriptData.isEmpty {
            #if DEBUG
            print("📺 YouTubeTranscriptService: Received empty data, trying XML format instead...")
            #endif

            // Try XML format instead
            return try await fetchTranscriptXML(baseUrl: baseUrl, language: language)
        }

        // Parse the transcript
        guard let json = try? JSONSerialization.jsonObject(with: transcriptData) as? [String: Any],
              let events = json["events"] as? [[String: Any]] else {
            #if DEBUG
            print("📺 YouTubeTranscriptService: JSON parsing failed, trying XML format instead...")
            #endif

            // Try XML format instead
            return try await fetchTranscriptXML(baseUrl: baseUrl, language: language)
        }

        var formattedTranscript = ""

        for event in events {
            if let segs = event["segs"] as? [[String: Any]],
               let startTime = event["tStartMs"] as? Int {

                // Combine all segments in this event
                let textParts = segs.compactMap { seg -> String? in
                    guard let text = seg["utf8"] as? String else { return nil }
                    return text.trimmingCharacters(in: .whitespacesAndNewlines)
                }

                if !textParts.isEmpty {
                    let combinedText = textParts.joined(separator: " ")

                    let seconds = startTime / 1000
                    let minutes = seconds / 60
                    let remainingSeconds = seconds % 60

                    formattedTranscript += String(format: "[%02d:%02d] %@\n", minutes, remainingSeconds, combinedText)
                }
            }
        }

        if formattedTranscript.isEmpty {
            throw YouTubeTranscriptError.transcriptNotAvailable
        }

        #if DEBUG
        print("📺 YouTubeTranscriptService: Direct approach - Successfully generated transcript")
        #endif

        return (formattedTranscript, language)
    }

    // Fetch transcript in XML format as a fallback
    private func fetchTranscriptXML(baseUrl: String, language: String?) async throws -> (transcript: String, language: String?) {
        #if DEBUG
        print("📺 YouTubeTranscriptService: Attempting to fetch transcript in XML format")
        #endif

        // Remove any existing format parameter and add XML format
        var xmlUrl = baseUrl
        if xmlUrl.contains("&fmt=") {
            // Remove existing format parameter
            let components = xmlUrl.components(separatedBy: "&fmt=")
            if components.count > 1 {
                let restComponents = components[1].components(separatedBy: "&")
                if restComponents.count > 1 {
                    xmlUrl = components[0] + "&" + restComponents[1...].joined(separator: "&")
                } else {
                    xmlUrl = components[0]
                }
            }
        }

        // Don't add any format parameter to get the default XML format

        #if DEBUG
        print("📺 YouTubeTranscriptService: XML URL: \(xmlUrl)")
        #endif

        guard let url = URL(string: xmlUrl) else {
            throw YouTubeTranscriptError.invalidVideoId
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw YouTubeTranscriptError.networkError("Failed to fetch XML transcript")
        }

        if data.isEmpty {
            throw YouTubeTranscriptError.emptyData
        }

        #if DEBUG
        print("📺 YouTubeTranscriptService: Received XML data of size: \(data.count) bytes")
        #endif

        // Parse XML data
        guard let xmlString = String(data: data, encoding: .utf8) else {
            throw YouTubeTranscriptError.parsingError("Failed to decode XML data")
        }

        // Simple XML parsing for transcript
        var formattedTranscript = ""

        // Use regular expression to extract text and timestamps
        let pattern = "<text start=\"([0-9\\.]+)\" dur=\"([0-9\\.]+)\">(.*?)</text>"

        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
            let matches = regex.matches(in: xmlString, range: NSRange(xmlString.startIndex..., in: xmlString))

            #if DEBUG
            print("📺 YouTubeTranscriptService: Found \(matches.count) text segments in XML")
            #endif

            for match in matches {
                guard let startRange = Range(match.range(at: 1), in: xmlString),
                      let textRange = Range(match.range(at: 3), in: xmlString) else {
                    continue
                }

                let startTimeString = String(xmlString[startRange])
                let text = String(xmlString[textRange])
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "&lt;", with: "<")
                    .replacingOccurrences(of: "&gt;", with: ">")
                    .replacingOccurrences(of: "&quot;", with: "\"")
                    .replacingOccurrences(of: "&#39;", with: "'")

                if let startTime = Double(startTimeString) {
                    let seconds = Int(startTime)
                    let minutes = seconds / 60
                    let remainingSeconds = seconds % 60

                    formattedTranscript += String(format: "[%02d:%02d] %@\n", minutes, remainingSeconds, text)
                }
            }

            if formattedTranscript.isEmpty {
                throw YouTubeTranscriptError.transcriptNotAvailable
            }

            #if DEBUG
            print("📺 YouTubeTranscriptService: Successfully parsed XML transcript")
            print("📺 YouTubeTranscriptService: First 500 characters of transcript:")
            print(formattedTranscript.prefix(500))
            #endif

            return (formattedTranscript, language)
        } catch {
            #if DEBUG
            print("📺 YouTubeTranscriptService: Error parsing XML: \(error.localizedDescription)")
            #endif
            throw YouTubeTranscriptError.parsingError("Failed to parse XML transcript: \(error.localizedDescription)")
        }
    }

    private func fetchPlayerResponse(videoId: String) async throws -> [String: Any] {
        let url = URL(string: "\(baseURL)/watch?v=\(videoId)")!
        var request = URLRequest(url: url)
        // Update User-Agent to match the one used in getVideoMetadata
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

        #if DEBUG
        print("📺 YouTubeTranscriptService: Fetching HTML for video ID: \(videoId)")
        #endif

        let (data, response) = try await session.data(for: request)

        // Check HTTP response status
        guard let httpResponse = response as? HTTPURLResponse else {
            throw YouTubeTranscriptError.networkError("Invalid response type")
        }

        if httpResponse.statusCode != 200 {
            throw YouTubeTranscriptError.networkError("Server returned status code: \(httpResponse.statusCode)")
        }

        guard let htmlString = String(data: data, encoding: .utf8) else {
            throw YouTubeTranscriptError.invalidResponse
        }

        #if DEBUG
        print("📺 YouTubeTranscriptService: Received HTML response of length: \(htmlString.count)")
        print("📺 YouTubeTranscriptService: Searching for ytInitialPlayerResponse in HTML...")
        #endif

        // First attempt: Extract using standard pattern
        if let playerResponse = try? extractPlayerResponse(from: htmlString, using: "ytInitialPlayerResponse = ") {
            return playerResponse
        }

        // Second attempt: Try alternative pattern
        if let playerResponse = try? extractPlayerResponse(from: htmlString, using: "var ytInitialPlayerResponse = ") {
            return playerResponse
        }

        // Third attempt: Try with regex
        if let playerResponse = try? extractPlayerResponseWithRegex(from: htmlString) {
            return playerResponse
        }

        // If all attempts fail, throw an error
        throw YouTubeTranscriptError.jsonParsingError("Could not find ytInitialPlayerResponse in page")
    }

    private func extractPlayerResponse(from htmlString: String, using pattern: String) throws -> [String: Any] {
        guard let startRange = htmlString.range(of: pattern) else {
            throw YouTubeTranscriptError.jsonParsingError("Pattern '\(pattern)' not found in HTML")
        }

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

        if jsonString.isEmpty {
            throw YouTubeTranscriptError.jsonParsingError("Empty JSON string extracted")
        }

        #if DEBUG
        print("📺 YouTubeTranscriptService: Found JSON string of length: \(jsonString.count)")
        print("📺 YouTubeTranscriptService: Attempting to parse JSON...")
        #endif

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw YouTubeTranscriptError.jsonParsingError("Failed to convert JSON string to data")
        }

        do {
            guard let playerResponse = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                throw YouTubeTranscriptError.jsonParsingError("Failed to parse JSON as dictionary")
            }

            #if DEBUG
            print("📺 YouTubeTranscriptService: Successfully parsed player response")
            #endif

            return playerResponse
        } catch {
            #if DEBUG
            print("📺 YouTubeTranscriptService: JSON parsing error: \(error.localizedDescription)")
            if jsonString.count < 1000 {
                print("📺 YouTubeTranscriptService: JSON string: \(jsonString)")
            }
            #endif
            throw YouTubeTranscriptError.jsonParsingError("Failed to parse player response JSON: \(error.localizedDescription)")
        }
    }

    private func extractPlayerResponseWithRegex(from htmlString: String) throws -> [String: Any] {
        // Pattern to match ytInitialPlayerResponse with any potential prefix
        let pattern = "(var\\s+)?ytInitialPlayerResponse\\s*=\\s*\\{.+?\\}\\s*;"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            throw YouTubeTranscriptError.parsingError("Failed to create regex")
        }

        guard let match = regex.firstMatch(in: htmlString, range: NSRange(htmlString.startIndex..., in: htmlString)) else {
            throw YouTubeTranscriptError.parsingError("No regex match found")
        }

        guard let matchRange = Range(match.range, in: htmlString) else {
            throw YouTubeTranscriptError.parsingError("Failed to convert match range")
        }

        var jsonString = String(htmlString[matchRange])

        // Remove variable declaration and trailing semicolon
        if let equalsRange = jsonString.range(of: "=") {
            jsonString = String(jsonString[equalsRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Remove trailing semicolon if present
        if jsonString.hasSuffix(";") {
            jsonString = String(jsonString.dropLast())
        }

        #if DEBUG
        print("📺 YouTubeTranscriptService: Extracted JSON with regex, length: \(jsonString.count)")
        #endif

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw YouTubeTranscriptError.jsonParsingError("Failed to convert regex JSON string to data")
        }

        do {
            guard let playerResponse = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                throw YouTubeTranscriptError.jsonParsingError("Failed to parse regex JSON as dictionary")
            }
            return playerResponse
        } catch {
            throw YouTubeTranscriptError.jsonParsingError("Failed to parse regex JSON: \(error.localizedDescription)")
        }
    }

    private func fetchTranscript(videoId: String, playerResponse: [String: Any]) async throws -> (transcript: String, language: String?) {
        #if DEBUG
        print("📺 YouTubeTranscriptService: Extracting caption data from player response")

        // Debug: Check if captions exist
        if playerResponse["captions"] == nil {
            print("📺 YouTubeTranscriptService: ERROR - 'captions' key not found in player response")
            print("📺 YouTubeTranscriptService: Available keys: \(playerResponse.keys.joined(separator: ", "))")
        }
        #endif

        // Get necessary data from player response
        guard let captions = playerResponse["captions"] as? [String: Any] else {
            throw YouTubeTranscriptError.transcriptNotAvailable
        }

        #if DEBUG
        // Debug: Check if playerCaptionsTracklistRenderer exists
        if captions["playerCaptionsTracklistRenderer"] == nil {
            print("📺 YouTubeTranscriptService: ERROR - 'playerCaptionsTracklistRenderer' key not found in captions")
            print("📺 YouTubeTranscriptService: Available keys in captions: \(captions.keys.joined(separator: ", "))")
        }
        #endif

        guard let playerCaptionsTracklistRenderer = captions["playerCaptionsTracklistRenderer"] as? [String: Any] else {
            throw YouTubeTranscriptError.transcriptNotAvailable
        }

        #if DEBUG
        // Debug: Check if captionTracks exists
        if playerCaptionsTracklistRenderer["captionTracks"] == nil {
            print("📺 YouTubeTranscriptService: ERROR - 'captionTracks' key not found in playerCaptionsTracklistRenderer")
            print("📺 YouTubeTranscriptService: Available keys: \(playerCaptionsTracklistRenderer.keys.joined(separator: ", "))")
        }
        #endif

        guard let captionTracks = playerCaptionsTracklistRenderer["captionTracks"] as? [[String: Any]] else {
            throw YouTubeTranscriptError.transcriptNotAvailable
        }

        #if DEBUG
        print("📺 YouTubeTranscriptService: Found \(captionTracks.count) caption tracks")
        #endif

        guard let firstCaption = captionTracks.first else {
            throw YouTubeTranscriptError.transcriptNotAvailable
        }

        #if DEBUG
        // Debug: Check if baseUrl exists
        if firstCaption["baseUrl"] == nil {
            print("📺 YouTubeTranscriptService: ERROR - 'baseUrl' key not found in first caption")
            print("📺 YouTubeTranscriptService: Available keys: \(firstCaption.keys.joined(separator: ", "))")
        }
        #endif

        guard let baseUrl = firstCaption["baseUrl"] as? String else {
            throw YouTubeTranscriptError.transcriptNotAvailable
        }

        // Extract language code from the first caption
        let language = (firstCaption["languageCode"] as? String) ?? (firstCaption["vssId"] as? String)?.components(separatedBy: ".").first

        #if DEBUG
        print("📺 YouTubeTranscriptService: Detected language: \(language ?? "unknown")")
        print("📺 YouTubeTranscriptService: Caption base URL: \(baseUrl)")
        #endif

        // Create URL for transcript
        let transcriptUrl = baseUrl + "&fmt=json3"
        guard let url = URL(string: transcriptUrl) else {
            throw YouTubeTranscriptError.invalidVideoId
        }

        #if DEBUG
        print("📺 YouTubeTranscriptService: Fetching transcript from URL: \(transcriptUrl)")
        #endif

        // Fetch transcript data
        let (data, response) = try await session.data(from: url)

        // Check HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw YouTubeTranscriptError.networkError("Invalid response type for transcript")
        }

        if httpResponse.statusCode != 200 {
            throw YouTubeTranscriptError.networkError("Server returned status code: \(httpResponse.statusCode) for transcript")
        }

        #if DEBUG
        print("📺 YouTubeTranscriptService: Received transcript data of size: \(data.count) bytes")
        #endif

        // If data is empty, try XML format instead
        if data.isEmpty {
            #if DEBUG
            print("📺 YouTubeTranscriptService: ERROR - Received empty data from transcript URL")
            print("📺 YouTubeTranscriptService: Trying XML format instead...")
            #endif

            return try await fetchTranscriptXML(baseUrl: baseUrl, language: language)
        }

        // Parse JSON response
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                #if DEBUG
                print("📺 YouTubeTranscriptService: Failed to parse transcript JSON as dictionary, trying XML format instead...")
                #endif

                // Try XML format instead
                return try await fetchTranscriptXML(baseUrl: baseUrl, language: language)
            }

            #if DEBUG
            // Debug: Check if events exists
            if json["events"] == nil {
                print("📺 YouTubeTranscriptService: ERROR - 'events' key not found in transcript JSON")
                print("📺 YouTubeTranscriptService: Available keys: \(json.keys.joined(separator: ", "))")
            }
            #endif

            guard let events = json["events"] as? [[String: Any]] else {
                #if DEBUG
                print("📺 YouTubeTranscriptService: Events not found in JSON, trying XML format instead...")
                #endif

                // Try XML format instead
                return try await fetchTranscriptXML(baseUrl: baseUrl, language: language)
            }

            #if DEBUG
            print("📺 YouTubeTranscriptService: Processing \(events.count) transcript events")
            #endif

            var formattedTranscript = ""

            for event in events {
                if let segs = event["segs"] as? [[String: Any]],
                   let startTime = event["tStartMs"] as? Int {

                    // Combine all segments in this event
                    let textParts = segs.compactMap { seg -> String? in
                        guard let text = seg["utf8"] as? String else { return nil }
                        return text.trimmingCharacters(in: .whitespacesAndNewlines)
                    }

                    if !textParts.isEmpty {
                        let combinedText = textParts.joined(separator: " ")

                        let seconds = startTime / 1000
                        let minutes = seconds / 60
                        let remainingSeconds = seconds % 60

                        formattedTranscript += String(format: "[%02d:%02d] %@\n", minutes, remainingSeconds, combinedText)
                    }
                }
            }

            if formattedTranscript.isEmpty {
                throw YouTubeTranscriptError.transcriptNotAvailable
            }

            #if DEBUG
            print("📺 YouTubeTranscriptService: Generated transcript of length: \(formattedTranscript.count)")
            print("📺 YouTubeTranscriptService: First 500 characters of transcript:")
            print(formattedTranscript.prefix(500))
            #endif

            return (formattedTranscript, language)
        } catch {
            #if DEBUG
            print("📺 YouTubeTranscriptService: Error parsing transcript JSON: \(error.localizedDescription)")
            #endif

            if let specificError = error as? YouTubeTranscriptError {
                throw specificError
            } else {
                throw YouTubeTranscriptError.jsonParsingError("Failed to parse transcript: \(error.localizedDescription)")
            }
        }
    }

    // Transcript list approach - first get available transcripts, then fetch the appropriate one
    private func fetchTranscriptFromList(videoId: String) async throws -> (transcript: String, language: String?) {
        #if DEBUG
        print("📺 YouTubeTranscriptService: Using transcript list approach")
        #endif

        // First, get the list of available transcripts
        let listUrl = "https://www.youtube.com/api/timedtext?type=list&v=\(videoId)"

        #if DEBUG
        print("📺 YouTubeTranscriptService: Transcript list URL: \(listUrl)")
        #endif

        var request = URLRequest(url: URL(string: listUrl)!)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw YouTubeTranscriptError.networkError("Failed to fetch transcript list")
        }

        if data.isEmpty {
            throw YouTubeTranscriptError.emptyData
        }

        #if DEBUG
        print("📺 YouTubeTranscriptService: Received transcript list data of size: \(data.count) bytes")
        #endif

        // Parse XML data to get available transcripts
        guard let xmlString = String(data: data, encoding: .utf8) else {
            throw YouTubeTranscriptError.parsingError("Failed to decode transcript list XML")
        }

        // Extract transcript tracks
        let trackPattern = "<track id=\"(\\d+)\" name=\"([^\"]*)\" lang_code=\"([^\"]*)\" lang_original=\"([^\"]*)\" lang_translated=\"([^\"]*)\" lang_default=\"([^\"]*)\"(.*?)/>"

        guard let trackRegex = try? NSRegularExpression(pattern: trackPattern, options: [.dotMatchesLineSeparators]) else {
            throw YouTubeTranscriptError.parsingError("Failed to create regex for transcript list")
        }

        let matches = trackRegex.matches(in: xmlString, range: NSRange(xmlString.startIndex..., in: xmlString))

        #if DEBUG
        print("📺 YouTubeTranscriptService: Found \(matches.count) transcript tracks in list")
        #endif

        if matches.isEmpty {
            throw YouTubeTranscriptError.transcriptNotAvailable
        }

        // Try to find English transcript first, then fall back to any available transcript
        var selectedLangCode = ""
        var selectedName = ""

        for match in matches {
            guard let langCodeRange = Range(match.range(at: 3), in: xmlString),
                  let nameRange = Range(match.range(at: 2), in: xmlString) else {
                continue
            }

            let langCode = String(xmlString[langCodeRange])
            let name = String(xmlString[nameRange])

            #if DEBUG
            print("📺 YouTubeTranscriptService: Found transcript: \(name) (\(langCode))")
            #endif

            // Prefer English
            if langCode == "en" {
                selectedLangCode = langCode
                selectedName = name
                break
            }

            // Otherwise take the first one
            if selectedLangCode.isEmpty {
                selectedLangCode = langCode
                selectedName = name
            }
        }

        if selectedLangCode.isEmpty {
            throw YouTubeTranscriptError.transcriptNotAvailable
        }

        #if DEBUG
        print("📺 YouTubeTranscriptService: Selected transcript: \(selectedName) (\(selectedLangCode))")
        #endif

        // Now fetch the selected transcript
        let transcriptUrl = "https://www.youtube.com/api/timedtext?lang=\(selectedLangCode)&v=\(videoId)&name=\(selectedName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"

        #if DEBUG
        print("📺 YouTubeTranscriptService: Fetching selected transcript URL: \(transcriptUrl)")
        #endif

        var transcriptRequest = URLRequest(url: URL(string: transcriptUrl)!)
        transcriptRequest.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

        let (transcriptData, transcriptResponse) = try await session.data(for: transcriptRequest)

        guard let transcriptHttpResponse = transcriptResponse as? HTTPURLResponse, transcriptHttpResponse.statusCode == 200 else {
            throw YouTubeTranscriptError.networkError("Failed to fetch selected transcript")
        }

        if transcriptData.isEmpty {
            throw YouTubeTranscriptError.emptyData
        }

        #if DEBUG
        print("📺 YouTubeTranscriptService: Received selected transcript data of size: \(transcriptData.count) bytes")
        #endif

        // Parse XML data
        guard let transcriptXmlString = String(data: transcriptData, encoding: .utf8) else {
            throw YouTubeTranscriptError.parsingError("Failed to decode selected transcript XML")
        }

        // Simple XML parsing for transcript
        var formattedTranscript = ""

        // Use regular expression to extract text and timestamps
        let textPattern = "<text start=\"([0-9\\.]+)\" dur=\"([0-9\\.]+)\">(.*?)</text>"

        do {
            let textRegex = try NSRegularExpression(pattern: textPattern, options: [.dotMatchesLineSeparators])
            let textMatches = textRegex.matches(in: transcriptXmlString, range: NSRange(transcriptXmlString.startIndex..., in: transcriptXmlString))

            #if DEBUG
            print("📺 YouTubeTranscriptService: Found \(textMatches.count) text segments in selected transcript")
            #endif

            for match in textMatches {
                guard let startRange = Range(match.range(at: 1), in: transcriptXmlString),
                      let textRange = Range(match.range(at: 3), in: transcriptXmlString) else {
                    continue
                }

                let startTimeString = String(transcriptXmlString[startRange])
                let text = String(transcriptXmlString[textRange])
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "&lt;", with: "<")
                    .replacingOccurrences(of: "&gt;", with: ">")
                    .replacingOccurrences(of: "&quot;", with: "\"")
                    .replacingOccurrences(of: "&#39;", with: "'")

                if let startTime = Double(startTimeString) {
                    let seconds = Int(startTime)
                    let minutes = seconds / 60
                    let remainingSeconds = seconds % 60

                    formattedTranscript += String(format: "[%02d:%02d] %@\n", minutes, remainingSeconds, text)
                }
            }

            if formattedTranscript.isEmpty {
                throw YouTubeTranscriptError.transcriptNotAvailable
            }

            #if DEBUG
            print("📺 YouTubeTranscriptService: Successfully parsed selected transcript")
            print("📺 YouTubeTranscriptService: First 500 characters of transcript:")
            print(formattedTranscript.prefix(500))
            #endif

            return (formattedTranscript, selectedLangCode)
        } catch {
            #if DEBUG
            print("📺 YouTubeTranscriptService: Error parsing selected transcript: \(error.localizedDescription)")
            #endif
            throw YouTubeTranscriptError.parsingError("Failed to parse selected transcript: \(error.localizedDescription)")
        }
    }

    // Alternative URL approach for fetching transcripts
    private func fetchTranscriptAlternativeURL(videoId: String) async throws -> (transcript: String, language: String?) {
        #if DEBUG
        print("📺 YouTubeTranscriptService: Using alternative URL approach")
        #endif

        // Try the alternative timedtext API format
        // This is a different endpoint that sometimes works when the standard one doesn't
        let alternativeUrl = "https://www.youtube.com/api/timedtext?lang=en&v=\(videoId)"

        #if DEBUG
        print("📺 YouTubeTranscriptService: Alternative URL: \(alternativeUrl)")
        #endif

        var request = URLRequest(url: URL(string: alternativeUrl)!)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw YouTubeTranscriptError.networkError("Failed to fetch transcript with alternative URL")
        }

        if data.isEmpty {
            throw YouTubeTranscriptError.emptyData
        }

        #if DEBUG
        print("📺 YouTubeTranscriptService: Received alternative data of size: \(data.count) bytes")
        #endif

        // Parse XML data
        guard let xmlString = String(data: data, encoding: .utf8) else {
            throw YouTubeTranscriptError.parsingError("Failed to decode XML data")
        }

        // Simple XML parsing for transcript
        var formattedTranscript = ""

        // Use regular expression to extract text and timestamps
        let pattern = "<text start=\"([0-9\\.]+)\" dur=\"([0-9\\.]+)\">(.*?)</text>"

        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
            let matches = regex.matches(in: xmlString, range: NSRange(xmlString.startIndex..., in: xmlString))

            #if DEBUG
            print("📺 YouTubeTranscriptService: Found \(matches.count) text segments in alternative XML")
            #endif

            for match in matches {
                guard let startRange = Range(match.range(at: 1), in: xmlString),
                      let textRange = Range(match.range(at: 3), in: xmlString) else {
                    continue
                }

                let startTimeString = String(xmlString[startRange])
                let text = String(xmlString[textRange])
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "&lt;", with: "<")
                    .replacingOccurrences(of: "&gt;", with: ">")
                    .replacingOccurrences(of: "&quot;", with: "\"")
                    .replacingOccurrences(of: "&#39;", with: "'")

                if let startTime = Double(startTimeString) {
                    let seconds = Int(startTime)
                    let minutes = seconds / 60
                    let remainingSeconds = seconds % 60

                    formattedTranscript += String(format: "[%02d:%02d] %@\n", minutes, remainingSeconds, text)
                }
            }

            if formattedTranscript.isEmpty {
                // If no text segments found, try another pattern for auto-generated captions
                let autoPattern = "<transcript>(.*?)</transcript>"
                if let autoRegex = try? NSRegularExpression(pattern: autoPattern, options: [.dotMatchesLineSeparators]),
                   let autoMatch = autoRegex.firstMatch(in: xmlString, range: NSRange(xmlString.startIndex..., in: xmlString)),
                   let autoRange = Range(autoMatch.range(at: 1), in: xmlString) {

                    let autoText = String(xmlString[autoRange])
                    formattedTranscript = "Auto-generated transcript:\n\n\(autoText)"
                } else {
                    throw YouTubeTranscriptError.transcriptNotAvailable
                }
            }

            #if DEBUG
            print("📺 YouTubeTranscriptService: Successfully parsed alternative transcript")
            print("📺 YouTubeTranscriptService: First 500 characters of transcript:")
            print(formattedTranscript.prefix(500))
            #endif

            return (formattedTranscript, "en") // Assume English for alternative URL
        } catch {
            #if DEBUG
            print("📺 YouTubeTranscriptService: Error parsing alternative XML: \(error.localizedDescription)")
            #endif
            throw YouTubeTranscriptError.parsingError("Failed to parse alternative transcript: \(error.localizedDescription)")
        }
    }

    // Browser simulation approach - use more browser-like headers and cookies
    private func fetchTranscriptWithBrowserSimulation(videoId: String) async throws -> (transcript: String, language: String?) {
        #if DEBUG
        print("📺 YouTubeTranscriptService: Using browser simulation approach")
        #endif

        // First, get the video page with browser-like headers
        let videoUrl = "https://www.youtube.com/watch?v=\(videoId)"
        var request = URLRequest(url: URL(string: videoUrl)!)

        // Add browser-like headers
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Referer")
        request.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")
        request.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")

        // Add some common cookies
        let cookieString = "CONSENT=YES+; VISITOR_INFO1_LIVE=somevalue; YSC=somevalue; PREF=f4=4000000&tz=America.NewYork"
        request.setValue(cookieString, forHTTPHeaderField: "Cookie")

        #if DEBUG
        print("📺 YouTubeTranscriptService: Fetching video page with browser simulation")
        #endif

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw YouTubeTranscriptError.networkError("Failed to fetch video page with browser simulation")
        }

        guard let htmlString = String(data: data, encoding: .utf8) else {
            throw YouTubeTranscriptError.invalidResponse
        }

        #if DEBUG
        print("📺 YouTubeTranscriptService: Received HTML response of length: \(htmlString.count)")
        #endif

        // Try to extract the transcript URL using a more specific pattern
        let pattern = "\"captionTracks\":\\[\\{.*?\"baseUrl\":\"(.*?)\".*?\"languageCode\":\"(.*?)\".*?\\}\\]"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            throw YouTubeTranscriptError.parsingError("Failed to create regex for browser simulation")
        }

        guard let match = regex.firstMatch(in: htmlString, range: NSRange(htmlString.startIndex..., in: htmlString)) else {
            throw YouTubeTranscriptError.transcriptNotAvailable
        }

        guard let baseUrlRange = Range(match.range(at: 1), in: htmlString),
              let languageCodeRange = Range(match.range(at: 2), in: htmlString) else {
            throw YouTubeTranscriptError.parsingError("Failed to extract caption URL")
        }

        var baseUrl = String(htmlString[baseUrlRange])
        let language = String(htmlString[languageCodeRange])

        // Unescape the URL
        baseUrl = baseUrl.replacingOccurrences(of: "\\u0026", with: "&")

        #if DEBUG
        print("📺 YouTubeTranscriptService: Browser simulation - Found caption URL")
        print("📺 YouTubeTranscriptService: Language: \(language)")
        #endif

        // Create a new request for the transcript with browser-like headers
        var transcriptRequest = URLRequest(url: URL(string: baseUrl)!)

        // Add browser-like headers
        transcriptRequest.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        transcriptRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        transcriptRequest.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        transcriptRequest.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        transcriptRequest.setValue("keep-alive", forHTTPHeaderField: "Connection")
        transcriptRequest.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        transcriptRequest.setValue("https://www.youtube.com/watch?v=\(videoId)", forHTTPHeaderField: "Referer")
        transcriptRequest.setValue(cookieString, forHTTPHeaderField: "Cookie")

        // Try to get the transcript in XML format first
        let xmlUrl = baseUrl.replacingOccurrences(of: "&fmt=json3", with: "")
        transcriptRequest.url = URL(string: xmlUrl)

        #if DEBUG
        print("📺 YouTubeTranscriptService: Fetching transcript with browser simulation: \(xmlUrl)")
        #endif

        let (transcriptData, transcriptResponse) = try await session.data(for: transcriptRequest)

        guard let transcriptHttpResponse = transcriptResponse as? HTTPURLResponse, transcriptHttpResponse.statusCode == 200 else {
            throw YouTubeTranscriptError.networkError("Failed to fetch transcript with browser simulation")
        }

        if transcriptData.isEmpty {
            throw YouTubeTranscriptError.emptyData
        }

        #if DEBUG
        print("📺 YouTubeTranscriptService: Received transcript data of size: \(transcriptData.count) bytes")
        #endif

        // Parse XML data
        guard let xmlString = String(data: transcriptData, encoding: .utf8) else {
            throw YouTubeTranscriptError.parsingError("Failed to decode XML data")
        }

        // Simple XML parsing for transcript
        var formattedTranscript = ""

        // Use regular expression to extract text and timestamps
        let textPattern = "<text start=\"([0-9\\.]+)\" dur=\"([0-9\\.]+)\">(.*?)</text>"

        do {
            let textRegex = try NSRegularExpression(pattern: textPattern, options: [.dotMatchesLineSeparators])
            let textMatches = textRegex.matches(in: xmlString, range: NSRange(xmlString.startIndex..., in: xmlString))

            #if DEBUG
            print("📺 YouTubeTranscriptService: Found \(textMatches.count) text segments in browser simulation")
            #endif

            for match in textMatches {
                guard let startRange = Range(match.range(at: 1), in: xmlString),
                      let textRange = Range(match.range(at: 3), in: xmlString) else {
                    continue
                }

                let startTimeString = String(xmlString[startRange])
                let text = String(xmlString[textRange])
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "&lt;", with: "<")
                    .replacingOccurrences(of: "&gt;", with: ">")
                    .replacingOccurrences(of: "&quot;", with: "\"")
                    .replacingOccurrences(of: "&#39;", with: "'")

                if let startTime = Double(startTimeString) {
                    let seconds = Int(startTime)
                    let minutes = seconds / 60
                    let remainingSeconds = seconds % 60

                    formattedTranscript += String(format: "[%02d:%02d] %@\n", minutes, remainingSeconds, text)
                }
            }

            if formattedTranscript.isEmpty {
                // If no text segments found, try to extract the raw transcript
                if xmlString.contains("<transcript>") {
                    let rawPattern = "<transcript>(.*?)</transcript>"
                    if let rawRegex = try? NSRegularExpression(pattern: rawPattern, options: [.dotMatchesLineSeparators]),
                       let rawMatch = rawRegex.firstMatch(in: xmlString, range: NSRange(xmlString.startIndex..., in: xmlString)),
                       let rawRange = Range(rawMatch.range(at: 1), in: xmlString) {

                        let rawText = String(xmlString[rawRange])
                        formattedTranscript = "Raw transcript:\n\n\(rawText)"
                    }
                }

                // If still empty, try to use the entire XML as a last resort
                if formattedTranscript.isEmpty {
                    formattedTranscript = "Transcript data (raw XML):\n\n\(xmlString)"
                }
            }

            #if DEBUG
            print("📺 YouTubeTranscriptService: Successfully parsed browser simulation transcript")
            print("📺 YouTubeTranscriptService: First 500 characters of transcript:")
            print(formattedTranscript.prefix(500))
            #endif

            return (formattedTranscript, language)
        } catch {
            #if DEBUG
            print("📺 YouTubeTranscriptService: Error parsing browser simulation transcript: \(error.localizedDescription)")
            #endif
            throw YouTubeTranscriptError.parsingError("Failed to parse browser simulation transcript: \(error.localizedDescription)")
        }
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
