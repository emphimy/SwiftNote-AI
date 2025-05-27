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

    // MARK: - Download Methods

    /// Download notes from Supabase to CoreData
    /// - Parameters:
    ///   - context: The NSManagedObjectContext to save notes to
    ///   - includeBinaryData: Whether to include binary data in the download
    ///   - updateProgress: Closure to update sync progress
    /// - Returns: Success flag
    func downloadNotesFromSupabase(context: NSManagedObjectContext, includeBinaryData: Bool, updateProgress: @escaping (SyncProgress) -> Void) async throws -> Bool {
        // Get current user ID
        let session = try await supabaseService.getSession()
        let userId = session.user.id

        #if DEBUG
        print("🔄 NoteSyncManager: Starting note download for user: \(userId) with binary data: \(includeBinaryData)")
        #endif

        // Fetch notes from Supabase for the current user (excluding deleted notes) with network recovery
        let remoteNotes: [SimpleSupabaseNote] = try await networkRecoveryManager.executeWithRetry(
            operation: {
                try await self.supabaseService.fetch(
                    from: "notes",
                    filters: { query in
                        query.eq("user_id", value: userId.uuidString)
                             .is("deleted_at", value: nil)
                    }
                )
            },
            operationName: "Notes Download"
        )

        #if DEBUG
        print("🔄 NoteSyncManager: Found \(remoteNotes.count) remote notes")
        #endif

        // Update progress
        await MainActor.run {
            var progress = SyncProgress()
            progress.totalNotes = remoteNotes.count
            progress.downloadedNotes = 0
            updateProgress(progress)
        }

        // Use an actor-isolated counter to track success
        let successCounter = SuccessCounter()

        for (index, remoteNote) in remoteNotes.enumerated() {
            do {
                // Update progress status
                await MainActor.run {
                    var progress = SyncProgress()
                    progress.currentStatus = "Downloading note \(index + 1) of \(remoteNotes.count)"
                    updateProgress(progress)
                }

                #if DEBUG
                print("🔄 NoteSyncManager: Processing note \(remoteNote.id) - \(remoteNote.title)")
                #endif

                // Check if note exists locally and resolve conflicts
                let conflictResolved = try await resolveNoteConflict(remoteNote: remoteNote, context: context, includeBinaryData: includeBinaryData, updateProgress: updateProgress)

                if conflictResolved {
                    await successCounter.increment()
                    #if DEBUG
                    print("🔄 NoteSyncManager: Successfully processed note \(remoteNote.id)")
                    #endif
                } else {
                    #if DEBUG
                    print("🔄 NoteSyncManager: Failed to process note \(remoteNote.id)")
                    #endif
                }

                // Update progress
                let currentSuccessCount = await successCounter.getCount()
                await MainActor.run {
                    var progress = SyncProgress()
                    progress.downloadedNotes = currentSuccessCount
                    updateProgress(progress)
                }
            } catch {
                #if DEBUG
                print("🔄 NoteSyncManager: Error downloading note \(remoteNote.id): \(error.localizedDescription)")
                print("🔄 NoteSyncManager: Full error details: \(error)")
                #endif
                // Continue processing other notes even if one fails
            }
        }

        // Get final success count
        let finalSuccessCount = await successCounter.getCount()

        #if DEBUG
        print("🔄 NoteSyncManager: Note download completed. Downloaded \(finalSuccessCount) of \(remoteNotes.count) notes")
        #endif

        // Consider success if we processed any notes OR if there were no notes to process
        return finalSuccessCount > 0 || remoteNotes.isEmpty
    }

    // MARK: - Conflict Resolution Methods

    /// Resolve note conflict using "Last Write Wins" strategy
    /// - Parameters:
    ///   - remoteNote: The note from Supabase
    ///   - context: The NSManagedObjectContext
    ///   - includeBinaryData: Whether to include binary data in the resolution
    ///   - updateProgress: Closure to update sync progress
    /// - Returns: True if conflict was resolved successfully
    private func resolveNoteConflict(remoteNote: SimpleSupabaseNote, context: NSManagedObjectContext, includeBinaryData: Bool, updateProgress: @escaping (SyncProgress) -> Void) async throws -> Bool {
        // Skip deleted remote notes - they should not be downloaded
        if remoteNote.deletedAt != nil {
            #if DEBUG
            print("🔄 NoteSyncManager: Skipping deleted remote note \(remoteNote.id)")
            #endif
            return true
        }

        // Store the note ID for safe access across context operations
        let noteId = remoteNote.id

        // Perform all CoreData operations within a single context.perform block to avoid race conditions
        let (shouldUpdate, isNewNote) = try await context.perform {
            let request = NSFetchRequest<Note>(entityName: "Note")
            request.predicate = NSPredicate(format: "id == %@", noteId as CVarArg)
            request.fetchLimit = 1

            let existingNotes = try context.fetch(request)

            if let localNote = existingNotes.first {
                // Check if local note is deleted
                if localNote.deletedAt != nil {
                    #if DEBUG
                    print("🔄 NoteSyncManager: Local note \(noteId) is deleted, skipping remote update")
                    #endif
                    return (false, false) // Don't update deleted local notes
                }

                // Note exists locally - check for conflicts
                let localModified = localNote.lastModified ?? localNote.timestamp ?? Date.distantPast
                let remoteModified = remoteNote.lastModified

                #if DEBUG
                print("🔄 NoteSyncManager: Resolving note conflict - Local: \(localModified), Remote: \(remoteModified)")
                #endif

                // "Last Write Wins" strategy
                if remoteModified > localModified {
                    #if DEBUG
                    print("🔄 NoteSyncManager: Remote note \(noteId) is newer, will update local data")
                    #endif
                    return (true, false) // Existing note, should update, not new
                } else {
                    #if DEBUG
                    print("🔄 NoteSyncManager: Local note \(noteId) is newer, keeping local data")
                    #endif
                    return (false, false) // Existing note, no update needed, not new
                }
            } else {
                // Note doesn't exist locally - create new note with proper ID
                let newNote = Note(context: context)
                newNote.id = noteId  // Set the ID immediately to satisfy validation
                #if DEBUG
                print("🔄 NoteSyncManager: Creating new local note \(noteId)")
                #endif
                return (true, true) // New note, should update, is new
            }
        }

        // If we need to update the note, perform the update and save
        if shouldUpdate {
            // Find or create the note and update it
            let localNote = try await context.perform {
                let request = NSFetchRequest<Note>(entityName: "Note")
                request.predicate = NSPredicate(format: "id == %@", noteId as CVarArg)
                request.fetchLimit = 1

                let existingNotes = try context.fetch(request)

                if let existing = existingNotes.first {
                    return existing
                } else {
                    // Create new note if it doesn't exist
                    let newNote = Note(context: context)
                    newNote.id = noteId  // Set the ID immediately to satisfy validation
                    return newNote
                }
            }

            // Update the note with remote data (outside context.perform to allow async operations)
            try await updateLocalNoteFromRemote(localNote: localNote, remoteNote: remoteNote, context: context, includeBinaryData: includeBinaryData)

            // Save changes
            try await context.perform {
                if context.hasChanges {
                    do {
                        try context.save()
                        #if DEBUG
                        print("🔄 NoteSyncManager: Successfully saved note changes to CoreData")
                        #endif
                    } catch {
                        #if DEBUG
                        print("🔄 NoteSyncManager: Failed to save note changes to CoreData: \(error.localizedDescription)")
                        #endif
                        throw error
                    }
                }
            }

            // Update conflict counter if this was a conflict resolution (not a new note)
            if !isNewNote {
                await MainActor.run {
                    var progress = SyncProgress()
                    progress.resolvedConflicts = 1
                    updateProgress(progress)
                }
            }

            #if DEBUG
            print("🔄 NoteSyncManager: \(isNewNote ? "Created" : "Updated") local note \(noteId)")
            #endif
        }

        return true
    }

    /// Update local note with data from remote note
    /// - Parameters:
    ///   - localNote: The local CoreData note
    ///   - remoteNote: The remote Supabase note
    ///   - context: The NSManagedObjectContext
    ///   - includeBinaryData: Whether to include binary data in the update
    private func updateLocalNoteFromRemote(localNote: Note, remoteNote: SimpleSupabaseNote, context: NSManagedObjectContext, includeBinaryData: Bool) async throws {
        // Update basic metadata
        localNote.id = remoteNote.id
        localNote.title = remoteNote.title
        localNote.sourceType = remoteNote.sourceType
        localNote.timestamp = remoteNote.timestamp
        localNote.lastModified = remoteNote.lastModified
        localNote.isFavorite = remoteNote.isFavorite
        localNote.processingStatus = remoteNote.processingStatus
        localNote.keyPoints = remoteNote.keyPoints
        localNote.citations = remoteNote.citations
        localNote.duration = remoteNote.duration ?? 0.0 // Safely unwrap optional Double
        localNote.transcriptLanguage = remoteNote.languageCode
        localNote.tags = remoteNote.tags
        localNote.transcript = remoteNote.transcript
        localNote.videoId = remoteNote.videoId
        localNote.syncStatus = "synced"

        // Set source URL
        if let sourceURLString = remoteNote.sourceURL {
            localNote.sourceURL = URL(string: sourceURLString)
        }

        // Handle folder relationship
        if let folderId = remoteNote.folderId {
            let folderRequest = NSFetchRequest<Folder>(entityName: "Folder")
            folderRequest.predicate = NSPredicate(format: "id == %@", folderId as CVarArg)
            folderRequest.fetchLimit = 1

            let folders = try context.fetch(folderRequest)
            localNote.folder = folders.first
        }

        // Handle binary data if requested and available
        if includeBinaryData {
            try await downloadNoteBinaryData(for: localNote, remoteNoteId: remoteNote.id)
        }

        // Ensure the note has at least some content for HomeViewModel validation
        // If no originalContent was downloaded, create a placeholder from the title
        if localNote.originalContent == nil {
            let placeholderContent = localNote.title ?? "Downloaded Note"
            localNote.originalContent = placeholderContent.data(using: .utf8)

            #if DEBUG
            print("🔄 NoteSyncManager: Created placeholder content for note \(remoteNote.id)")
            #endif
        }
    }

    /// Download binary data for a note from Supabase
    /// - Parameters:
    ///   - localNote: The local CoreData note to update
    ///   - remoteNoteId: The ID of the remote note
    private func downloadNoteBinaryData(for localNote: Note, remoteNoteId: UUID) async throws {
        // Fetch the full note with binary data from Supabase using direct bytea format with network recovery
        let fullNotes: [SupabaseNote] = try await networkRecoveryManager.executeWithRetry(
            operation: {
                try await self.supabaseService.fetch(
                    from: "notes",
                    filters: { query in
                        query.eq("id", value: remoteNoteId.uuidString)
                    }
                )
            },
            operationName: "Binary Data Download (\(remoteNoteId))"
        )

        guard let fullNote = fullNotes.first else {
            #if DEBUG
            print("🔄 NoteSyncManager: No full note found for binary data download for note \(remoteNoteId)")
            #endif
            return
        }

        #if DEBUG
        print("🔄 NoteSyncManager: Found full note for binary data download (direct bytea format)")
        #endif

        // Directly assign binary data from bytea columns (no encoding/decoding needed)
        if let originalContentData = fullNote.originalContent {
            localNote.originalContent = originalContentData

            #if DEBUG
            let sizeInMB = originalContentData.sizeInMB()
            print("🔄 NoteSyncManager: Downloaded originalContent (\(String(format: "%.2f", sizeInMB)) MB) from bytea")
            #endif
        } else {
            #if DEBUG
            print("🔄 NoteSyncManager: No originalContent binary data found for note \(remoteNoteId)")
            #endif
        }

        if let aiGeneratedContentData = fullNote.aiGeneratedContent {
            localNote.aiGeneratedContent = aiGeneratedContentData

            #if DEBUG
            let sizeInMB = aiGeneratedContentData.sizeInMB()
            print("🔄 NoteSyncManager: Downloaded aiGeneratedContent (\(String(format: "%.2f", sizeInMB)) MB) from bytea")
            #endif
        }

        if let sectionsData = fullNote.sections {
            localNote.sections = sectionsData

            #if DEBUG
            let sizeInMB = sectionsData.sizeInMB()
            print("🔄 NoteSyncManager: Downloaded sections (\(String(format: "%.2f", sizeInMB)) MB) from bytea")
            #endif
        }

        if let supplementaryMaterialsData = fullNote.supplementaryMaterials {
            localNote.supplementaryMaterials = supplementaryMaterialsData

            #if DEBUG
            let sizeInMB = supplementaryMaterialsData.sizeInMB()
            print("🔄 NoteSyncManager: Downloaded supplementaryMaterials (\(String(format: "%.2f", sizeInMB)) MB) from bytea")
            #endif
        }

        if let mindMapData = fullNote.mindMap {
            localNote.mindMap = mindMapData

            #if DEBUG
            let sizeInMB = mindMapData.sizeInMB()
            print("🔄 NoteSyncManager: Downloaded mindMap (\(String(format: "%.2f", sizeInMB)) MB) from bytea")
            #endif
        }
    }

    /// Placeholder for deleteNoteFromSupabase - will be implemented in Phase 4
    private func deleteNoteFromSupabase(note: Note, userId: UUID, context: NSManagedObjectContext) async throws {
        // TODO: Implement in Phase 4
        fatalError("deleteNoteFromSupabase not yet implemented")
    }
}
