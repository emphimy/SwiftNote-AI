import Foundation

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

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case color
        case timestamp
        case sortOrder = "sort_order"
        case userId = "user_id"
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
