//
//  SyncDataModels.swift
//  SwiftNote AI
//
//  Created by Augment Agent on 1/27/25.
//  Extracted from SupabaseSyncService.swift for better code organization
//

import Foundation

// MARK: - Sync Progress Tracking

/// Sync progress information
struct SyncProgress {
    var totalNotes: Int = 0
    var syncedNotes: Int = 0
    var totalFolders: Int = 0
    var syncedFolders: Int = 0
    var downloadedNotes: Int = 0
    var downloadedFolders: Int = 0
    var resolvedConflicts: Int = 0
    var currentStatus: String = "Preparing..."
    var includeBinaryData: Bool = false
    var isDownloadPhase: Bool = false
    var isTwoWaySync: Bool = false

    var folderProgress: Double {
        if isTwoWaySync {
            let uploadProgress = totalFolders > 0 ? Double(syncedFolders) / Double(totalFolders) : 0
            let downloadProgress = totalFolders > 0 ? Double(downloadedFolders) / Double(totalFolders) : 0
            return (uploadProgress + downloadProgress) / 2.0
        } else {
            return totalFolders > 0 ? Double(syncedFolders) / Double(totalFolders) : 0
        }
    }

    var noteProgress: Double {
        if isTwoWaySync {
            let uploadProgress = totalNotes > 0 ? Double(syncedNotes) / Double(totalNotes) : 0
            let downloadProgress = totalNotes > 0 ? Double(downloadedNotes) / Double(totalNotes) : 0
            return (uploadProgress + downloadProgress) / 2.0
        } else {
            return totalNotes > 0 ? Double(syncedNotes) / Double(totalNotes) : 0
        }
    }

    var overallProgress: Double {
        // Weight folders as 30% and notes as 70% of overall progress
        return (folderProgress * 0.3) + (noteProgress * 0.7)
    }
}

// MARK: - Thread-Safe Counter

/// Actor-isolated counter for thread-safe progress tracking
actor SuccessCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func getCount() -> Int {
        return count
    }

    func reset() {
        count = 0
    }
}

// MARK: - Simplified Sync Models

/// A simplified version of SupabaseFolder with only the metadata fields
/// This helps avoid encoding/decoding issues with complex fields
struct SimpleSupabaseFolder: Codable {
    let id: UUID
    let name: String
    let color: String
    let timestamp: Date
    let sortOrder: Int32
    let userId: UUID
    let updatedAt: Date?
    let syncStatus: String?
    let deletedAt: Date?

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

/// A simplified version of SupabaseNote with only the metadata fields
/// This helps avoid encoding/decoding issues with complex fields
struct SimpleSupabaseNote: Codable {
    let id: UUID
    let title: String
    let sourceType: String
    let timestamp: Date
    let lastModified: Date
    let isFavorite: Bool
    let processingStatus: String
    let userId: UUID
    let folderId: UUID?
    // Note: CoreData Note doesn't have a summary field
    let keyPoints: String?
    let citations: String?
    let duration: Double?
    let languageCode: String?  // Maps to transcriptLanguage in CoreData
    let sourceURL: String?
    let tags: String?
    let transcript: String?
    let videoId: String?
    let syncStatus: String?
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case sourceType = "source_type"
        case timestamp
        case lastModified = "last_modified"
        case isFavorite = "is_favorite"
        case processingStatus = "processing_status"
        case userId = "user_id"
        case folderId = "folder_id"
        case keyPoints = "key_points"
        case citations
        case duration
        case languageCode = "language_code"
        case sourceURL = "source_url"
        case tags
        case transcript
        case videoId = "video_id"
        case syncStatus = "sync_status"
        case deletedAt = "deleted_at"
    }

    // Custom initializer
    init(
        id: UUID,
        title: String,
        sourceType: String,
        timestamp: Date,
        lastModified: Date,
        isFavorite: Bool,
        processingStatus: String,
        userId: UUID,
        folderId: UUID?,
        keyPoints: String?,
        citations: String?,
        duration: Double?,
        languageCode: String?,
        sourceURL: String?,
        tags: String?,
        transcript: String?,
        videoId: String?,
        syncStatus: String?,
        deletedAt: Date?
    ) {
        self.id = id
        self.title = title
        self.sourceType = sourceType
        self.timestamp = timestamp
        self.lastModified = lastModified
        self.isFavorite = isFavorite
        self.processingStatus = processingStatus
        self.userId = userId
        self.folderId = folderId
        self.keyPoints = keyPoints
        self.citations = citations
        self.duration = duration
        self.languageCode = languageCode
        self.sourceURL = sourceURL
        self.tags = tags
        self.transcript = transcript
        self.videoId = videoId
        self.syncStatus = syncStatus
        self.deletedAt = deletedAt
    }
}

/// An enhanced version of SupabaseNote that includes Base64-encoded binary data
/// This allows us to sync binary content while avoiding encoding/decoding issues
struct EnhancedSupabaseNote: Codable {
    // Include all fields from SimpleSupabaseNote
    let id: UUID
    let title: String
    let sourceType: String
    let timestamp: Date
    let lastModified: Date
    let isFavorite: Bool
    let processingStatus: String
    let userId: UUID
    let folderId: UUID?
    let keyPoints: String?
    let citations: String?
    let duration: Double?
    let languageCode: String?
    let sourceURL: String?
    let tags: String?
    let transcript: String?
    let videoId: String?
    let syncStatus: String?
    let deletedAt: Date?

