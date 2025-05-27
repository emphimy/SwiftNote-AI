import Foundation
import CoreData
import Supabase

/// Manager class for handling all note-related sync operations between CoreData and Supabase
class NoteSyncManager {

    // MARK: - Dependencies

    private let supabaseService: SupabaseService
    private let transactionManager: SyncTransactionManager
    private let networkRecoveryManager: NetworkRecoveryManager
    private let progressCoordinator: ProgressUpdateCoordinator

    // MARK: - Initialization

    init(
        supabaseService: SupabaseService,
        transactionManager: SyncTransactionManager,
        networkRecoveryManager: NetworkRecoveryManager,
        progressCoordinator: ProgressUpdateCoordinator
    ) {
        self.supabaseService = supabaseService
        self.transactionManager = transactionManager
        self.networkRecoveryManager = networkRecoveryManager
        self.progressCoordinator = progressCoordinator

        #if DEBUG
        print("🔄 NoteSyncManager: Initialized")
        #endif
    }

    // MARK: - Public Methods

    /// Sync notes from CoreData to Supabase
    /// - Parameters:
    ///   - context: The NSManagedObjectContext to fetch notes from
    ///   - includeBinaryData: Whether to include binary data in the sync
    ///   - updateProgress: Closure to update sync progress
    /// - Returns: Success flag
    func syncNotesToSupabase(context: NSManagedObjectContext, includeBinaryData: Bool, updateProgress: @escaping (SyncProgress) -> Void) async throws -> Bool {
        // Get current user ID
        let session = try await supabaseService.getSession()
        let userId = session.user.id

        #if DEBUG
        print("🔄 NoteSyncManager: Starting note sync for user: \(userId) with binary data: \(includeBinaryData)")
        #endif

        // Fetch notes from CoreData that need syncing
        let notes = try await fetchNotesForSync(context: context)

        #if DEBUG
        print("🔄 NoteSyncManager: Found \(notes.count) notes to sync")
        #endif

        // Update progress
        await MainActor.run {
            var progress = SyncProgress()
            progress.totalNotes = notes.count
            progress.syncedNotes = 0
            updateProgress(progress)
        }

        // Use an actor-isolated counter to track success
        let successCounter = SuccessCounter()

        for (index, note) in notes.enumerated() {
            do {
                // Update progress status with throttling
                progressCoordinator.scheduleUpdate {
                    var progress = SyncProgress()
                    progress.currentStatus = "Syncing note \(index + 1) of \(notes.count)"
                    updateProgress(progress)
                }

                // Check if this is a deleted note that needs to be removed from Supabase
                if note.deletedAt != nil {
                    // Delete the note from Supabase
                    try await deleteNoteFromSupabase(note: note, userId: userId, context: context)
                } else {
                    if includeBinaryData {
                        // Sync with binary data
                        try await syncNoteWithBinaryData(note: note, userId: userId, context: context)
                    } else {
                        // Sync metadata only
                        try await syncNoteMetadataOnly(note: note, userId: userId, context: context)
                    }
                }

                // Update sync status in CoreData
                await updateSyncStatus(noteId: note.id ?? UUID(), status: "synced", context: context)

                // Increment success counter in a thread-safe way
                await successCounter.increment()

                // Update progress with throttling
                let currentSuccessCount = await successCounter.getCount()
                progressCoordinator.scheduleUpdate {
                    var progress = SyncProgress()
                    progress.syncedNotes = currentSuccessCount
                    updateProgress(progress)
                }
            } catch {
                #if DEBUG
                print("🔄 NoteSyncManager: Error syncing note \(note.id?.uuidString ?? "unknown"): \(error)")
                #endif
            }
        }

        // Get final success count
        let finalSuccessCount = await successCounter.getCount()

        #if DEBUG
        print("🔄 NoteSyncManager: Note sync completed. Synced \(finalSuccessCount) of \(notes.count) notes")
        #endif

        return finalSuccessCount > 0
    }

    // MARK: - Private Helper Methods

    /// Fetch notes from CoreData that need syncing
    /// - Parameter context: The NSManagedObjectContext to fetch notes from
    /// - Returns: Array of notes that need syncing (including deleted notes)
    private func fetchNotesForSync(context: NSManagedObjectContext) async throws -> [Note] {
        return try await context.perform {
            let request = NSFetchRequest<Note>(entityName: "Note")

            // Include all notes (including deleted ones) for sync
            // We need to sync deleted notes to propagate deletions to Supabase
            // Filter by sync status to only sync notes that need syncing
            request.predicate = NSPredicate(format: "syncStatus != %@", "synced")

            // Sort by lastModified to sync newest changes first
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Note.lastModified, ascending: false)]

