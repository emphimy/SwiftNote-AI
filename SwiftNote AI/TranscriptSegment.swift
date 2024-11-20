import Foundation

struct TranscriptSegment: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    var isHighlighted: Bool
    
    init(id: UUID = UUID(), text: String, startTime: TimeInterval, endTime: TimeInterval, isHighlighted: Bool = false) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.isHighlighted = isHighlighted
    }
}
