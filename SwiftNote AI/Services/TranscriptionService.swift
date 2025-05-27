import Foundation
import Speech
import AVFoundation

// MARK: - Transcript Service Protocol
protocol TranscriptionServiceProtocol {
    func transcribe(audioURL: URL) async throws -> [TranscriptSegment]
    func exportTranscript(_ segments: [TranscriptSegment], format: TranscriptExportFormat) throws -> Data
    func searchTranscript(_ segments: [TranscriptSegment], query: String) -> [TranscriptSearchResult]
    func updateSegment(_ segment: TranscriptSegment, newText: String) throws -> TranscriptSegment
}

// MARK: - Transcript Models
enum TranscriptExportFormat {
    case txt, srt, json
    
    var contentType: String {
        switch self {
        case .txt: return "text/plain"
        case .srt: return "text/srt"
        case .json: return "application/json"
        }
    }
    
    var fileExtension: String {
        switch self {
        case .txt: return "txt"
        case .srt: return "srt"
        case .json: return "json"
        }
    }
}

struct TranscriptSearchResult: Identifiable {
    let id = UUID()
    let segment: TranscriptSegment
    let range: Range<String.Index>
}

// MARK: - Live Transcription Service
final class LiveTranscriptionService: TranscriptionServiceProtocol {
    private let speechRecognizer: SFSpeechRecognizer
    private let audioEngine: AVAudioEngine
    private var recognitionTask: SFSpeechRecognitionTask?
    private let queue = DispatchQueue(label: "com.app.transcription")
    
    init() {
        self.speechRecognizer = SFSpeechRecognizer(locale: .current)!
        self.audioEngine = AVAudioEngine()
        
        #if DEBUG
        print("🎤 TranscriptionService: Initializing with locale: \(String(describing: speechRecognizer.locale))")
        #endif
    }
    
    func transcribe(audioURL: URL) async throws -> [TranscriptSegment] {
        #if DEBUG
        print("🎤 TranscriptionService: Starting transcription for URL: \(audioURL)")
        #endif
        
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            #if DEBUG
            print("🎤 TranscriptionService: Speech recognizer unavailable")
            #endif
            throw TranscriptionError.recognizerUnavailable
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    #if DEBUG
                    print("🎤 TranscriptionService: Recognition error - \(error)")
                    #endif
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let result = result else { return }
                
                if result.isFinal {
                    let segments = result.bestTranscription.segments.map { segment in
                        TranscriptSegment(
                            text: segment.substring,
                            startTime: segment.timestamp,
                            endTime: segment.timestamp + segment.duration
                        )
                    }
                    
                    #if DEBUG
                    print("🎤 TranscriptionService: Transcription completed with \(segments.count) segments")
                    #endif
                    
                    continuation.resume(returning: segments)
                }
            }
        }
    }
    
    func exportTranscript(_ segments: [TranscriptSegment], format: TranscriptExportFormat) throws -> Data {
        #if DEBUG
        print("🎤 TranscriptionService: Exporting transcript in format: \(format)")
        #endif
        
        switch format {
        case .txt:
            let text = segments.map { $0.text }.joined(separator: "\n\n")
            guard let data = text.data(using: .utf8) else {
                throw TranscriptionError.exportFailed
            }
            return data
            
        case .srt:
            var srtContent = ""
            for (index, segment) in segments.enumerated() {
                srtContent += "\(index + 1)\n"
                srtContent += "\(formatTimestamp(segment.startTime)) --> \(formatTimestamp(segment.endTime))\n"
                srtContent += "\(segment.text)\n\n"
            }
            guard let data = srtContent.data(using: .utf8) else {
                throw TranscriptionError.exportFailed
            }
            return data
            
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            return try encoder.encode(segments)
        }
    }
    
    func searchTranscript(_ segments: [TranscriptSegment], query: String) -> [TranscriptSearchResult] {
        #if DEBUG
        print("🎤 TranscriptionService: Searching transcript for query: \(query)")
        #endif
        
        return segments.compactMap { segment in
            guard let range = segment.text.range(
                of: query,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) else { return nil }
            
            return TranscriptSearchResult(segment: segment, range: range)
        }
    }
    
    func updateSegment(_ segment: TranscriptSegment, newText: String) throws -> TranscriptSegment {
        #if DEBUG
        print("🎤 TranscriptionService: Updating segment text from '\(segment.text)' to '\(newText)'")
        #endif
        
        guard !newText.isEmpty else {
            throw TranscriptionError.invalidText
        }
        
        return TranscriptSegment(
            text: newText,
            startTime: segment.startTime,
            endTime: segment.endTime
        )
    }
    
    // MARK: - Helper Methods
    private func formatTimestamp(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 1000)
        
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
    }
}

// MARK: - Transcription Errors
enum TranscriptionError: LocalizedError {
    case recognizerUnavailable
    case exportFailed
    case invalidText
    case unauthorized
    
    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognition is not available on this device"
        case .exportFailed:
            return "Failed to export transcript"
        case .invalidText:
            return "Invalid text provided"
        case .unauthorized:
            return "Speech recognition not authorized"
        }
    }
}
