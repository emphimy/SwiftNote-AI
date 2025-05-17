import Foundation
import CoreData
import Supabase
import SwiftUI

/// Service class for syncing data between CoreData and Supabase
class SupabaseSyncService {
    // MARK: - Singleton
    static let shared = SupabaseSyncService()

    // MARK: - Properties
    private let supabaseService = SupabaseService.shared

    // MARK: - Initialization
    private init() {
        #if DEBUG
        print("🔄 SupabaseSyncService: Initializing")
        #endif
    }

    // MARK: - Public Methods

    /// Sync progress information
    struct SyncProgress {
        var totalNotes: Int = 0
        var syncedNotes: Int = 0
        var totalFolders: Int = 0
        var syncedFolders: Int = 0
        var currentStatus: String = "Preparing..."
        var includeBinaryData: Bool = false

        var folderProgress: Double {
            return totalFolders > 0 ? Double(syncedFolders) / Double(totalFolders) : 0
        }

        var noteProgress: Double {
            return totalNotes > 0 ? Double(syncedNotes) / Double(totalNotes) : 0
        }

        var overallProgress: Double {
            // Weight folders as 30% and notes as 70% of overall progress
            return (folderProgress * 0.3) + (noteProgress * 0.7)
        }
    }

    /// Sync progress publisher
    @Published var syncProgress = SyncProgress()

    /// Sync folders and notes from CoreData to Supabase
    /// - Parameters:
    ///   - context: The NSManagedObjectContext to fetch data from
    ///   - includeBinaryData: Whether to include binary data in the sync (default: false)
    ///   - completion: Completion handler with success flag and optional error
    func syncToSupabase(context: NSManagedObjectContext, includeBinaryData: Bool = false, completion: @escaping (Bool, Error?) -> Void) {
        Task {
            do {
                // Reset sync progress
                await MainActor.run {
                    syncProgress = SyncProgress()
                    syncProgress.includeBinaryData = includeBinaryData
                    syncProgress.currentStatus = "Checking authentication..."
                }

                // Check if user is signed in
                guard await supabaseService.isSignedIn() else {
                    let error = NSError(domain: "SupabaseSyncService", code: 401, userInfo: [
                        NSLocalizedDescriptionKey: "User is not signed in"
                    ])
                    completion(false, error)
                    return
                }

                await MainActor.run {
                    syncProgress.currentStatus = "Syncing folders..."
                }

                // First sync folders
                let folderSuccess = try await syncFoldersToSupabase(context: context)

                await MainActor.run {
                    syncProgress.currentStatus = "Syncing notes..."
                }

                // Then sync notes
                let noteSuccess = try await syncNotesToSupabase(context: context, includeBinaryData: includeBinaryData)

                // Update last sync time in UserDefaults
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastSupabaseSyncDate")

                await MainActor.run {
                    syncProgress.currentStatus = "Sync completed"
                }

                // Call completion handler on main thread
                DispatchQueue.main.async {
                    completion(folderSuccess || noteSuccess, nil)
                }
            } catch {
                #if DEBUG
                print("🔄 SupabaseSyncService: Sync failed with error: \(error)")
                #endif

                await MainActor.run {
                    syncProgress.currentStatus = "Sync failed: \(error.localizedDescription)"
                }

                // Call completion handler on main thread
                DispatchQueue.main.async {
                    completion(false, error)
                }
            }
        }
    }

