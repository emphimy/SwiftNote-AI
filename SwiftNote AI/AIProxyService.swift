import AIProxy
import SwiftUI


// MARK: - AI Proxy Service
final class AIProxyService {
    private let endpoint = "https://your-proxy-endpoint/api/v1/chat/completions"
    private let session: URLSession
    
    init(session: URLSession = .shared) {
        self.session = session
        
        #if DEBUG
        print("🤖 AIProxyService: Initializing")
        #endif
    }
    
    func generateCompletion(prompt: String) async throws -> String {
        #if DEBUG
        print("🤖 AIProxyService: Generating completion for prompt length: \(prompt.count)")
        #endif
        
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "prompt": prompt,
            "max_tokens": 2000,
            "temperature": 0.7
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NoteGenerationError.invalidResponse
            }
            
            #if DEBUG
            print("🤖 AIProxyService: Response status code: \(httpResponse.statusCode)")
            #endif
            
            if httpResponse.statusCode != 200 {
                throw NoteGenerationError.apiError("Server returned status code: \(httpResponse.statusCode)")
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = json["content"] as? String else {
                throw NoteGenerationError.invalidResponse
            }
            
            return content
            
        } catch {
            #if DEBUG
            print("🤖 AIProxyService: Request failed - \(error)")
            #endif
            throw NoteGenerationError.apiError(error.localizedDescription)
        }
    }
}
