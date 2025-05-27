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

    /// Sync operation lock to prevent concurrent sync operations
    private var isSyncInProgress = false

    /// Lock queue for thread-safe access to sync state
    private let syncLockQueue = DispatchQueue(label: "com.swiftnote.sync.lock", qos: .userInitiated)

    /// Transaction manager for atomic sync operations
    private let transactionManager = SyncTransactionManager()

    /// Background queue for sync operations to prevent UI blocking
    private let syncQueue = DispatchQueue(label: "com.swiftnote.sync.background", qos: .userInitiated)

    /// Progress update queue for batching UI updates
    private let progressQueue = DispatchQueue(label: "com.swiftnote.sync.progress", qos: .utility)

    /// Progress update coordinator for efficient UI updates
    private let progressCoordinator = ProgressUpdateCoordinator()

    /// Network failure recovery manager
    private let networkRecoveryManager = NetworkRecoveryManager()

    /// Folder sync manager for folder-related operations
    private lazy var folderSyncManager = FolderSyncManager(
        supabaseService: supabaseService,
        transactionManager: transactionManager,
        networkRecoveryManager: networkRecoveryManager,
        progressCoordinator: progressCoordinator
    )

    /// Note sync manager for note-related operations
    private lazy var noteSyncManager = NoteSyncManager(
        supabaseService: supabaseService,
        transactionManager: transactionManager,
        networkRecoveryManager: networkRecoveryManager,
        progressCoordinator: progressCoordinator
    )

    // MARK: - Initialization
    private init() {
        #if DEBUG
        print("🔄 SupabaseSyncService: Initializing")
        #endif
    }

    // MARK: - Public Methods

    /// Sync progress publisher
    @Published var syncProgress = SyncProgress()

    // MARK: - Sync Lock Management

    /// Check if a sync operation is currently in progress
    /// - Returns: True if sync is in progress, false otherwise
    func isSyncLocked() -> Bool {
        return syncLockQueue.sync {
            return isSyncInProgress
        }
    }

    /// Attempt to acquire the sync lock
    /// - Returns: True if lock was acquired, false if sync is already in progress
    private func acquireSyncLock() -> Bool {
        return syncLockQueue.sync {
            if isSyncInProgress {
                #if DEBUG
                print("🔒 SupabaseSyncService: Sync lock acquisition failed - sync already in progress")
                #endif
                return false
            } else {
                isSyncInProgress = true
                #if DEBUG
                print("🔒 SupabaseSyncService: Sync lock acquired successfully")
                #endif
                return true
            }
        }
    }

    /// Release the sync lock
    private func releaseSyncLock() {
        syncLockQueue.sync {
            isSyncInProgress = false
            #if DEBUG
            print("🔒 SupabaseSyncService: Sync lock released")
            #endif
        }
    }

    /// Sync folders and notes between CoreData and Supabase (bidirectional)
    /// - Parameters:
    ///   - context: The NSManagedObjectContext to fetch data from
    ///   - includeBinaryData: Whether to include binary data in the sync (default: false)
    ///   - twoWaySync: Whether to perform bidirectional sync (default: true)
    ///   - completion: Completion handler with success flag and optional error
    func syncToSupabase(context: NSManagedObjectContext, includeBinaryData: Bool = false, twoWaySync: Bool = true, completion: @escaping (Bool, Error?) -> Void) {
        // Check if sync lock can be acquired
        guard acquireSyncLock() else {
            let error = NSError(domain: "SupabaseSyncService", code: 409, userInfo: [
                NSLocalizedDescriptionKey: "Sync operation already in progress. Please wait for the current sync to complete."
            ])
            #if DEBUG
            print("🔒 SupabaseSyncService: Sync request rejected - another sync operation is already in progress")
            #endif
            completion(false, error)
            return
        }

        // Dispatch sync operation to background queue to prevent UI blocking
        syncQueue.async { [weak self] in
            guard let self = self else {
                self?.releaseSyncLock()
                completion(false, NSError(domain: "SupabaseSyncService", code: 500, userInfo: [
                    NSLocalizedDescriptionKey: "Sync service was deallocated"
                ]))
                return
            }

            // Create background task to ensure sync completes even if app goes to background
            let backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "SupabaseSync") {
                #if DEBUG
                print("🔄 SupabaseSyncService: Background task expired, sync may be incomplete")
                #endif
            }

            defer {
                self.releaseSyncLock()
                if backgroundTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                }
            }

            Task {
                await self.performBackgroundSync(
                    context: context,
                    includeBinaryData: includeBinaryData,
                    twoWaySync: twoWaySync,
                    completion: completion
                )
            }
        }
    }

    /// Perform the actual sync operation on background thread
    /// - Parameters:
    ///   - context: The NSManagedObjectContext to fetch data from
    ///   - includeBinaryData: Whether to include binary data in the sync
    ///   - twoWaySync: Whether to perform bidirectional sync
    ///   - completion: Completion handler with success flag and optional error
    private func performBackgroundSync(context: NSManagedObjectContext, includeBinaryData: Bool, twoWaySync: Bool, completion: @escaping (Bool, Error?) -> Void) async {
        do {
            // Reset sync progress on main thread
            await MainActor.run {
                syncProgress = SyncProgress()
                syncProgress.includeBinaryData = includeBinaryData
                syncProgress.isTwoWaySync = twoWaySync
                syncProgress.currentStatus = "Checking authentication..."
            }

            // Validate token and refresh if necessary
            await MainActor.run {
                syncProgress.currentStatus = "Validating authentication..."
            }

            do {
                _ = try await networkRecoveryManager.executeWithRetry(
                    operation: {
                        try await self.supabaseService.validateAndRefreshTokenIfNeeded()
                    },
                    operationName: "Token Validation"
                )
                #if DEBUG
                print("🔄 SupabaseSyncService: Token validation successful")
                #endif
            } catch {
                #if DEBUG
                print("🔄 SupabaseSyncService: Token validation failed after retries: \(error)")
                #endif

                await MainActor.run {
                    syncProgress.currentStatus = "Authentication failed"
                }

                DispatchQueue.main.async {
                    completion(false, error)
                }
                return
            }

            // Begin atomic transaction for sync operations
            await MainActor.run {
                syncProgress.currentStatus = "Starting sync transaction..."
            }

            let transactionContext = try transactionManager.beginTransaction()

            #if DEBUG
            print("🔄 SupabaseSyncService: Sync transaction started")
            #endif

            #if DEBUG
            print("🔄 SupabaseSyncService: Starting \(twoWaySync ? "two-way" : "one-way") sync")
            #endif

            // Wrap sync operations in transaction with proper error handling
            var overallSuccess = false

            do {
                if twoWaySync {
                    // Phase 1: Upload local changes to Supabase
                    await MainActor.run {
                        syncProgress.currentStatus = "Uploading local changes..."
                    }

                    transactionManager.addCheckpoint("upload_phase_start")

                    #if DEBUG
                    print("🔄 SupabaseSyncService: Starting upload phase")
                    #endif

                    let uploadFolderSuccess = try await folderSyncManager.syncFoldersToSupabase(context: transactionContext) { [weak self] progress in
                        self?.syncProgress.totalFolders = progress.totalFolders
                        self?.syncProgress.syncedFolders = progress.syncedFolders
                        if !progress.currentStatus.isEmpty {
                            self?.syncProgress.currentStatus = progress.currentStatus
                        }
                    }
                    transactionManager.addCheckpoint("folders_uploaded")

                    let uploadNoteSuccess = try await noteSyncManager.syncNotesToSupabase(context: transactionContext, includeBinaryData: includeBinaryData) { [weak self] progress in
                        self?.syncProgress.totalNotes = progress.totalNotes
                        self?.syncProgress.syncedNotes = progress.syncedNotes
                        if !progress.currentStatus.isEmpty {
                            self?.syncProgress.currentStatus = progress.currentStatus
                        }
                    }
                    transactionManager.addCheckpoint("notes_uploaded")

                    #if DEBUG
                    print("🔄 SupabaseSyncService: Upload phase completed - Folders: \(uploadFolderSuccess), Notes: \(uploadNoteSuccess)")
                    #endif

                    // Phase 2: Download remote changes from Supabase
                    await MainActor.run {
                        syncProgress.isDownloadPhase = true
                        syncProgress.currentStatus = "Downloading remote changes..."
                    }

                    transactionManager.addCheckpoint("download_phase_start")

                    #if DEBUG
                    print("🔄 SupabaseSyncService: Starting download phase")
                    #endif

                    let downloadFolderSuccess = try await folderSyncManager.downloadFoldersFromSupabase(context: transactionContext) { [weak self] progress in
                        self?.syncProgress.totalFolders = max(self?.syncProgress.totalFolders ?? 0, progress.totalFolders)
                        self?.syncProgress.downloadedFolders = progress.downloadedFolders
                        self?.syncProgress.resolvedConflicts += progress.resolvedConflicts
                        if !progress.currentStatus.isEmpty {
                            self?.syncProgress.currentStatus = progress.currentStatus
                        }
                    }
                    transactionManager.addCheckpoint("folders_downloaded")

                    let downloadNoteSuccess = try await noteSyncManager.downloadNotesFromSupabase(context: transactionContext, includeBinaryData: includeBinaryData) { [weak self] progress in
                        self?.syncProgress.totalNotes = max(self?.syncProgress.totalNotes ?? 0, progress.totalNotes)
                        self?.syncProgress.downloadedNotes = progress.downloadedNotes
                        self?.syncProgress.resolvedConflicts += progress.resolvedConflicts
                        if !progress.currentStatus.isEmpty {
                            self?.syncProgress.currentStatus = progress.currentStatus
                        }
                    }
                    transactionManager.addCheckpoint("notes_downloaded")

                    #if DEBUG
                    print("🔄 SupabaseSyncService: Download phase completed - Folders: \(downloadFolderSuccess), Notes: \(downloadNoteSuccess)")
                    #endif

                    // For fresh installs, download success is more important than upload success
                    // Success if either upload worked OR download worked (not both required)
                    overallSuccess = uploadFolderSuccess || uploadNoteSuccess || downloadFolderSuccess || downloadNoteSuccess

                    #if DEBUG
                    print("🔄 SupabaseSyncService: Two-way sync overall success: \(overallSuccess)")
                    #endif

                    // Clean up items that were successfully deleted from Supabase
                    try await cleanupDeletedItems(context: transactionContext)
                    transactionManager.addCheckpoint("cleanup_deleted_items")

                    // Clean up any invalid default folders
                    try await folderSyncManager.cleanupInvalidFolders(context: transactionContext)
                    transactionManager.addCheckpoint("cleanup_invalid_folders")
                } else {
                    // One-way sync (upload only) - maintain backward compatibility
                    await MainActor.run {
                        syncProgress.currentStatus = "Syncing folders..."
                    }

                    transactionManager.addCheckpoint("one_way_sync_start")

                    let folderSuccess = try await folderSyncManager.syncFoldersToSupabase(context: transactionContext) { [weak self] progress in
                        self?.syncProgress.totalFolders = progress.totalFolders
                        self?.syncProgress.syncedFolders = progress.syncedFolders
                        if !progress.currentStatus.isEmpty {
                            self?.syncProgress.currentStatus = progress.currentStatus
                        }
                    }
                    transactionManager.addCheckpoint("one_way_folders_synced")

                    await MainActor.run {
                        syncProgress.currentStatus = "Syncing notes..."
                    }

                    let noteSuccess = try await noteSyncManager.syncNotesToSupabase(context: transactionContext, includeBinaryData: includeBinaryData) { [weak self] progress in
                        self?.syncProgress.totalNotes = progress.totalNotes
                        self?.syncProgress.syncedNotes = progress.syncedNotes
                        if !progress.currentStatus.isEmpty {
                            self?.syncProgress.currentStatus = progress.currentStatus
                        }
                    }
                    transactionManager.addCheckpoint("one_way_notes_synced")

                    overallSuccess = folderSuccess || noteSuccess

                    // Clean up items that were successfully deleted from Supabase
                    try await cleanupDeletedItems(context: transactionContext)
                    transactionManager.addCheckpoint("one_way_cleanup_deleted")

                    // Clean up any invalid default folders
                    try await folderSyncManager.cleanupInvalidFolders(context: transactionContext)
                    transactionManager.addCheckpoint("one_way_cleanup_invalid")
                }

                // Mark transaction as having changes if any operations succeeded
                if overallSuccess {
                    transactionManager.markChanges()
                }

                // Commit the transaction
                try transactionManager.commitTransaction()
                transactionManager.addCheckpoint("transaction_committed")

                #if DEBUG
                print("🔄 SupabaseSyncService: Transaction committed successfully")
                #endif

            } catch {
                // Rollback transaction on any error
                transactionManager.rollbackTransaction()

                #if DEBUG
                print("🔄 SupabaseSyncService: Transaction rolled back due to error: \(error)")
                #endif

                throw error
            }

            // Update last sync time in UserDefaults
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastSupabaseSyncDate")

            await MainActor.run {
                syncProgress.currentStatus = twoWaySync ? "Two-way sync completed" : "Upload completed"
            }

            #if DEBUG
            print("🔄 SupabaseSyncService: Sync process completed successfully")
            print("🔄 SupabaseSyncService: Final sync progress - Folders: \(syncProgress.syncedFolders)/\(syncProgress.totalFolders), Notes: \(syncProgress.syncedNotes)/\(syncProgress.totalNotes)")
            if twoWaySync {
                print("🔄 SupabaseSyncService: Downloaded - Folders: \(syncProgress.downloadedFolders), Notes: \(syncProgress.downloadedNotes)")
                print("🔄 SupabaseSyncService: Resolved conflicts: \(syncProgress.resolvedConflicts)")
            }
            #endif

            // Call completion handler on main thread
            DispatchQueue.main.async {
                completion(overallSuccess, nil)
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









    /// Delete a note from Supabase
    /// - Parameters:
    ///   - note: The CoreData Note to delete
    ///   - userId: The Supabase user ID
    ///   - context: The NSManagedObjectContext
    private func deleteNoteFromSupabase(note: Note, userId: UUID, context: NSManagedObjectContext) async throws {
        guard let noteId = note.id else {
            #if DEBUG
            print("🔄 SupabaseSyncService: Cannot delete note - missing ID")
            #endif
            return
        }

        #if DEBUG
        print("🔄 SupabaseSyncService: Deleting note from Supabase: \(noteId)")
        #endif

        // Delete the note from Supabase with network recovery
        _ = try await networkRecoveryManager.executeWithRetry(
            operation: {
                try await self.supabaseService.client.from("notes")
                    .delete()
                    .eq("id", value: noteId.uuidString)
                    .eq("user_id", value: userId.uuidString) // Security: ensure user can only delete their own notes
                    .execute()
            },
            operationName: "Note Delete (\(noteId))"
        )

        #if DEBUG
        print("🔄 SupabaseSyncService: Successfully deleted note from Supabase: \(noteId)")
        #endif

        // After successful deletion from Supabase, mark for permanent deletion
        // We'll delete it from CoreData after the sync loop completes to avoid threading issues
        try await context.perform {
            // Delete associated files if they exist
            if let sourceURL = note.sourceURL {
                do {
                    if FileManager.default.fileExists(atPath: sourceURL.path) {
                        try FileManager.default.removeItem(at: sourceURL)
                        #if DEBUG
                        print("🔄 SupabaseSyncService: Deleted associated file for note \(noteId)")
                        #endif
                    }
                } catch {
                    #if DEBUG
                    print("🔄 SupabaseSyncService: Error deleting associated file - \(error)")
                    #endif
                }
            }

            // Mark the note as successfully deleted from Supabase
            // We'll permanently delete it after the sync loop to avoid threading issues
            note.syncStatus = "deleted_from_supabase"

            if context.hasChanges {
                try context.save()
                #if DEBUG
                print("🔄 SupabaseSyncService: Marked note as deleted from Supabase: \(noteId)")
                #endif
            }
        }
    }



    /// Clean up items that were successfully deleted from Supabase
    /// - Parameter context: The NSManagedObjectContext
    private func cleanupDeletedItems(context: NSManagedObjectContext) async throws {
        #if DEBUG
        print("🔄 SupabaseSyncService: Starting cleanup of deleted items")
        #endif

        // Clean up notes marked as deleted from Supabase
        await context.perform {
            let noteRequest = NSFetchRequest<Note>(entityName: "Note")
            noteRequest.predicate = NSPredicate(format: "syncStatus == %@", "deleted_from_supabase")

            do {
                let deletedNotes = try context.fetch(noteRequest)

                #if DEBUG
                print("🔄 SupabaseSyncService: Found \(deletedNotes.count) notes to permanently delete")
                #endif

                for note in deletedNotes {
                    context.delete(note)
                }

                // Save changes if any
                if context.hasChanges {
                    try context.save()
                    #if DEBUG
                    print("🔄 SupabaseSyncService: Successfully cleaned up deleted notes")
                    #endif
                }
            } catch {
                #if DEBUG
                print("🔄 SupabaseSyncService: Error fetching deleted notes - \(error)")
                #endif
            }
        }

        // Clean up folders marked as deleted from Supabase using FolderSyncManager
        try await folderSyncManager.cleanupDeletedFolders(context: context)
    }



    // MARK: - Private Methods



















    /// Fix existing notes and folders in Supabase that have incorrect sync_status = "pending"
    /// This utility method updates remote records to have sync_status = "synced"
    /// - Returns: Tuple with (notes fixed, folders fixed)
    func fixRemoteSyncStatus() async throws -> (notesFix: Int, foldersFix: Int) {
        // Get current user ID
        let session = try await supabaseService.getSession()
        let userId = session.user.id

        #if DEBUG
        print("🔧 SupabaseSyncService: Starting remote sync status fix for user: \(userId)")
        #endif

        var notesFixed = 0
        var foldersFixed = 0

        // Fix notes with sync_status = "pending" in Supabase with network recovery
        do {
            let response = try await networkRecoveryManager.executeWithRetry(
                operation: {
                    try await self.supabaseService.client.from("notes")
                        .update(["sync_status": "synced"])
                        .eq("user_id", value: userId.uuidString)
                        .eq("sync_status", value: "pending")
                        .execute()
                },
                operationName: "Fix Notes Sync Status"
            )

            // Parse the response to count affected rows
            if let jsonArray = try? JSONSerialization.jsonObject(with: response.data) as? [[String: Any]] {
                notesFixed = jsonArray.count
            }

            #if DEBUG
            print("🔧 SupabaseSyncService: Fixed \(notesFixed) notes in Supabase")
            #endif
        } catch {
            #if DEBUG
            print("🔧 SupabaseSyncService: Error fixing notes in Supabase: \(error)")
            #endif
        }

        // Fix folders with sync_status = "pending" in Supabase using FolderSyncManager
        foldersFixed = try await folderSyncManager.fixPendingFoldersInSupabase()

        #if DEBUG
        print("🔧 SupabaseSyncService: Remote sync status fix completed - Notes: \(notesFixed), Folders: \(foldersFixed)")
        #endif

        return (notesFix: notesFixed, foldersFix: foldersFixed)
    }

    /// Fix existing audio notes that may have incorrect syncStatus
    /// This utility method marks audio notes with "synced" status as "pending" for sync
    /// - Parameter context: The NSManagedObjectContext to update notes in
    /// - Returns: Number of notes that were fixed
    func fixAudioNoteSyncStatus(context: NSManagedObjectContext) async throws -> Int {
        return try await context.perform {
            let request = NSFetchRequest<Note>(entityName: "Note")

            // Find audio notes (recording or audio sourceType) that are marked as "synced"
            // but may have been created before the syncStatus fix
            request.predicate = NSPredicate(format: "(sourceType == %@ OR sourceType == %@) AND syncStatus == %@",
                                          "recording", "audio", "synced")

            let audioNotes = try context.fetch(request)

            #if DEBUG
            print("🔧 SupabaseSyncService: Found \(audioNotes.count) audio notes with 'synced' status to potentially fix")
            #endif

            var fixedCount = 0

            for note in audioNotes {
                // Mark the note for sync
                note.syncStatus = "pending"
                fixedCount += 1

                #if DEBUG
                print("🔧 SupabaseSyncService: Fixed sync status for audio note: \(note.title ?? "Untitled")")
                #endif
            }

            if context.hasChanges {
                try context.save()
                #if DEBUG
                print("🔧 SupabaseSyncService: Successfully fixed \(fixedCount) audio notes")
                #endif
            }

            return fixedCount
        }
    }

    // MARK: - Download Methods (Phase 4: Two-Way Sync)

    /// Download folders from Supabase to CoreData
    /// - Parameter context: The NSManagedObjectContext to save folders to
    /// - Returns: Success flag
    private func downloadFoldersFromSupabase(context: NSManagedObjectContext) async throws -> Bool {
        // Get current user ID
        let session = try await supabaseService.getSession()
        let userId = session.user.id

        #if DEBUG
        print("🔄 SupabaseSyncService: Starting folder download for user: \(userId)")
        #endif

        // Fetch folders from Supabase for the current user with network recovery
        let remoteFolders: [SimpleSupabaseFolder] = try await networkRecoveryManager.executeWithRetry(
            operation: {
                try await self.supabaseService.fetch(
                    from: "folders",
                    filters: { query in
                        query.eq("user_id", value: userId.uuidString)
                    }
                )
            },
            operationName: "Folder Download"
        )

        #if DEBUG
        print("🔄 SupabaseSyncService: Found \(remoteFolders.count) remote folders")
        #endif

        // Update progress
        await MainActor.run {
            syncProgress.totalFolders = max(syncProgress.totalFolders, remoteFolders.count)
            syncProgress.downloadedFolders = 0
        }

        // Use an actor-isolated counter to track success

        let successCounter = SuccessCounter()

        for (index, remoteFolder) in remoteFolders.enumerated() {
            do {
                // Update progress status
                await MainActor.run {
                    syncProgress.currentStatus = "Downloading folder \(index + 1) of \(remoteFolders.count)"
                }

                #if DEBUG
                print("🔄 SupabaseSyncService: Processing folder \(remoteFolder.id) - \(remoteFolder.name)")
                #endif

                // Check if folder exists locally and resolve conflicts
                let conflictResolved = try await resolveFolderConflict(remoteFolder: remoteFolder, context: context)

                if conflictResolved {
                    await successCounter.increment()
                    #if DEBUG
                    print("🔄 SupabaseSyncService: Successfully processed folder \(remoteFolder.id)")
                    #endif
                } else {
                    #if DEBUG
                    print("🔄 SupabaseSyncService: Failed to process folder \(remoteFolder.id)")
                    #endif
                }

                // Update progress
                let currentSuccessCount = await successCounter.getCount()
                await MainActor.run {
                    syncProgress.downloadedFolders = currentSuccessCount
                }
            } catch {
                #if DEBUG
                print("🔄 SupabaseSyncService: Error downloading folder \(remoteFolder.id): \(error.localizedDescription)")
                print("🔄 SupabaseSyncService: Full error details: \(error)")
                #endif
                // Continue processing other folders even if one fails
            }
        }

        // Get final success count
        let finalSuccessCount = await successCounter.getCount()

        #if DEBUG
        print("🔄 SupabaseSyncService: Folder download completed. Downloaded \(finalSuccessCount) of \(remoteFolders.count) folders")
        #endif

        // Consider success if we processed any folders OR if there were no folders to process
        return finalSuccessCount > 0 || remoteFolders.isEmpty
    }



    // MARK: - Conflict Resolution Methods (Phase 4: Two-Way Sync)

    /// Resolve folder conflict using "Last Write Wins" strategy
    /// - Parameters:
    ///   - remoteFolder: The folder from Supabase
    ///   - context: The NSManagedObjectContext
    /// - Returns: True if conflict was resolved successfully
    private func resolveFolderConflict(remoteFolder: SimpleSupabaseFolder, context: NSManagedObjectContext) async throws -> Bool {
        // Perform CoreData operations synchronously
        let (shouldUpdateConflictCounter, wasUpdated) = try await context.perform {
            let request = NSFetchRequest<Folder>(entityName: "Folder")
            request.predicate = NSPredicate(format: "id == %@", remoteFolder.id as CVarArg)
            request.fetchLimit = 1

            let existingFolders = try context.fetch(request)

            if let localFolder = existingFolders.first {
                // Folder exists locally - check for conflicts
                let localModified = localFolder.updatedAt ?? localFolder.timestamp ?? Date.distantPast
                let remoteModified = remoteFolder.updatedAt ?? remoteFolder.timestamp

                #if DEBUG
                print("🔄 SupabaseSyncService: Resolving folder conflict - Local: \(localModified), Remote: \(remoteModified)")
                #endif

                // "Last Write Wins" strategy
                if remoteModified > localModified {
                    // Remote is newer - update local folder
                    self.updateLocalFolderFromRemote(localFolder: localFolder, remoteFolder: remoteFolder)

                    #if DEBUG
                    print("🔄 SupabaseSyncService: Updated local folder \(remoteFolder.id) with remote data")
                    #endif

                    return (true, true) // Should update conflict counter, was updated
                } else {
                    #if DEBUG
                    print("🔄 SupabaseSyncService: Local folder \(remoteFolder.id) is newer, keeping local data")
                    #endif
                    return (false, false) // No conflict counter update, not updated
                }
            } else {
                // Folder doesn't exist locally - create new folder
                let newFolder = Folder(context: context)
                self.updateLocalFolderFromRemote(localFolder: newFolder, remoteFolder: remoteFolder)

                #if DEBUG
                print("🔄 SupabaseSyncService: Created new local folder \(remoteFolder.id)")
                #endif
                return (false, true) // No conflict (new folder), was created
            }
        }

        // Save changes if needed
        if wasUpdated {
            try await context.perform {
                if context.hasChanges {
                    do {
                        try context.save()
                        #if DEBUG
                        print("🔄 SupabaseSyncService: Successfully saved folder changes to CoreData")
                        #endif
                    } catch {
                        #if DEBUG
                        print("🔄 SupabaseSyncService: Failed to save folder changes to CoreData: \(error.localizedDescription)")
                        #endif
                        throw error
                    }
                }
            }
        }

        // Update conflict counter on main actor if needed
        if shouldUpdateConflictCounter {
            await MainActor.run {
                syncProgress.resolvedConflicts += 1
            }
        }

        return true
    }



    /// Update local folder with data from remote folder
    /// - Parameters:
    ///   - localFolder: The local CoreData folder
    ///   - remoteFolder: The remote Supabase folder
    private func updateLocalFolderFromRemote(localFolder: Folder, remoteFolder: SimpleSupabaseFolder) {
        localFolder.id = remoteFolder.id
        localFolder.name = remoteFolder.name
        localFolder.color = remoteFolder.color
        localFolder.timestamp = remoteFolder.timestamp
        localFolder.sortOrder = remoteFolder.sortOrder
        localFolder.updatedAt = remoteFolder.updatedAt ?? Date()
        localFolder.syncStatus = "synced"
        localFolder.deletedAt = remoteFolder.deletedAt
    }







    // MARK: - Cleanup Methods

    /// Clean up old deleted notes (permanently delete notes that have been soft-deleted for more than 30 days)
    /// - Parameter context: The NSManagedObjectContext
    func cleanupOldDeletedNotes(context: NSManagedObjectContext) async throws {
        #if DEBUG
        print("🔄 SupabaseSyncService: Starting cleanup of old deleted notes")
        #endif

        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()

        try await context.perform {
            let request = NSFetchRequest<Note>(entityName: "Note")
            request.predicate = NSPredicate(format: "deletedAt != nil AND deletedAt < %@", thirtyDaysAgo as CVarArg)

            do {
                let oldDeletedNotes = try context.fetch(request)

                #if DEBUG
                print("🔄 SupabaseSyncService: Found \(oldDeletedNotes.count) old deleted notes to permanently delete")
                #endif

                for note in oldDeletedNotes {
                    // Delete associated files if they exist
                    if let sourceURL = note.sourceURL {
                        do {
                            if FileManager.default.fileExists(atPath: sourceURL.path) {
                                try FileManager.default.removeItem(at: sourceURL)
                                #if DEBUG
                                print("🔄 SupabaseSyncService: Deleted associated file for note \(note.id?.uuidString ?? "unknown")")
                                #endif
                            }
                        } catch {
                            #if DEBUG
                            print("🔄 SupabaseSyncService: Error deleting associated file - \(error)")
                            #endif
                        }
                    }

                    context.delete(note)
                }

                if context.hasChanges {
                    try context.save()
                    #if DEBUG
                    print("🔄 SupabaseSyncService: Successfully cleaned up \(oldDeletedNotes.count) old deleted notes")
                    #endif
                }
            } catch {
                #if DEBUG
                print("🔄 SupabaseSyncService: Error during cleanup - \(error)")
                #endif
                throw error
            }
        }
    }
}