    /// Sync folders from CoreData to Supabase (one-way, metadata only)
    /// - Parameter context: The NSManagedObjectContext to fetch folders from
    /// - Returns: Success flag
    private func syncFoldersToSupabase(context: NSManagedObjectContext) async throws -> Bool {
        // Get current user ID
        let session = try await supabaseService.getSession()
        let userId = session.user.id

        #if DEBUG
        print("🔄 SupabaseSyncService: Starting folder sync for user: \(userId)")
        #endif

        // Fetch folders from CoreData that need syncing
        let folders = try await fetchFoldersForSync(context: context)

        #if DEBUG
        print("🔄 SupabaseSyncService: Found \(folders.count) folders to sync")
        #endif

        // Update progress
        await MainActor.run {
            syncProgress.totalFolders = folders.count
            syncProgress.syncedFolders = 0
        }

        // Sync each folder to Supabase
        // Use an actor-isolated counter to track success
        actor SuccessCounter {
            var count = 0

            func increment() {
                count += 1
            }

            func getCount() -> Int {
                return count
            }
        }

        let successCounter = SuccessCounter()

        for (index, folder) in folders.enumerated() {
            do {
                // Update progress status
                await MainActor.run {
                    syncProgress.currentStatus = "Syncing folder \(index + 1) of \(folders.count)"
                }

                // Create a simplified folder with metadata fields
                let metadataFolder = SimpleSupabaseFolder(
                    id: folder.id ?? UUID(),
                    name: folder.name ?? "Untitled Folder",
                    color: folder.color ?? "blue",
                    timestamp: folder.timestamp ?? Date(),
                    sortOrder: folder.sortOrder,
                    userId: userId,
                    updatedAt: folder.updatedAt,
                    syncStatus: folder.syncStatus,
                    deletedAt: folder.deletedAt
                )

                // Check if folder already exists in Supabase
                let existingFolders: [SimpleSupabaseFolder] = try await supabaseService.fetch(
                    from: "folders",
                    filters: { query in
                        query.eq("id", value: metadataFolder.id.uuidString)
                    }
                )

                if existingFolders.isEmpty {
                    // Insert new folder
                    _ = try await supabaseService.client.from("folders")
                        .insert(metadataFolder)
                        .execute()

                    #if DEBUG
                    print("🔄 SupabaseSyncService: Inserted folder: \(metadataFolder.id)")
                    #endif
                } else {
                    // Update existing folder
                    _ = try await supabaseService.client.from("folders")
                        .update(metadataFolder)
                        .eq("id", value: metadataFolder.id.uuidString)
                        .execute()

                    #if DEBUG
                    print("🔄 SupabaseSyncService: Updated folder: \(metadataFolder.id)")
                    #endif
                }

                // Update sync status in CoreData
                await updateFolderSyncStatus(folderId: metadataFolder.id, status: "synced", context: context)

                // Increment success counter in a thread-safe way
                await successCounter.increment()

                // Update progress
                let currentSuccessCount = await successCounter.getCount()
                await MainActor.run {
                    syncProgress.syncedFolders = currentSuccessCount
                }
            } catch {
                #if DEBUG
                print("🔄 SupabaseSyncService: Error syncing folder \(folder.id?.uuidString ?? "unknown"): \(error)")
                #endif
            }
        }

        // Get final success count
        let finalSuccessCount = await successCounter.getCount()

        #if DEBUG
        print("🔄 SupabaseSyncService: Folder sync completed. Synced \(finalSuccessCount) of \(folders.count) folders")
        #endif

        return finalSuccessCount > 0
    }

    /// Sync notes from CoreData to Supabase
    /// - Parameters:
    ///   - context: The NSManagedObjectContext to fetch notes from
    ///   - includeBinaryData: Whether to include binary data in the sync
    /// - Returns: Success flag
    private func syncNotesToSupabase(context: NSManagedObjectContext, includeBinaryData: Bool) async throws -> Bool {
        // Get current user ID
        let session = try await supabaseService.getSession()
        let userId = session.user.id

        #if DEBUG
        print("🔄 SupabaseSyncService: Starting note sync for user: \(userId) with binary data: \(includeBinaryData)")
        #endif

        // Fetch notes from CoreData that need syncing
        let notes = try await fetchNotesForSync(context: context)

        #if DEBUG
        print("🔄 SupabaseSyncService: Found \(notes.count) notes to sync")
        #endif

        // Update progress
        await MainActor.run {
            syncProgress.totalNotes = notes.count
            syncProgress.syncedNotes = 0
        }

        // Sync each note to Supabase
        // Use an actor-isolated counter to track success
        actor SuccessCounter {
            var count = 0

            func increment() {
                count += 1
            }

            func getCount() -> Int {
                return count
            }
        }

        let successCounter = SuccessCounter()

        for (index, note) in notes.enumerated() {
            do {
                // Update progress status
                await MainActor.run {
                    syncProgress.currentStatus = "Syncing note \(index + 1) of \(notes.count)"
                }

                if includeBinaryData {
                    // Sync with binary data
                    try await syncNoteWithBinaryData(note: note, userId: userId, context: context)
                } else {
                    // Sync metadata only
                    try await syncNoteMetadataOnly(note: note, userId: userId, context: context)
                }

                // Update sync status in CoreData
                await updateSyncStatus(noteId: note.id ?? UUID(), status: "synced", context: context)

                // Increment success counter in a thread-safe way
                await successCounter.increment()

                // Update progress
                let currentSuccessCount = await successCounter.getCount()
                await MainActor.run {
                    syncProgress.syncedNotes = currentSuccessCount
                }
            } catch {
                #if DEBUG
                print("🔄 SupabaseSyncService: Error syncing note \(note.id?.uuidString ?? "unknown"): \(error)")
                #endif
            }
        }

        // Get final success count
        let finalSuccessCount = await successCounter.getCount()

        #if DEBUG
        print("🔄 SupabaseSyncService: Note sync completed. Synced \(finalSuccessCount) of \(notes.count) notes")
        #endif

        return finalSuccessCount > 0
    }

