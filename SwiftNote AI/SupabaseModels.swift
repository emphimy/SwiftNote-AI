import Foundation

// MARK: - Data Extensions for Hex Decoding
extension Data {
    /// Initialize Data from a hex string
    init?(hexString: String) {
        let cleanHexString = hexString.replacingOccurrences(of: " ", with: "")
        guard cleanHexString.count % 2 == 0 else { return nil }

        var data = Data()
        var index = cleanHexString.startIndex

        while index < cleanHexString.endIndex {
            let nextIndex = cleanHexString.index(index, offsetBy: 2)
            let byteString = String(cleanHexString[index..<nextIndex])

            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            data.append(byte)

            index = nextIndex
        }

        self = data
    }
}

// MARK: - Supabase Models
// These models represent the database schema in Supabase

// MARK: - Note Model
struct SupabaseNote: Codable, Identifiable {
    let id: UUID
    var title: String
    var originalContent: Data?
    var aiGeneratedContent: Data?
    var sourceType: String
    var timestamp: Date
    var lastModified: Date
    var isFavorite: Bool
    var processingStatus: String
    var folderId: UUID?
    var userId: UUID

    // Optional fields
    var summary: String?
    var keyPoints: String?
    var citations: String?
    var duration: Double?
    var languageCode: String?

    // Added fields to match CoreData model
    var sourceURL: String?
    var tags: String?
    var transcript: String?
    var sections: Data?
    var supplementaryMaterials: Data?
    var mindMap: Data?
    var videoId: String?

    // Sync fields
    var syncStatus: String?
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case originalContent = "original_content"
        case aiGeneratedContent = "ai_generated_content"
        case sourceType = "source_type"
        case timestamp
        case lastModified = "last_modified"
        case isFavorite = "is_favorite"
        case processingStatus = "processing_status"
        case folderId = "folder_id"
        case userId = "user_id"
        case summary
        case keyPoints = "key_points"
        case citations
        case duration
        case languageCode = "language_code"
        case sourceURL = "source_url"
        case tags
        case transcript
        case sections
        case supplementaryMaterials = "supplementary_materials"
        case mindMap = "mind_map"
        case videoId = "video_id"
        case syncStatus = "sync_status"
        case deletedAt = "deleted_at"
    }

    // Regular initializer for manual creation
    init(
        id: UUID,
        title: String,
        originalContent: Data? = nil,
        aiGeneratedContent: Data? = nil,
        sourceType: String,
        timestamp: Date,
        lastModified: Date,
        isFavorite: Bool,
        processingStatus: String,
        folderId: UUID? = nil,
        userId: UUID,
        summary: String? = nil,
        keyPoints: String? = nil,
        citations: String? = nil,
        duration: Double? = nil,
        languageCode: String? = nil,
        sourceURL: String? = nil,
        tags: String? = nil,
        transcript: String? = nil,
        sections: Data? = nil,
        supplementaryMaterials: Data? = nil,
        mindMap: Data? = nil,
        videoId: String? = nil,
        syncStatus: String? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.originalContent = originalContent
        self.aiGeneratedContent = aiGeneratedContent
        self.sourceType = sourceType
        self.timestamp = timestamp
        self.lastModified = lastModified
        self.isFavorite = isFavorite
        self.processingStatus = processingStatus
        self.folderId = folderId
        self.userId = userId
        self.summary = summary
        self.keyPoints = keyPoints
        self.citations = citations
        self.duration = duration
        self.languageCode = languageCode
        self.sourceURL = sourceURL
        self.tags = tags
        self.transcript = transcript
        self.sections = sections
        self.supplementaryMaterials = supplementaryMaterials
        self.mindMap = mindMap
        self.videoId = videoId
        self.syncStatus = syncStatus
        self.deletedAt = deletedAt
    }

    // Custom initializer for decoding - handles Base64 conversion from Supabase bytea fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode regular fields
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        sourceType = try container.decode(String.self, forKey: .sourceType)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        lastModified = try container.decode(Date.self, forKey: .lastModified)
        isFavorite = try container.decode(Bool.self, forKey: .isFavorite)
        processingStatus = try container.decode(String.self, forKey: .processingStatus)
        userId = try container.decode(UUID.self, forKey: .userId)

        // Decode optional fields
        folderId = try container.decodeIfPresent(UUID.self, forKey: .folderId)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        keyPoints = try container.decodeIfPresent(String.self, forKey: .keyPoints)
        citations = try container.decodeIfPresent(String.self, forKey: .citations)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        languageCode = try container.decodeIfPresent(String.self, forKey: .languageCode)
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
        tags = try container.decodeIfPresent(String.self, forKey: .tags)
        transcript = try container.decodeIfPresent(String.self, forKey: .transcript)
        videoId = try container.decodeIfPresent(String.self, forKey: .videoId)
        syncStatus = try container.decodeIfPresent(String.self, forKey: .syncStatus)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)

        // Decode binary fields - Supabase sends bytea as Base64 strings
        originalContent = try Self.decodeBase64Data(from: container, forKey: .originalContent)
        aiGeneratedContent = try Self.decodeBase64Data(from: container, forKey: .aiGeneratedContent)
        sections = try Self.decodeBase64Data(from: container, forKey: .sections)
        supplementaryMaterials = try Self.decodeBase64Data(from: container, forKey: .supplementaryMaterials)
        mindMap = try Self.decodeBase64Data(from: container, forKey: .mindMap)
    }

    // Custom encoder - converts Data to Base64 for Supabase bytea fields
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        // Encode regular fields
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(sourceType, forKey: .sourceType)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(lastModified, forKey: .lastModified)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(processingStatus, forKey: .processingStatus)
        try container.encode(userId, forKey: .userId)

        // Encode optional fields
        try container.encodeIfPresent(folderId, forKey: .folderId)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encodeIfPresent(keyPoints, forKey: .keyPoints)
        try container.encodeIfPresent(citations, forKey: .citations)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(languageCode, forKey: .languageCode)
        try container.encodeIfPresent(sourceURL, forKey: .sourceURL)
        try container.encodeIfPresent(tags, forKey: .tags)
        try container.encodeIfPresent(transcript, forKey: .transcript)
        try container.encodeIfPresent(videoId, forKey: .videoId)
        try container.encodeIfPresent(syncStatus, forKey: .syncStatus)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)

        // Encode binary fields as Base64 for Supabase bytea fields
        try Self.encodeBase64Data(originalContent, to: &container, forKey: .originalContent)
        try Self.encodeBase64Data(aiGeneratedContent, to: &container, forKey: .aiGeneratedContent)
        try Self.encodeBase64Data(sections, to: &container, forKey: .sections)
        try Self.encodeBase64Data(supplementaryMaterials, to: &container, forKey: .supplementaryMaterials)
        try Self.encodeBase64Data(mindMap, to: &container, forKey: .mindMap)
    }

    // Helper structure to decode Buffer objects from Supabase
    private struct BufferObject: Codable {
        let type: String
        let data: [UInt8]
    }

    // Helper method to decode binary data from Supabase (handles multiple data formats)
    private static func decodeBase64Data(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Data? {
        // Try to decode as a Buffer object first (Node.js format from Supabase)
        if let bufferObject = try? container.decodeIfPresent(BufferObject.self, forKey: key),
           bufferObject.type == "Buffer" {
            return Data(bufferObject.data)
        }

        // Try to decode as string format (Base64 or hex-encoded)
        if let dataString = try container.decodeIfPresent(String.self, forKey: key) {
            // Try to decode as Base64 first
            if let data = Data(base64Encoded: dataString) {
                return data
            }

            // Try to decode as hex-encoded string (PostgreSQL bytea format)
            if dataString.hasPrefix("\\x") {
                let hexString = String(dataString.dropFirst(2)) // Remove \x prefix
                if let hexData = Data(hexString: hexString) {
                    // Check if the hex-decoded data is actually Base64 encoded content
                    if let hexDecodedString = String(data: hexData, encoding: .utf8),
                       let finalData = Data(base64Encoded: hexDecodedString) {
                        return finalData
                    } else {
                        return hexData
                    }
                }
            }

            // Fallback: treat as UTF-8 data
            return Data(dataString.utf8)
        }

        return nil
    }

    // Helper method to encode Data as Base64 string
    private static func encodeBase64Data(_ data: Data?, to container: inout KeyedEncodingContainer<CodingKeys>, forKey key: CodingKeys) throws {
        if let data = data {
            let base64String = data.base64EncodedString()
            try container.encode(base64String, forKey: key)
        } else {
            try container.encodeNil(forKey: key)
        }
    }
}

