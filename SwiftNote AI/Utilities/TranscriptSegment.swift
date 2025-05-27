import Foundation

struct TranscriptSegment: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    var isHighlighted: Bool
    // Add new property for YouTube
    let videoId: String?
    
    init(id: UUID = UUID(), text: String, startTime: TimeInterval, endTime: TimeInterval, isHighlighted: Bool = false, videoId: String? = nil) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.isHighlighted = isHighlighted
        self.videoId = videoId
    }
}
