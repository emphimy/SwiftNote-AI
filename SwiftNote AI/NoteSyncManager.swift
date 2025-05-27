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

    /// Placeholder for syncNoteWithBinaryData - will be implemented in Phase 2
    private func syncNoteWithBinaryData(note: Note, userId: UUID, context: NSManagedObjectContext) async throws {
        // TODO: Implement in Phase 2
        fatalError("syncNoteWithBinaryData not yet implemented")
    }

    /// Placeholder for deleteNoteFromSupabase - will be implemented in Phase 4
    private func deleteNoteFromSupabase(note: Note, userId: UUID, context: NSManagedObjectContext) async throws {
        // TODO: Implement in Phase 4
        fatalError("deleteNoteFromSupabase not yet implemented")
    }
}
