import Foundation
import CoreData
import Supabase

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

    /// Sync folders and notes from CoreData to Supabase (one-way, metadata only)
    /// - Parameters:
    ///   - context: The NSManagedObjectContext to fetch data from
    ///   - completion: Completion handler with success flag and optional error
    func syncToSupabase(context: NSManagedObjectContext, completion: @escaping (Bool, Error?) -> Void) {
        Task {
            do {
                // Check if user is signed in
                guard await supabaseService.isSignedIn() else {
                    let error = NSError(domain: "SupabaseSyncService", code: 401, userInfo: [
                        NSLocalizedDescriptionKey: "User is not signed in"
                    ])
                    completion(false, error)
                    return
                }

                // First sync folders
                let folderSuccess = try await syncFoldersToSupabase(context: context)

                // Then sync notes
                let noteSuccess = try await syncNotesMetadataToSupabase(context: context)

                // Update last sync time in UserDefaults
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastSupabaseSyncDate")

                // Call completion handler on main thread
                DispatchQueue.main.async {
                    completion(folderSuccess || noteSuccess, nil)
                }
            } catch {
                #if DEBUG
                print("🔄 SupabaseSyncService: Sync failed with error: \(error)")
                #endif

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

        // Sync each folder to Supabase
        var successCount = 0
        for folder in folders {
            do {
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

                successCount += 1
            } catch {
                #if DEBUG
                print("🔄 SupabaseSyncService: Error syncing folder \(folder.id?.uuidString ?? "unknown"): \(error)")
                #endif
            }
        }

        #if DEBUG
        print("🔄 SupabaseSyncService: Folder sync completed. Synced \(successCount) of \(folders.count) folders")
        #endif

        return successCount > 0
    }

    /// Sync notes from CoreData to Supabase (one-way, metadata only)
    /// - Parameter context: The NSManagedObjectContext to fetch notes from
    /// - Returns: Success flag
    private func syncNotesMetadataToSupabase(context: NSManagedObjectContext) async throws -> Bool {
        // Get current user ID
        let session = try await supabaseService.getSession()
        let userId = session.user.id

        #if DEBUG
        print("🔄 SupabaseSyncService: Starting note sync for user: \(userId)")
        #endif

        // Fetch notes from CoreData that need syncing
        let notes = try await fetchNotesForSync(context: context)

        #if DEBUG
        print("🔄 SupabaseSyncService: Found \(notes.count) notes to sync")
        #endif

        // Convert CoreData notes to Supabase notes
        let supabaseNotes = notes.map { note in
            createSupabaseNoteFromCoreData(note: note, userId: userId)
        }

        // Sync each note to Supabase
        var successCount = 0
        for note in supabaseNotes {
            do {
                // Use the folderId from the SupabaseNote
                let folderId = note.folderId

                // Create a simplified note with all available metadata fields
                let metadataNote = SimpleSupabaseNote(
                    id: note.id,
                    title: note.title,
                    sourceType: note.sourceType,
                    timestamp: note.timestamp,
                    lastModified: note.lastModified,
                    isFavorite: note.isFavorite,
                    processingStatus: note.processingStatus,
                    userId: userId,
                    folderId: folderId,
                    keyPoints: note.keyPoints,
                    citations: note.citations,
                    duration: note.duration,
                    languageCode: note.languageCode,
                    sourceURL: note.sourceURL,
                    tags: note.tags,
                    transcript: note.transcript,
                    videoId: note.videoId,
                    syncStatus: note.syncStatus
                )

                // Check if note already exists in Supabase
                let existingNotes: [SimpleSupabaseNote] = try await supabaseService.fetch(
                    from: "notes",
                    filters: { query in
                        query.eq("id", value: note.id.uuidString)
                    }
                )

                if existingNotes.isEmpty {
                    // Insert new note
                    _ = try await supabaseService.client.from("notes")
                        .insert(metadataNote)
                        .execute()

                    #if DEBUG
                    print("🔄 SupabaseSyncService: Inserted note: \(note.id)")
                    #endif
                } else {
                    // Update existing note
                    _ = try await supabaseService.client.from("notes")
                        .update(metadataNote)
                        .eq("id", value: note.id.uuidString)
                        .execute()

                    #if DEBUG
                    print("🔄 SupabaseSyncService: Updated note: \(note.id)")
                    #endif
                }

                // Update sync status in CoreData
                await updateSyncStatus(noteId: note.id, status: "synced", context: context)

                successCount += 1
            } catch {
                #if DEBUG
                print("🔄 SupabaseSyncService: Error syncing note \(note.id): \(error)")
                #endif
            }
        }

        #if DEBUG
        print("🔄 SupabaseSyncService: Note sync completed. Synced \(successCount) of \(notes.count) notes")
        #endif

        return successCount > 0
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