    /// Sync a note's metadata only (no binary data)
    /// - Parameters:
    ///   - note: The CoreData Note
    ///   - userId: The Supabase user ID
    ///   - context: The NSManagedObjectContext
    private func syncNoteMetadataOnly(note: Note, userId: UUID, context: NSManagedObjectContext) async throws {
        // Get folder ID if available
        var folderId: UUID? = nil
        if let folder = note.folder, let folderID = folder.id {
            folderId = folderID
        }

        // Create a simplified note with all available metadata fields
        let metadataNote = SimpleSupabaseNote(
            id: note.id ?? UUID(),
            title: note.title ?? "Untitled Note",
            sourceType: note.sourceType ?? "text",
            timestamp: note.timestamp ?? Date(),
            lastModified: note.lastModified ?? Date(),
            isFavorite: note.isFavorite,
            processingStatus: note.processingStatus ?? "completed",
            userId: userId,
            folderId: folderId,
            keyPoints: note.keyPoints,
            citations: note.citations,
            duration: note.duration,
            languageCode: note.transcriptLanguage,
            sourceURL: note.sourceURL?.absoluteString,
            tags: note.tags,
            transcript: note.transcript,
            videoId: note.videoId,
            syncStatus: note.syncStatus
        )

        // Check if note already exists in Supabase
        let existingNotes: [SimpleSupabaseNote] = try await supabaseService.fetch(
            from: "notes",
            filters: { query in
                query.eq("id", value: metadataNote.id.uuidString)
            }
        )

        if existingNotes.isEmpty {
            // Insert new note
            _ = try await supabaseService.client.from("notes")
                .insert(metadataNote)
                .execute()

            #if DEBUG
            print("🔄 SupabaseSyncService: Inserted note metadata: \(metadataNote.id)")
            #endif
        } else {
            // Update existing note
            _ = try await supabaseService.client.from("notes")
                .update(metadataNote)
                .eq("id", value: metadataNote.id.uuidString)
                .execute()

            #if DEBUG
            print("🔄 SupabaseSyncService: Updated note metadata: \(metadataNote.id)")
            #endif
        }
    }

    /// Sync a note with binary data
    /// - Parameters:
    ///   - note: The CoreData Note
    ///   - userId: The Supabase user ID
    ///   - context: The NSManagedObjectContext
    private func syncNoteWithBinaryData(note: Note, userId: UUID, context: NSManagedObjectContext) async throws {
        // Create an enhanced note with Base64-encoded binary data
        let enhancedNote = try createEnhancedSupabaseNoteFromCoreData(note: note, userId: userId)

        // Check if note already exists in Supabase
        let existingNotes: [SimpleSupabaseNote] = try await supabaseService.fetch(
            from: "notes",
            filters: { query in
                query.eq("id", value: enhancedNote.id.uuidString)
            }
        )

        if existingNotes.isEmpty {
            // Insert new note
            _ = try await supabaseService.client.from("notes")
                .insert(enhancedNote)
                .execute()

            #if DEBUG
            print("🔄 SupabaseSyncService: Inserted note with binary data: \(enhancedNote.id)")
            #endif
        } else {
            // Update existing note
            _ = try await supabaseService.client.from("notes")
                .update(enhancedNote)
                .eq("id", value: enhancedNote.id.uuidString)
                .execute()

            #if DEBUG
            print("🔄 SupabaseSyncService: Updated note with binary data: \(enhancedNote.id)")
            #endif
        }
    }

    // MARK: - Private Methods

