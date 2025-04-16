import Foundation
import AIProxy

// MARK: - Audio Transcription Error
enum AudioTranscriptionError: LocalizedError {
    case fileNotFound
    case fileReadError(String)
    case transcriptionFailed(String)
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Audio file not found"
        case .fileReadError(let message):
            return "Failed to read audio file: \(message)"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .invalidResponse:
            return "Invalid response from transcription service"
        }
    }
}

// MARK: - Audio Transcription Service
final class AudioTranscriptionService {
    // MARK: - Properties
    private let openAIService: OpenAIService
    
    // Singleton instance
    static let shared = AudioTranscriptionService()
    
    // MARK: - Initialization
    init() {
        self.openAIService = AIProxy.openAIService(
            partialKey: "v2|feef4cd4|k3bJw_-iBG5958LZ",
            serviceURL: "https://api.aiproxy.pro/4b571ffb/5b899002"
        )
        
        #if DEBUG
        print("🎙️ AudioTranscriptionService: Initializing")
        #endif
    }
    
    // MARK: - Public Methods
    
    /// Transcribe an audio file
    /// - Parameters:
    ///   - fileURL: URL to the audio file
    ///   - language: Optional language code to guide transcription
    /// - Returns: Transcribed text
    func transcribeAudio(fileURL: URL, language: String? = nil) async throws -> String {
        #if DEBUG
        print("🎙️ AudioTranscriptionService: Transcribing audio file: \(fileURL.lastPathComponent)")
        #endif
        
        do {
            // Verify file exists
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw AudioTranscriptionError.fileNotFound
            }
            
            // Read file data
            let audioData: Data
            do {
                audioData = try Data(contentsOf: fileURL)
            } catch {
                throw AudioTranscriptionError.fileReadError(error.localizedDescription)
            }
            
            // Create transcription request
            let requestBody = OpenAICreateTranscriptionRequestBody(
                file: audioData,
                model: "whisper-1",
                language: language
            )
            
            // Send request
            let response = try await openAIService.createTranscriptionRequest(body: requestBody)
            
            // Check if we have a valid response
            let transcription = response.text
            if transcription.isEmpty {
                #if DEBUG
                print("🎙️ AudioTranscriptionService: Invalid transcription response - empty text")
                #endif
                throw AudioTranscriptionError.invalidResponse
            }
            
            #if DEBUG
            print("🎙️ AudioTranscriptionService: Successfully transcribed audio (\(transcription.count) characters)")
            #endif
            
            return transcription
            
        } catch let error as AudioTranscriptionError {
            throw error
        } catch let error as AIProxyError {
            throw AudioTranscriptionError.transcriptionFailed(error.localizedDescription)
        } catch {
            throw AudioTranscriptionError.transcriptionFailed(error.localizedDescription)
        }
    }
    
    /// Transcribe an audio file with word-level timestamps
    /// - Parameters:
    ///   - fileURL: URL to the audio file
    ///   - language: Optional language code to guide transcription
    /// - Returns: Transcribed text and segments with timestamps
    func transcribeAudioWithTimestamps(fileURL: URL, language: String? = nil) async throws -> (text: String, segments: [TranscriptSegment]) {
        #if DEBUG
        print("🎙️ AudioTranscriptionService: Transcribing audio with timestamps: \(fileURL.lastPathComponent)")
        #endif
        
        do {
            // Verify file exists
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw AudioTranscriptionError.fileNotFound
            }
            
            // Read file data
            let audioData: Data
            do {
                audioData = try Data(contentsOf: fileURL)
            } catch {
                throw AudioTranscriptionError.fileReadError(error.localizedDescription)
            }
            
            // Create transcription request with timestamp granularities
            let requestBody = OpenAICreateTranscriptionRequestBody(
                file: audioData,
                model: "whisper-1", 
                language: language,
                responseFormat: "verbose_json",
                timestampGranularities: [.segment]
            )
            
            // Send request
            let response = try await openAIService.createTranscriptionRequest(body: requestBody)
            
            // Check if we have a valid response
            let transcription = response.text
            if transcription.isEmpty {
                #if DEBUG
                print("🎙️ AudioTranscriptionService: Invalid transcription response - empty text")
                #endif
                throw AudioTranscriptionError.invalidResponse
            }
            
            // Extract segments
            var segments: [TranscriptSegment] = []
            
            if let responseSegments = response.segments {
                for segment in responseSegments {
                    let newSegment = TranscriptSegment(
                        text: segment.text,
                        startTime: segment.start,
                        endTime: segment.end,
                        isHighlighted: false
                    )
                    segments.append(newSegment)
                }
            }
            
            #if DEBUG
            print("🎙️ AudioTranscriptionService: Successfully transcribed audio with \(segments.count) segments")
            #endif
            
            return (text: transcription, segments: segments)
            
        } catch let error as AudioTranscriptionError {
            throw error
        } catch let error as AIProxyError {
            throw AudioTranscriptionError.transcriptionFailed(error.localizedDescription)
        } catch {
            throw AudioTranscriptionError.transcriptionFailed(error.localizedDescription)
        }
    }
}
