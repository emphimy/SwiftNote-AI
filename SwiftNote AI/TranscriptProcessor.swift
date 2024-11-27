import SwiftUI

// MARK: - Transcript Models
struct TranscriptEntry: Codable, Identifiable {
    let id = UUID()
    let text: String
    let start: TimeInterval
    let duration: TimeInterval
    var formattedTime: String {
        let minutes = Int(start) / 60
        let seconds = Int(start) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Transcript Processing Error
enum TranscriptProcessingError: LocalizedError {
    case invalidFormat
    case emptyTranscript
    case parsingError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid transcript format"
        case .emptyTranscript:
            return "Empty transcript data"
        case .parsingError(let message):
            return "Failed to parse transcript: \(message)"
        }
    }
}

// MARK: - Transcript Processor
final class TranscriptProcessor {
    // MARK: - Properties
    private let timeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()
    
    // MARK: - Processing Methods
    func processTranscript(_ rawTranscript: String) async throws -> [TranscriptEntry] {
        guard !rawTranscript.isEmpty else {
            #if DEBUG
            print("📝 TranscriptProcessor: Empty transcript received")
            #endif
            throw TranscriptProcessingError.emptyTranscript
        }
        
        #if DEBUG
        print("📝 TranscriptProcessor: Processing transcript of length: \(rawTranscript.count)")
        #endif
        
        return try await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { throw TranscriptProcessingError.parsingError("Processor deallocated") }
            
            let lines = rawTranscript.components(separatedBy: .newlines)
            var entries: [TranscriptEntry] = []
            var currentLine = ""
            var currentStart: TimeInterval = 0
            var currentDuration: TimeInterval = 0
            
            for line in lines {
                if line.contains("-->") {
                    // Time line
                    let times = try self.parseTimeLine(line)
                    currentStart = times.start
                    currentDuration = times.duration
                } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    // Text line
                    currentLine += line + " "
                } else if !currentLine.isEmpty {
                    // Empty line - end of entry
                    let entry = TranscriptEntry(
                        text: currentLine.trimmingCharacters(in: .whitespacesAndNewlines),
                        start: currentStart,
                        duration: currentDuration
                    )
                    entries.append(entry)
                    currentLine = ""
                }
            }
            
            // Add final entry if exists
            if !currentLine.isEmpty {
                entries.append(
                    TranscriptEntry(
                        text: currentLine.trimmingCharacters(in: .whitespacesAndNewlines),
                        start: currentStart,
                        duration: currentDuration
                    )
                )
            }
            
            #if DEBUG
            print("📝 TranscriptProcessor: Processed \(entries.count) transcript entries")
            #endif
            
            return entries
        }
        .value
    }
    
    // MARK: - Private Methods
    private func parseTimeLine(_ line: String) throws -> (start: TimeInterval, duration: TimeInterval) {
        let components = line.components(separatedBy: "-->")
        guard components.count == 2 else {
            #if DEBUG
            print("📝 TranscriptProcessor: Invalid time format - \(line)")
            #endif
            throw TranscriptProcessingError.invalidFormat
        }
        
        let startTime = try parseTimeString(components[0].trimmingCharacters(in: .whitespaces))
        let endTime = try parseTimeString(components[1].trimmingCharacters(in: .whitespaces))
        
        return (startTime, endTime - startTime)
    }
    
    private func parseTimeString(_ timeString: String) throws -> TimeInterval {
        let components = timeString.components(separatedBy: ":")
        guard components.count >= 2 else {
            #if DEBUG
            print("📝 TranscriptProcessor: Invalid time string format - \(timeString)")
            #endif
            throw TranscriptProcessingError.invalidFormat
        }
        
        var timeComponents: [Double] = []
        for component in components {
            guard let value = Double(component.replacingOccurrences(of: ",", with: ".")) else {
                #if DEBUG
                print("📝 TranscriptProcessor: Failed to parse time component - \(component)")
                #endif
                throw TranscriptProcessingError.parsingError("Invalid time value: \(component)")
            }
            timeComponents.append(value)
        }
        
        let seconds: Double
        switch timeComponents.count {
        case 2: // MM:SS
            seconds = timeComponents[0] * 60 + timeComponents[1]
        case 3: // HH:MM:SS
            seconds = timeComponents[0] * 3600 + timeComponents[1] * 60 + timeComponents[2]
        default:
            throw TranscriptProcessingError.invalidFormat
        }
        
        return seconds
    }
    
    // MARK: - Formatting Methods
    func formatTranscriptForDisplay(_ entries: [TranscriptEntry]) -> String {
        entries.map { "\($0.formattedTime): \($0.text)" }.joined(separator: "\n\n")
    }
    
    func searchTranscript(_ entries: [TranscriptEntry], query: String) -> [TranscriptEntry] {
        guard !query.isEmpty else { return entries }
        
        #if DEBUG
        print("📝 TranscriptProcessor: Searching transcript for: \(query)")
        #endif
        
        return entries.filter { entry in
            entry.text.localizedCaseInsensitiveContains(query)
        }
    }
}