    // Additional binary data fields (Base64-encoded)
    let originalContentBase64: String?
    let aiGeneratedContentBase64: String?
    let sectionsBase64: String?
    let mindMapBase64: String?
    let supplementaryMaterialsBase64: String?

    // Size tracking fields
    let originalContentSize: Double?
    let aiGeneratedContentSize: Double?
    let sectionsSize: Double?
    let mindMapSize: Double?
    let supplementaryMaterialsSize: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case sourceType = "source_type"
        case timestamp
        case lastModified = "last_modified"
        case isFavorite = "is_favorite"
        case processingStatus = "processing_status"
        case userId = "user_id"
        case folderId = "folder_id"
        case keyPoints = "key_points"
        case citations
        case duration
        case languageCode = "language_code"
        case sourceURL = "source_url"
        case tags
        case transcript
        case videoId = "video_id"
        case syncStatus = "sync_status"
        case originalContentBase64 = "original_content"
        case aiGeneratedContentBase64 = "ai_generated_content"
        case sectionsBase64 = "sections"
        case mindMapBase64 = "mind_map"
        case supplementaryMaterialsBase64 = "supplementary_materials"

        // Size metadata fields and deletedAt are intentionally excluded from CodingKeys
        // so they won't be sent to Supabase, as they don't exist in the schema
    }

    // Custom initializer for decoding
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
        keyPoints = try container.decodeIfPresent(String.self, forKey: .keyPoints)
        citations = try container.decodeIfPresent(String.self, forKey: .citations)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        languageCode = try container.decodeIfPresent(String.self, forKey: .languageCode)
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
        tags = try container.decodeIfPresent(String.self, forKey: .tags)
        transcript = try container.decodeIfPresent(String.self, forKey: .transcript)
        videoId = try container.decodeIfPresent(String.self, forKey: .videoId)
        syncStatus = try container.decodeIfPresent(String.self, forKey: .syncStatus)

        // Decode binary data fields
        originalContentBase64 = try container.decodeIfPresent(String.self, forKey: .originalContentBase64)
        aiGeneratedContentBase64 = try container.decodeIfPresent(String.self, forKey: .aiGeneratedContentBase64)
        sectionsBase64 = try container.decodeIfPresent(String.self, forKey: .sectionsBase64)
        mindMapBase64 = try container.decodeIfPresent(String.self, forKey: .mindMapBase64)
        supplementaryMaterialsBase64 = try container.decodeIfPresent(String.self, forKey: .supplementaryMaterialsBase64)

        // Initialize fields excluded from CodingKeys to nil since they're not in the JSON
        deletedAt = nil
        originalContentSize = nil
        aiGeneratedContentSize = nil
        sectionsSize = nil
        mindMapSize = nil
        supplementaryMaterialsSize = nil
    }

    // Custom initializer for creating from code
    init(
        id: UUID,
        title: String,
        sourceType: String,
        timestamp: Date,
        lastModified: Date,
        isFavorite: Bool,
        processingStatus: String,
        userId: UUID,
        folderId: UUID?,
        keyPoints: String?,
        citations: String?,
        duration: Double?,
        languageCode: String?,
        sourceURL: String?,
        tags: String?,
        transcript: String?,
        videoId: String?,
        syncStatus: String?,
        originalContentBase64: String?,
        aiGeneratedContentBase64: String?,
        sectionsBase64: String?,
        mindMapBase64: String?,
        supplementaryMaterialsBase64: String?,
        originalContentSize: Double?,
        aiGeneratedContentSize: Double?,
        sectionsSize: Double?,
        mindMapSize: Double?,
        supplementaryMaterialsSize: Double?
    ) {
        self.id = id
        self.title = title
        self.sourceType = sourceType
        self.timestamp = timestamp
        self.lastModified = lastModified
        self.isFavorite = isFavorite
        self.processingStatus = processingStatus
        self.userId = userId
        self.folderId = folderId
        self.keyPoints = keyPoints
        self.citations = citations
        self.duration = duration
        self.languageCode = languageCode
        self.sourceURL = sourceURL
        self.tags = tags
        self.transcript = transcript
        self.videoId = videoId
        self.syncStatus = syncStatus
        self.deletedAt = nil  // Always nil for manually created instances
        self.originalContentBase64 = originalContentBase64
        self.aiGeneratedContentBase64 = aiGeneratedContentBase64
        self.sectionsBase64 = sectionsBase64
        self.mindMapBase64 = mindMapBase64
        self.supplementaryMaterialsBase64 = supplementaryMaterialsBase64
        self.originalContentSize = originalContentSize
        self.aiGeneratedContentSize = aiGeneratedContentSize
        self.sectionsSize = sectionsSize
        self.mindMapSize = mindMapSize
        self.supplementaryMaterialsSize = supplementaryMaterialsSize
    }
}
