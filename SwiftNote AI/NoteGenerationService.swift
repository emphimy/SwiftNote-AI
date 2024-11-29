import Foundation

// MARK: - Note Generation Error
enum NoteGenerationError: LocalizedError {
    case invalidAPIKey
    case apiError(String)
    case invalidResponse
    case emptyTranscript
    
    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Invalid OpenAI API key"
        case .apiError(let message):
            return "API Error: \(message)"
        case .invalidResponse:
            return "Invalid response from OpenAI"
        case .emptyTranscript:
            return "Empty transcript provided"
        }
    }
}

// MARK: - Note Generation Service
actor NoteGenerationService {
    private let apiKey: String
    private let endpoint = "https://api.openai.com/v1/chat/completions"
    
    init() throws {
        #if DEBUG
        print("🤖 NoteGeneration: Initializing service")
        #endif
        
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "OpenAIAPIKey") as? String else {
            #if DEBUG
            print("🤖 NoteGeneration: Failed to retrieve API key from Info.plist")
            #endif
            throw NoteGenerationError.invalidAPIKey
        }
        
        guard !apiKey.isEmpty else {
            #if DEBUG
            print("🤖 NoteGeneration: API key is empty")
            #endif
            throw NoteGenerationError.invalidAPIKey
        }
        
        #if DEBUG
        print("🤖 NoteGeneration: Successfully retrieved API key")
        print("🤖 NoteGeneration: API key length: \(apiKey.count)")
        print("🤖 NoteGeneration: First 10 chars: \(String(apiKey.prefix(10)))...")
        #endif
        
        self.apiKey = apiKey
    }
    
    func generateNote(from transcript: String) async throws -> String {
        guard !transcript.isEmpty else {
            throw NoteGenerationError.emptyTranscript
        }
        
        #if DEBUG
        print("🤖 NoteGenerationService: Generating note from transcript of length: \(transcript.count)")
        #endif
        
        let prompt = """
        Please analyze this transcript and create a well-structured note with the following sections:
        1. Summary (2-3 sentences)
        2. Key Points (bullet points)
        3. Important Details (organized by topics)
        4. Notable Quotes (if any)
        
        Use Markdown formatting for better readability.
        
        Transcript:
        \(transcript)
        """
        
        return try await makeRequest(prompt: prompt)
    }
    
    func generateTitle(from transcript: String) async throws -> String {
        guard !transcript.isEmpty else {
            throw NoteGenerationError.emptyTranscript
        }
        
        let prompt = """
        Based on this transcript, generate a concise but descriptive title (maximum 60 characters) that captures the main topic or theme.
        The title should be clear and informative, avoiding generic phrases.
        
        Transcript:
        \(transcript)
        
        Generate only the title, nothing else.
        """
        
        let response = try await makeRequest(prompt: prompt)
        // Clean up the response to ensure it's just the title
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Update makeRequest function
    private func makeRequest(prompt: String) async throws -> String {
        guard !prompt.isEmpty else {
            #if DEBUG
            print("🤖 NoteGeneration: Empty prompt provided")
            #endif
            throw NoteGenerationError.apiError("Empty prompt provided")
        }

        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                ["role": "system", "content": "You are a helpful assistant that creates well-structured notes from transcripts. Create comprehensive, well-organized notes with sections for Summary, Key Points, Important Details, and Notable Quotes."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
            "max_tokens": 2000
        ]
        
        guard let url = URL(string: endpoint) else {
            #if DEBUG
            print("🤖 NoteGeneration: Invalid endpoint URL")
            #endif
            throw NoteGenerationError.invalidAPIKey
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
            request.httpBody = jsonData
            
            #if DEBUG
            print("🤖 NoteGeneration: Request body:")
            if let requestString = String(data: jsonData, encoding: .utf8) {
                print(requestString)
            }
            #endif
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                #if DEBUG
                print("🤖 NoteGeneration: Invalid response type")
                #endif
                throw NoteGenerationError.invalidResponse
            }
            
            #if DEBUG
            print("🤖 NoteGeneration: Response status code: \(httpResponse.statusCode)")
            print("🤖 NoteGeneration: Response headers: \(httpResponse.allHeaderFields)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("🤖 NoteGeneration: Response body: \(responseString)")
            }
            #endif
            
            if httpResponse.statusCode == 400 {
                // Parse error message from response
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    #if DEBUG
                    print("🤖 NoteGeneration: API error message: \(message)")
                    #endif
                    throw NoteGenerationError.apiError(message)
                }
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                #if DEBUG
                print("🤖 NoteGeneration: Error status code: \(httpResponse.statusCode)")
                #endif
                throw NoteGenerationError.apiError("Server returned status code: \(httpResponse.statusCode)")
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw NoteGenerationError.invalidResponse
            }

            return content
        } catch {
            #if DEBUG
            print("🤖 NoteGeneration: Request failed with error: \(error)")
            #endif
            throw NoteGenerationError.apiError(error.localizedDescription)
        }
    }
}