// MARK: - Folder Model
struct SupabaseFolder: Codable, Identifiable {
    let id: UUID
    var name: String
    var color: String
    var timestamp: Date
    var sortOrder: Int32
    var userId: UUID

    // Sync fields
    var updatedAt: Date?
    var syncStatus: String?
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case color
        case timestamp
        case sortOrder = "sort_order"
        case userId = "user_id"
        case updatedAt = "updated_at"
        case syncStatus = "sync_status"
        case deletedAt = "deleted_at"
    }
}

// MARK: - Quiz Analytics Model
struct SupabaseQuizAnalytics: Codable, Identifiable {
    let id: UUID
    var noteId: UUID
    var averageScore: Double
    var completedQuizzes: Int32
    var correctAnswers: Int32
    var totalQuestions: Int32
    var topicPerformance: Data?
    var userId: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case noteId = "note_id"
        case averageScore = "average_score"
        case completedQuizzes = "completed_quizzes"
        case correctAnswers = "correct_answers"
        case totalQuestions = "total_questions"
        case topicPerformance = "topic_performance"
        case userId = "user_id"
    }
}

// MARK: - Quiz Progress Model
struct SupabaseQuizProgress: Codable, Identifiable {
    let id: UUID
    var noteId: UUID
    var quizType: String
    var score: Double
    var completedAt: Date
    var userId: UUID
    var answers: Data?

    enum CodingKeys: String, CodingKey {
        case id
        case noteId = "note_id"
        case quizType = "quiz_type"
        case score
        case completedAt = "completed_at"
        case userId = "user_id"
        case answers
    }
}

// MARK: - User Settings Model
struct SupabaseUserSettings: Codable, Identifiable {
    let id: UUID
    var analyticsEnabled: Bool
    var biometricEnabled: Bool
    var theme: String
    var lastSync: Date?
    var userId: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case analyticsEnabled = "analytics_enabled"
        case biometricEnabled = "biometric_enabled"
        case theme
        case lastSync = "last_sync"
        case userId = "user_id"
    }
}

// MARK: - User Profile Model
struct SupabaseUserProfile: Codable, Identifiable {
    let id: UUID
    var email: String
    var fullName: String?
    var avatarUrl: String?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case fullName = "full_name"
        case avatarUrl = "avatar_url"
        case createdAt = "created_at"
    }
}