    /// Fetch notes from CoreData that need syncing
    /// - Parameter context: The NSManagedObjectContext to fetch notes from
    /// - Returns: Array of notes that need syncing
    private func fetchNotesForSync(context: NSManagedObjectContext) async throws -> [Note] {
        return try await context.perform {
            let request = NSFetchRequest<Note>(entityName: "Note")

            // Only fetch notes that need syncing or have never been synced
            // For initial implementation, we'll sync all notes
            // In the future, we can filter by syncStatus

            // Sort by lastModified to sync newest changes first
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Note.lastModified, ascending: false)]

            return try context.fetch(request)
        }
    }

    /// Create a SupabaseNote from a CoreData Note
    /// - Parameters:
    ///   - note: The CoreData Note
    ///   - userId: The Supabase user ID
    /// - Returns: A SupabaseNote with metadata only
    private func createSupabaseNoteFromCoreData(note: Note, userId: UUID) -> SupabaseNote {
        // Get folder ID if available
        var folderId: UUID? = nil
        if let folder = note.folder, let folderID = folder.id {
            folderId = folderID
        }

        // Create a SupabaseNote with metadata fields
        return SupabaseNote(
            id: note.id ?? UUID(),
            title: note.title ?? "Untitled Note",
            originalContent: nil, // Exclude binary content for now
            aiGeneratedContent: nil, // Exclude binary content for now
            sourceType: note.sourceType ?? "text",
            timestamp: note.timestamp ?? Date(),
            lastModified: note.lastModified ?? Date(),
            isFavorite: note.isFavorite,
            processingStatus: note.processingStatus ?? "completed",
            folderId: folderId,
            userId: userId,

            // Include all available metadata (Note: CoreData Note doesn't have a summary field)
            summary: nil,
            keyPoints: note.keyPoints,
            citations: note.citations,
            duration: note.duration,
            languageCode: note.transcriptLanguage,
            sourceURL: note.sourceURL?.absoluteString, // This is correct for CoreData Note
            tags: note.tags,
            transcript: note.transcript,
            sections: nil, // Exclude binary content
            supplementaryMaterials: nil, // Exclude binary content
            mindMap: nil, // Exclude binary content
            videoId: note.videoId,

            // Set sync fields
            syncStatus: note.syncStatus ?? "synced",
            deletedAt: note.deletedAt
        )
    }

    /// Create an EnhancedSupabaseNote from a CoreData Note with Base64-encoded binary data
    /// - Parameters:
    ///   - note: The CoreData Note
    ///   - userId: The Supabase user ID
    /// - Returns: An EnhancedSupabaseNote with Base64-encoded binary data
    /// - Throws: Error if binary data conversion fails
    private func createEnhancedSupabaseNoteFromCoreData(note: Note, userId: UUID) throws -> EnhancedSupabaseNote {
        // Get folder ID if available
        var folderId: UUID? = nil
        if let folder = note.folder, let folderID = folder.id {
            folderId = folderID
        }

        // Define maximum size for binary data (10MB)
        let maxBinaryDataSize: Double = 10 * 1024 * 1024 // 10MB in bytes

        // Process original content
        var originalContentBase64: String? = nil
        var originalContentSize: Double? = nil
        if let originalContent = note.originalContent {
            originalContentSize = originalContent.sizeInBytes

            // Check if size is within limits
            if originalContentSize ?? 0 <= maxBinaryDataSize {
                originalContentBase64 = originalContent.toBase64String()

                #if DEBUG
                let sizeInMB = (originalContentSize ?? 0) / (1024 * 1024)
                print("🔄 SupabaseSyncService: Encoded originalContent (\(String(format: "%.2f", sizeInMB)) MB)")
                #endif
            } else {
                #if DEBUG
                let sizeInMB = (originalContentSize ?? 0) / (1024 * 1024)
                print("🔄 SupabaseSyncService: originalContent too large to sync (\(String(format: "%.2f", sizeInMB)) MB)")
                #endif
            }
        }

        // Process AI generated content
        var aiGeneratedContentBase64: String? = nil
        var aiGeneratedContentSize: Double? = nil
        if let aiGeneratedContent = note.aiGeneratedContent {
            aiGeneratedContentSize = aiGeneratedContent.sizeInBytes

            // Check if size is within limits
            if aiGeneratedContentSize ?? 0 <= maxBinaryDataSize {
                aiGeneratedContentBase64 = aiGeneratedContent.toBase64String()

                #if DEBUG
                let sizeInMB = (aiGeneratedContentSize ?? 0) / (1024 * 1024)
                print("🔄 SupabaseSyncService: Encoded aiGeneratedContent (\(String(format: "%.2f", sizeInMB)) MB)")
                #endif
            } else {
                #if DEBUG
                let sizeInMB = (aiGeneratedContentSize ?? 0) / (1024 * 1024)
                print("🔄 SupabaseSyncService: aiGeneratedContent too large to sync (\(String(format: "%.2f", sizeInMB)) MB)")
                #endif
            }
        }

        // Process sections
        var sectionsBase64: String? = nil
        var sectionsSize: Double? = nil
        if let sections = note.sections {
            sectionsSize = sections.sizeInBytes

            // Check if size is within limits
            if sectionsSize ?? 0 <= maxBinaryDataSize {
                sectionsBase64 = sections.toBase64String()

                #if DEBUG
                let sizeInMB = (sectionsSize ?? 0) / (1024 * 1024)
                print("🔄 SupabaseSyncService: Encoded sections (\(String(format: "%.2f", sizeInMB)) MB)")
                #endif
            } else {
                #if DEBUG
                let sizeInMB = (sectionsSize ?? 0) / (1024 * 1024)
                print("🔄 SupabaseSyncService: sections too large to sync (\(String(format: "%.2f", sizeInMB)) MB)")
                #endif
            }
        }

        // Process mind map
        var mindMapBase64: String? = nil
        var mindMapSize: Double? = nil
        if let mindMap = note.mindMap {
            mindMapSize = mindMap.sizeInBytes

            // Check if size is within limits
            if mindMapSize ?? 0 <= maxBinaryDataSize {
                mindMapBase64 = mindMap.toBase64String()

                #if DEBUG
                let sizeInMB = (mindMapSize ?? 0) / (1024 * 1024)
                print("🔄 SupabaseSyncService: Encoded mindMap (\(String(format: "%.2f", sizeInMB)) MB)")
                #endif
            } else {
                #if DEBUG
                let sizeInMB = (mindMapSize ?? 0) / (1024 * 1024)
                print("🔄 SupabaseSyncService: mindMap too large to sync (\(String(format: "%.2f", sizeInMB)) MB)")
                #endif
            }
        }

        // Process supplementary materials
        var supplementaryMaterialsBase64: String? = nil
        var supplementaryMaterialsSize: Double? = nil
        if let supplementaryMaterials = note.supplementaryMaterials {
            supplementaryMaterialsSize = supplementaryMaterials.sizeInBytes

            // Check if size is within limits
            if supplementaryMaterialsSize ?? 0 <= maxBinaryDataSize {
                supplementaryMaterialsBase64 = supplementaryMaterials.toBase64String()

                #if DEBUG
                let sizeInMB = (supplementaryMaterialsSize ?? 0) / (1024 * 1024)
                print("🔄 SupabaseSyncService: Encoded supplementaryMaterials (\(String(format: "%.2f", sizeInMB)) MB)")
                #endif
            } else {
                #if DEBUG
                let sizeInMB = (supplementaryMaterialsSize ?? 0) / (1024 * 1024)
                print("🔄 SupabaseSyncService: supplementaryMaterials too large to sync (\(String(format: "%.2f", sizeInMB)) MB)")
                #endif
            }
        }

        // Create an EnhancedSupabaseNote with all fields
        return EnhancedSupabaseNote(
            id: note.id ?? UUID(),
            title: note.title ?? "Untitled Note",
            sourceType: note.sourceType ?? "text",
            timestamp: note.timestamp ?? Date(),
            lastModified: note.lastModified ?? Date(),
            isFavorite: note.isFavorite,
            processingStatus: note.processingStatus ?? "completed",
            userId: userId,
            folderId: folderId,
            keyPoints: note.keyPoints,
            citations: note.citations,
            duration: note.duration,
            languageCode: note.transcriptLanguage,
            sourceURL: note.sourceURL?.absoluteString,
            tags: note.tags,
            transcript: note.transcript,
            videoId: note.videoId,
            syncStatus: note.syncStatus,

            // Include Base64-encoded binary data
            originalContentBase64: originalContentBase64,
            aiGeneratedContentBase64: aiGeneratedContentBase64,
            sectionsBase64: sectionsBase64,
            mindMapBase64: mindMapBase64,
            supplementaryMaterialsBase64: supplementaryMaterialsBase64,

            // Include size metadata
            originalContentSize: originalContentSize,
            aiGeneratedContentSize: aiGeneratedContentSize,
            sectionsSize: sectionsSize,
            mindMapSize: mindMapSize,
            supplementaryMaterialsSize: supplementaryMaterialsSize
        )
    }

    /// A simplified version of SupabaseFolder with only the metadata fields
    /// This helps avoid encoding/decoding issues with complex fields
    private struct SimpleSupabaseFolder: Codable {
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
    private struct SimpleSupabaseNote: Codable {
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
        }
    }

    /// An enhanced version of SupabaseNote that includes Base64-encoded binary data
    /// This allows us to sync binary content while avoiding encoding/decoding issues
    private struct EnhancedSupabaseNote: Codable {
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

        // Add Base64-encoded binary data fields
        let originalContentBase64: String?
        let aiGeneratedContentBase64: String?
        let sectionsBase64: String?
        let mindMapBase64: String?
        let supplementaryMaterialsBase64: String?

        // Add metadata about binary content - these are not sent to Supabase
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

            // Binary data fields
            case originalContentBase64 = "original_content"
            case aiGeneratedContentBase64 = "ai_generated_content"
            case sectionsBase64 = "sections"
            case mindMapBase64 = "mind_map"
            case supplementaryMaterialsBase64 = "supplementary_materials"

            // Size metadata fields are intentionally excluded from CodingKeys
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

            // Initialize size metadata fields to nil since they're not in the JSON
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

    /// Fetch folders from CoreData that need syncing
    /// - Parameter context: The NSManagedObjectContext to fetch folders from
    /// - Returns: Array of folders that need syncing
    private func fetchFoldersForSync(context: NSManagedObjectContext) async throws -> [Folder] {
        return try await context.perform {
            let request = NSFetchRequest<Folder>(entityName: "Folder")

            // Only fetch folders that need syncing or have never been synced
            // For initial implementation, we'll sync all folders
            // In the future, we can filter by syncStatus

            // Sort by updatedAt to sync newest changes first
            request.sortDescriptors = [
                NSSortDescriptor(keyPath: \Folder.sortOrder, ascending: true),
                NSSortDescriptor(keyPath: \Folder.updatedAt, ascending: false)
            ]

            // Get all folders
            let allFolders = try context.fetch(request)

            #if DEBUG
            print("🔄 SupabaseSyncService: Fetched \(allFolders.count) folders for sync")
            #endif

            return allFolders
        }
    }

    /// Update the sync status of a folder in CoreData
    /// - Parameters:
    ///   - folderId: The ID of the folder
    ///   - status: The new sync status
    ///   - context: The NSManagedObjectContext
    private func updateFolderSyncStatus(folderId: UUID, status: String, context: NSManagedObjectContext) async {
        await context.perform {
            let request = NSFetchRequest<Folder>(entityName: "Folder")
            request.predicate = NSPredicate(format: "id == %@", folderId as CVarArg)
            request.fetchLimit = 1

            do {
                let results = try context.fetch(request)
                if let folder = results.first {
                    folder.syncStatus = status

                    if context.hasChanges {
                        try context.save()

                        #if DEBUG
                        print("🔄 SupabaseSyncService: Updated sync status for folder \(folderId) to \(status)")
                        #endif
                    }
                }
            } catch {
                #if DEBUG
                print("🔄 SupabaseSyncService: Error updating folder sync status: \(error)")
                #endif
            }
        }
    }

    /// Update the sync status of a note in CoreData
    /// - Parameters:
    ///   - noteId: The ID of the note
    ///   - status: The new sync status
    ///   - context: The NSManagedObjectContext
    private func updateSyncStatus(noteId: UUID, status: String, context: NSManagedObjectContext) async {
        await context.perform {
            let request = NSFetchRequest<Note>(entityName: "Note")
            request.predicate = NSPredicate(format: "id == %@", noteId as CVarArg)
            request.fetchLimit = 1

            do {
                let results = try context.fetch(request)
                if let note = results.first {
                    note.syncStatus = status

                    if context.hasChanges {
                        try context.save()

                        #if DEBUG
                        print("🔄 SupabaseSyncService: Updated sync status for note \(noteId) to \(status)")
                        #endif
                    }
                }
            } catch {
                #if DEBUG
                print("🔄 SupabaseSyncService: Error updating sync status: \(error)")
                #endif
            }
        }
    }
}