            let notes = try context.fetch(request)

            #if DEBUG
            let deletedCount = notes.filter { $0.deletedAt != nil }.count
            print("🔄 NoteSyncManager: Fetched \(notes.count) notes for sync (\(deletedCount) deleted)")
            #endif

            return notes
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

                    // Only save immediately if not in a transaction context
                    // Transaction contexts will be saved atomically later
                    let isTransactionContext = self.transactionManager.getCurrentContext() === context

                    if context.hasChanges && !isTransactionContext {
                        try context.save()

                        #if DEBUG
                        print("🔄 NoteSyncManager: Updated sync status for note \(noteId) to \(status)")
                        #endif
                    } else if isTransactionContext {
                        #if DEBUG
                        print("🔄 NoteSyncManager: Marked note \(noteId) sync status as \(status) in transaction")
                        #endif
                    }
                }
            } catch {
                #if DEBUG
                print("🔄 NoteSyncManager: Error updating sync status: \(error)")
                #endif
            }
        }
    }

    // MARK: - Placeholder Methods (To be implemented in future phases)

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
            syncStatus: "synced", // Mark as synced in remote database
            deletedAt: note.deletedAt
        )

        // Check if note already exists in Supabase with network recovery
        let existingNotes: [SimpleSupabaseNote] = try await networkRecoveryManager.executeWithRetry(
            operation: {
                try await self.supabaseService.fetch(
                    from: "notes",
                    filters: { query in
                        query.eq("id", value: metadataNote.id.uuidString)
                    }
                )
            },
            operationName: "Note Existence Check (\(metadataNote.title))"
        )

        if existingNotes.isEmpty {
            // Insert new note with network recovery
            _ = try await networkRecoveryManager.executeWithRetry(
                operation: {
                    try await self.supabaseService.client.from("notes")
                        .insert(metadataNote)
                        .execute()
                },
                operationName: "Note Insert (\(metadataNote.title))"
            )

            #if DEBUG
            print("🔄 NoteSyncManager: Inserted note metadata: \(metadataNote.id)")
            #endif
        } else {
            // Update existing note with network recovery
            _ = try await networkRecoveryManager.executeWithRetry(
                operation: {
                    try await self.supabaseService.client.from("notes")
                        .update(metadataNote)
                        .eq("id", value: metadataNote.id.uuidString)
                        .execute()
                },
                operationName: "Note Update (\(metadataNote.title))"
            )

            #if DEBUG
            print("🔄 NoteSyncManager: Updated note metadata: \(metadataNote.id)")
            #endif
        }
    }

    /// Sync a note with binary data
    /// - Parameters:
    ///   - note: The CoreData Note
    ///   - userId: The Supabase user ID
    ///   - context: The NSManagedObjectContext
    private func syncNoteWithBinaryData(note: Note, userId: UUID, context: NSManagedObjectContext) async throws {
        // Create a full note with binary data using SupabaseNote (direct binary format)
        let fullNote = createFullSupabaseNoteFromCoreData(note: note, userId: userId)

        // Check if note already exists in Supabase with network recovery
        let existingNotes: [SimpleSupabaseNote] = try await networkRecoveryManager.executeWithRetry(
            operation: {
                try await self.supabaseService.fetch(
                    from: "notes",
                    filters: { query in
                        query.eq("id", value: fullNote.id.uuidString)
                    }
                )
            },
            operationName: "Binary Note Existence Check (\(fullNote.title))"
        )

        if existingNotes.isEmpty {
            // Insert new note with binary data directly to bytea columns with network recovery
            _ = try await networkRecoveryManager.executeWithRetry(
                operation: {
                    try await self.supabaseService.client.from("notes")
                        .insert(fullNote)
                        .execute()
                },
                operationName: "Binary Note Insert (\(fullNote.title))"
            )

            #if DEBUG
            print("🔄 NoteSyncManager: Inserted note with binary data: \(fullNote.id)")
            if let originalContent = fullNote.originalContent {
                let sizeInMB = originalContent.sizeInMB()
                print("🔄 NoteSyncManager: Uploaded originalContent (\(String(format: "%.2f", sizeInMB)) MB)")
            }
            if let aiContent = fullNote.aiGeneratedContent {
                let sizeInMB = aiContent.sizeInMB()
                print("🔄 NoteSyncManager: Uploaded aiGeneratedContent (\(String(format: "%.2f", sizeInMB)) MB)")
            }
            #endif
        } else {
            // Update existing note with binary data directly to bytea columns with network recovery
            _ = try await networkRecoveryManager.executeWithRetry(
                operation: {
                    try await self.supabaseService.client.from("notes")
                        .update(fullNote)
                        .eq("id", value: fullNote.id.uuidString)
                        .execute()
                },
                operationName: "Binary Note Update (\(fullNote.title))"
            )

            #if DEBUG
            print("🔄 NoteSyncManager: Updated note with binary data: \(fullNote.id)")
            if let originalContent = fullNote.originalContent {
                let sizeInMB = originalContent.sizeInMB()
                print("🔄 NoteSyncManager: Updated originalContent (\(String(format: "%.2f", sizeInMB)) MB)")
            }
            if let aiContent = fullNote.aiGeneratedContent {
                let sizeInMB = aiContent.sizeInMB()
                print("🔄 NoteSyncManager: Updated aiGeneratedContent (\(String(format: "%.2f", sizeInMB)) MB)")
            }
            #endif
        }
    }

    // MARK: - Note Creation Methods

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

            // Set sync fields - mark as synced in remote database
            syncStatus: "synced",
            deletedAt: note.deletedAt
        )
    }

    /// Create a full SupabaseNote from a CoreData Note with binary data
    /// - Parameters:
    ///   - note: The CoreData Note
    ///   - userId: The Supabase user ID
    /// - Returns: A SupabaseNote with binary data included
    private func createFullSupabaseNoteFromCoreData(note: Note, userId: UUID) -> SupabaseNote {
        // Get folder ID if available
        var folderId: UUID? = nil
        if let folder = note.folder, let folderID = folder.id {
            folderId = folderID
        }

        // Create a SupabaseNote with all fields including binary data
        return SupabaseNote(
            id: note.id ?? UUID(),
            title: note.title ?? "Untitled Note",
            originalContent: note.originalContent, // Include binary content
            aiGeneratedContent: note.aiGeneratedContent, // Include binary content
            sourceType: note.sourceType ?? "text",
            timestamp: note.timestamp ?? Date(),
            lastModified: note.lastModified ?? Date(),
            isFavorite: note.isFavorite,
            processingStatus: note.processingStatus ?? "completed",
            folderId: folderId,
            userId: userId,

            // Include all available metadata
            summary: nil,
            keyPoints: note.keyPoints,
            citations: note.citations,
            duration: note.duration,
            languageCode: note.transcriptLanguage,
            sourceURL: note.sourceURL?.absoluteString,
            tags: note.tags,
            transcript: note.transcript,
            sections: note.sections, // Include binary content
            supplementaryMaterials: note.supplementaryMaterials, // Include binary content
            mindMap: note.mindMap, // Include binary content
            videoId: note.videoId,

            // Set sync fields - mark as synced in remote database
            syncStatus: "synced",
            deletedAt: note.deletedAt
        )
    }

    /// Create an EnhancedSupabaseNote from a CoreData Note with Base64-encoded binary data
    /// - Parameters:
    ///   - note: The CoreData Note
    ///   - userId: The Supabase user ID
    /// - Returns: An EnhancedSupabaseNote with Base64-encoded binary data
    /// - Throws: Error if binary data conversion fails
    /// NOTE: This method is deprecated in favor of createFullSupabaseNoteFromCoreData for direct binary format
    private func createEnhancedSupabaseNoteFromCoreData(note: Note, userId: UUID) throws -> EnhancedSupabaseNote {
        // Get folder ID if available
        var folderId: UUID? = nil
        if let folder = note.folder, let folderID = folder.id {
            folderId = folderID
        }

        // Define maximum size for binary data (10MB)
        let maxBinaryDataSize: Double = 10 * 1024 * 1024 // 10MB in bytes

        // Convert binary data to Base64 strings with size validation
        var originalContentBase64: String? = nil
        var originalContentSize: Double = 0
        if let originalContentData = note.originalContent {
            let sizeInBytes = Double(originalContentData.count)
            if sizeInBytes <= maxBinaryDataSize {
                originalContentBase64 = originalContentData.base64EncodedString()
                originalContentSize = sizeInBytes
                #if DEBUG
                let sizeInMB = sizeInBytes / (1024 * 1024)
                print("🔄 NoteSyncManager: Encoded originalContent (\(String(format: "%.2f", sizeInMB)) MB) to Base64")
                #endif
            } else {
                let sizeInMB = sizeInBytes / (1024 * 1024)
                #if DEBUG
                print("🔄 NoteSyncManager: Skipping originalContent (\(String(format: "%.2f", sizeInMB)) MB) - exceeds 10MB limit")
                #endif
                throw NSError(domain: "NoteSyncManager", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Original content exceeds 10MB limit"])
            }
        }

        var aiGeneratedContentBase64: String? = nil
        var aiGeneratedContentSize: Double = 0
        if let aiContentData = note.aiGeneratedContent {
            let sizeInBytes = Double(aiContentData.count)
            if sizeInBytes <= maxBinaryDataSize {
                aiGeneratedContentBase64 = aiContentData.base64EncodedString()
                aiGeneratedContentSize = sizeInBytes
                #if DEBUG
                let sizeInMB = sizeInBytes / (1024 * 1024)
                print("🔄 NoteSyncManager: Encoded aiGeneratedContent (\(String(format: "%.2f", sizeInMB)) MB) to Base64")
                #endif
            } else {
                let sizeInMB = sizeInBytes / (1024 * 1024)
                #if DEBUG
                print("🔄 NoteSyncManager: Skipping aiGeneratedContent (\(String(format: "%.2f", sizeInMB)) MB) - exceeds 10MB limit")
                #endif
                throw NSError(domain: "NoteSyncManager", code: 1002, userInfo: [NSLocalizedDescriptionKey: "AI generated content exceeds 10MB limit"])
            }
        }

        var sectionsBase64: String? = nil
        var sectionsSize: Double = 0
        if let sectionsData = note.sections {
            let sizeInBytes = Double(sectionsData.count)
            if sizeInBytes <= maxBinaryDataSize {
                sectionsBase64 = sectionsData.base64EncodedString()
                sectionsSize = sizeInBytes
                #if DEBUG
                let sizeInMB = sizeInBytes / (1024 * 1024)
                print("🔄 NoteSyncManager: Encoded sections (\(String(format: "%.2f", sizeInMB)) MB) to Base64")
                #endif
            } else {
                let sizeInMB = sizeInBytes / (1024 * 1024)
                #if DEBUG
                print("🔄 NoteSyncManager: Skipping sections (\(String(format: "%.2f", sizeInMB)) MB) - exceeds 10MB limit")
                #endif
                // Don't throw error for sections - just skip them
            }
        }

        var mindMapBase64: String? = nil
        var mindMapSize: Double = 0
        if let mindMapData = note.mindMap {
            let sizeInBytes = Double(mindMapData.count)
            if sizeInBytes <= maxBinaryDataSize {
                mindMapBase64 = mindMapData.base64EncodedString()
                mindMapSize = sizeInBytes
                #if DEBUG
                let sizeInMB = sizeInBytes / (1024 * 1024)
                print("🔄 NoteSyncManager: Encoded mindMap (\(String(format: "%.2f", sizeInMB)) MB) to Base64")
                #endif
            } else {
                let sizeInMB = sizeInBytes / (1024 * 1024)
                #if DEBUG
                print("🔄 NoteSyncManager: Skipping mindMap (\(String(format: "%.2f", sizeInMB)) MB) - exceeds 10MB limit")
                #endif
                // Don't throw error for mindMap - just skip it
            }
        }

        var supplementaryMaterialsBase64: String? = nil
        var supplementaryMaterialsSize: Double = 0
        if let supplementaryData = note.supplementaryMaterials {
            let sizeInBytes = Double(supplementaryData.count)
            if sizeInBytes <= maxBinaryDataSize {
                supplementaryMaterialsBase64 = supplementaryData.base64EncodedString()
                supplementaryMaterialsSize = sizeInBytes
                #if DEBUG
                let sizeInMB = sizeInBytes / (1024 * 1024)
                print("🔄 NoteSyncManager: Encoded supplementaryMaterials (\(String(format: "%.2f", sizeInMB)) MB) to Base64")
                #endif
            } else {
                let sizeInMB = sizeInBytes / (1024 * 1024)
                #if DEBUG
                print("🔄 NoteSyncManager: Skipping supplementaryMaterials (\(String(format: "%.2f", sizeInMB)) MB) - exceeds 10MB limit")
                #endif
                // Don't throw error for supplementary materials - just skip them
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
            syncStatus: "synced", // Mark as synced in remote database

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

    /// Placeholder for deleteNoteFromSupabase - will be implemented in Phase 4
    private func deleteNoteFromSupabase(note: Note, userId: UUID, context: NSManagedObjectContext) async throws {
        // TODO: Implement in Phase 4
        fatalError("deleteNoteFromSupabase not yet implemented")
    }
}
