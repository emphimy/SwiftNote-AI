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

                    let uploadFolderSuccess = try await syncFoldersToSupabase(context: transactionContext)
                    transactionManager.addCheckpoint("folders_uploaded")

                    let uploadNoteSuccess = try await syncNotesToSupabase(context: transactionContext, includeBinaryData: includeBinaryData)
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

                    let downloadFolderSuccess = try await downloadFoldersFromSupabase(context: transactionContext)
                    transactionManager.addCheckpoint("folders_downloaded")

                    let downloadNoteSuccess = try await downloadNotesFromSupabase(context: transactionContext, includeBinaryData: includeBinaryData)
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
                    try await cleanupInvalidFolders(context: transactionContext)
                    transactionManager.addCheckpoint("cleanup_invalid_folders")
                } else {
                    // One-way sync (upload only) - maintain backward compatibility
                    await MainActor.run {
                        syncProgress.currentStatus = "Syncing folders..."
                    }

                    transactionManager.addCheckpoint("one_way_sync_start")

                    let folderSuccess = try await syncFoldersToSupabase(context: transactionContext)
                    transactionManager.addCheckpoint("one_way_folders_synced")

                    await MainActor.run {
                        syncProgress.currentStatus = "Syncing notes..."
                    }

                    let noteSuccess = try await syncNotesToSupabase(context: transactionContext, includeBinaryData: includeBinaryData)
                    transactionManager.addCheckpoint("one_way_notes_synced")

                    overallSuccess = folderSuccess || noteSuccess

                    // Clean up items that were successfully deleted from Supabase
                    try await cleanupDeletedItems(context: transactionContext)
                    transactionManager.addCheckpoint("one_way_cleanup_deleted")

                    // Clean up any invalid default folders
                    try await cleanupInvalidFolders(context: transactionContext)
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
                // Update progress status with throttling
                progressCoordinator.scheduleUpdate { [weak self] in
                    self?.syncProgress.currentStatus = "Syncing folder \(index + 1) of \(folders.count)"
                }

                // Skip folders with invalid/default values that shouldn't be synced
                if let folderName = folder.name,
                   folderName == "Untitled Folder" && folder.color == "blue" && folder.notes?.count == 0 {
                    #if DEBUG
                    print("🔄 SupabaseSyncService: Skipping empty default folder: \(folder.id?.uuidString ?? "unknown")")
                    #endif

                    // Mark as synced to prevent future sync attempts
                    await updateFolderSyncStatus(folderId: folder.id ?? UUID(), status: "synced", context: context)
                    continue
                }

                // Check if this is a deleted folder that needs to be removed from Supabase
                if folder.deletedAt != nil {
                    // Delete the folder from Supabase
                    try await deleteFolderFromSupabase(folder: folder, userId: userId, context: context)
                } else {
                    // Create a simplified folder with metadata fields
                    let metadataFolder = SimpleSupabaseFolder(
                        id: folder.id ?? UUID(),
                        name: folder.name ?? "Untitled Folder",
                        color: folder.color ?? "blue",
                        timestamp: folder.timestamp ?? Date(),
                        sortOrder: folder.sortOrder,
                        userId: userId,
                        updatedAt: folder.updatedAt,
                        syncStatus: "synced", // Mark as synced in remote database
                        deletedAt: folder.deletedAt
                    )

                    // Check if folder already exists in Supabase with network recovery
                    let existingFolders: [SimpleSupabaseFolder] = try await networkRecoveryManager.executeWithRetry(
                        operation: {
                            try await self.supabaseService.fetch(
                                from: "folders",
                                filters: { query in
                                    query.eq("id", value: metadataFolder.id.uuidString)
                                }
                            )
                        },
                        operationName: "Folder Existence Check (\(metadataFolder.name))"
                    )

                    if existingFolders.isEmpty {
                        // Insert new folder with network recovery
                        _ = try await networkRecoveryManager.executeWithRetry(
                            operation: {
                                try await self.supabaseService.client.from("folders")
                                    .insert(metadataFolder)
                                    .execute()
                            },
                            operationName: "Folder Insert (\(metadataFolder.name))"
                        )

                        #if DEBUG
                        print("🔄 SupabaseSyncService: Inserted folder: \(metadataFolder.id)")
                        #endif
                    } else {
                        // Update existing folder with network recovery
                        _ = try await networkRecoveryManager.executeWithRetry(
                            operation: {
                                try await self.supabaseService.client.from("folders")
                                    .update(metadataFolder)
                                    .eq("id", value: metadataFolder.id.uuidString)
                                    .execute()
                            },
                            operationName: "Folder Update (\(metadataFolder.name))"
                        )

                        #if DEBUG
                        print("🔄 SupabaseSyncService: Updated folder: \(metadataFolder.id)")
                        #endif
                    }
                }

                // Update sync status in CoreData
                await updateFolderSyncStatus(folderId: folder.id ?? UUID(), status: "synced", context: context)

                // Increment success counter in a thread-safe way
                await successCounter.increment()

                // Update progress with throttling
                let currentSuccessCount = await successCounter.getCount()
                progressCoordinator.scheduleUpdate { [weak self] in
                    self?.syncProgress.syncedFolders = currentSuccessCount
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
                // Update progress status with throttling
                progressCoordinator.scheduleUpdate { [weak self] in
                    self?.syncProgress.currentStatus = "Syncing note \(index + 1) of \(notes.count)"
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
                progressCoordinator.scheduleUpdate { [weak self] in
                    self?.syncProgress.syncedNotes = currentSuccessCount
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
            print("🔄 SupabaseSyncService: Inserted note metadata: \(metadataNote.id)")
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
            print("🔄 SupabaseSyncService: Inserted note with binary data: \(fullNote.id)")
            if let originalContent = fullNote.originalContent {
                let sizeInMB = originalContent.sizeInMB()
                print("🔄 SupabaseSyncService: Uploaded originalContent (\(String(format: "%.2f", sizeInMB)) MB)")
            }
            if let aiContent = fullNote.aiGeneratedContent {
                let sizeInMB = aiContent.sizeInMB()
                print("🔄 SupabaseSyncService: Uploaded aiGeneratedContent (\(String(format: "%.2f", sizeInMB)) MB)")
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
            print("🔄 SupabaseSyncService: Updated note with binary data: \(fullNote.id)")
            if let originalContent = fullNote.originalContent {
                let sizeInMB = originalContent.sizeInMB()
                print("🔄 SupabaseSyncService: Updated originalContent (\(String(format: "%.2f", sizeInMB)) MB)")
            }
            if let aiContent = fullNote.aiGeneratedContent {
                let sizeInMB = aiContent.sizeInMB()
                print("🔄 SupabaseSyncService: Updated aiGeneratedContent (\(String(format: "%.2f", sizeInMB)) MB)")
            }
            #endif
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

    /// Delete a folder from Supabase
    /// - Parameters:
    ///   - folder: The CoreData Folder to delete
    ///   - userId: The Supabase user ID
    ///   - context: The NSManagedObjectContext
    private func deleteFolderFromSupabase(folder: Folder, userId: UUID, context: NSManagedObjectContext) async throws {
        guard let folderId = folder.id else {
            #if DEBUG
            print("🔄 SupabaseSyncService: Cannot delete folder - missing ID")
            #endif
            return
        }

        #if DEBUG
        print("🔄 SupabaseSyncService: Deleting folder from Supabase: \(folderId)")
        #endif

        // Delete the folder from Supabase with network recovery
        _ = try await networkRecoveryManager.executeWithRetry(
            operation: {
                try await self.supabaseService.client.from("folders")
                    .delete()
                    .eq("id", value: folderId.uuidString)
                    .eq("user_id", value: userId.uuidString) // Security: ensure user can only delete their own folders
                    .execute()
            },
            operationName: "Folder Delete (\(folderId))"
        )

        #if DEBUG
        print("🔄 SupabaseSyncService: Successfully deleted folder from Supabase: \(folderId)")
        #endif

        // After successful deletion from Supabase, mark for permanent deletion
        // We'll delete it from CoreData after the sync loop completes to avoid threading issues
        try await context.perform {
            // Mark the folder as successfully deleted from Supabase
            folder.syncStatus = "deleted_from_supabase"

            if context.hasChanges {
                try context.save()
                #if DEBUG
                print("🔄 SupabaseSyncService: Marked folder as deleted from Supabase: \(folderId)")
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

        try await context.perform {
            // Clean up notes marked as deleted from Supabase
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
            } catch {
                #if DEBUG
                print("🔄 SupabaseSyncService: Error fetching deleted notes - \(error)")
                #endif
            }

            // Clean up folders marked as deleted from Supabase
            let folderRequest = NSFetchRequest<Folder>(entityName: "Folder")
            folderRequest.predicate = NSPredicate(format: "syncStatus == %@", "deleted_from_supabase")

            do {
                let deletedFolders = try context.fetch(folderRequest)

                #if DEBUG
                print("🔄 SupabaseSyncService: Found \(deletedFolders.count) folders to permanently delete")
                #endif

                for folder in deletedFolders {
                    context.delete(folder)
                }
            } catch {
                #if DEBUG
                print("🔄 SupabaseSyncService: Error fetching deleted folders - \(error)")
                #endif
            }

            // Save changes if any
            if context.hasChanges {
                try context.save()
                #if DEBUG
                print("🔄 SupabaseSyncService: Successfully cleaned up deleted items")
                #endif
            }
        }
    }

    /// Clean up invalid default folders that shouldn't exist
    /// - Parameter context: The NSManagedObjectContext
    private func cleanupInvalidFolders(context: NSManagedObjectContext) async throws {
        #if DEBUG
        print("🔄 SupabaseSyncService: Starting cleanup of invalid folders")
        #endif

        await context.perform {
            // Find folders with default values that are empty (no notes)
            let request = NSFetchRequest<Folder>(entityName: "Folder")
            request.predicate = NSPredicate(format: "name == %@ AND color == %@", "Untitled Folder", "blue")

            do {
                let defaultFolders = try context.fetch(request)

                #if DEBUG
                print("🔄 SupabaseSyncService: Found \(defaultFolders.count) default folders to check")
                #endif

                for folder in defaultFolders {
                    // Only delete if the folder is empty (no notes) and not the "All Notes" folder
                    if folder.notes?.count == 0 && folder.name != "All Notes" {
                        #if DEBUG
                        print("🔄 SupabaseSyncService: Deleting empty default folder: \(folder.id?.uuidString ?? "unknown")")
                        #endif
                        context.delete(folder)
                    }
                }

                // Save changes if any
                if context.hasChanges {
                    try context.save()
                    #if DEBUG
                    print("🔄 SupabaseSyncService: Successfully cleaned up invalid folders")
                    #endif
                }
            } catch {
                #if DEBUG
                print("🔄 SupabaseSyncService: Error cleaning up invalid folders - \(error)")
                #endif
            }
        }
    }

    // MARK: - Private Methods

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
            print("🔄 SupabaseSyncService: Fetched \(notes.count) notes for sync (\(deletedCount) deleted)")
            #endif

            return notes
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

                    // Only save immediately if not in a transaction context
                    // Transaction contexts will be saved atomically later
                    let isTransactionContext = self.transactionManager.getCurrentContext() === context

                    if context.hasChanges && !isTransactionContext {
                        try context.save()

                        #if DEBUG
                        print("🔄 SupabaseSyncService: Updated sync status for folder \(folderId) to \(status)")
                        #endif
                    } else if isTransactionContext {
                        #if DEBUG
                        print("🔄 SupabaseSyncService: Marked folder \(folderId) sync status as \(status) in transaction")
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

                    // Only save immediately if not in a transaction context
                    // Transaction contexts will be saved atomically later
                    let isTransactionContext = self.transactionManager.getCurrentContext() === context

                    if context.hasChanges && !isTransactionContext {
                        try context.save()

                        #if DEBUG
                        print("🔄 SupabaseSyncService: Updated sync status for note \(noteId) to \(status)")
                        #endif
                    } else if isTransactionContext {
                        #if DEBUG
                        print("🔄 SupabaseSyncService: Marked note \(noteId) sync status as \(status) in transaction")
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

        // Fix folders with sync_status = "pending" in Supabase with network recovery
        do {
            let response = try await networkRecoveryManager.executeWithRetry(
                operation: {
                    try await self.supabaseService.client.from("folders")
                        .update(["sync_status": "synced"])
                        .eq("user_id", value: userId.uuidString)
                        .eq("sync_status", value: "pending")
                        .execute()
                },
                operationName: "Fix Folders Sync Status"
            )

            // Parse the response to count affected rows
            if let jsonArray = try? JSONSerialization.jsonObject(with: response.data) as? [[String: Any]] {
                foldersFixed = jsonArray.count
            }

            #if DEBUG
            print("🔧 SupabaseSyncService: Fixed \(foldersFixed) folders in Supabase")
            #endif
        } catch {
            #if DEBUG
            print("🔧 SupabaseSyncService: Error fixing folders in Supabase: \(error)")
            #endif
        }

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

    /// Download notes from Supabase to CoreData
    /// - Parameters:
    ///   - context: The NSManagedObjectContext to save notes to
    ///   - includeBinaryData: Whether to include binary data in the download
    /// - Returns: Success flag
    private func downloadNotesFromSupabase(context: NSManagedObjectContext, includeBinaryData: Bool) async throws -> Bool {
        // Get current user ID
        let session = try await supabaseService.getSession()
        let userId = session.user.id

        #if DEBUG
        print("🔄 SupabaseSyncService: Starting note download for user: \(userId) with binary data: \(includeBinaryData)")
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
        print("🔄 SupabaseSyncService: Found \(remoteNotes.count) remote notes")
        #endif

        // Update progress
        await MainActor.run {
            syncProgress.totalNotes = max(syncProgress.totalNotes, remoteNotes.count)
            syncProgress.downloadedNotes = 0
        }

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

        for (index, remoteNote) in remoteNotes.enumerated() {
            do {
                // Update progress status
                await MainActor.run {
                    syncProgress.currentStatus = "Downloading note \(index + 1) of \(remoteNotes.count)"
                }

                #if DEBUG
                print("🔄 SupabaseSyncService: Processing note \(remoteNote.id) - \(remoteNote.title)")
                #endif

                // Check if note exists locally and resolve conflicts
                let conflictResolved = try await resolveNoteConflict(remoteNote: remoteNote, context: context, includeBinaryData: includeBinaryData)

                if conflictResolved {
                    await successCounter.increment()
                    #if DEBUG
                    print("🔄 SupabaseSyncService: Successfully processed note \(remoteNote.id)")
                    #endif
                } else {
                    #if DEBUG
                    print("🔄 SupabaseSyncService: Failed to process note \(remoteNote.id)")
                    #endif
                }

                // Update progress
                let currentSuccessCount = await successCounter.getCount()
                await MainActor.run {
                    syncProgress.downloadedNotes = currentSuccessCount
                }
            } catch {
                #if DEBUG
                print("🔄 SupabaseSyncService: Error downloading note \(remoteNote.id): \(error.localizedDescription)")
                print("🔄 SupabaseSyncService: Full error details: \(error)")
                #endif
                // Continue processing other notes even if one fails
            }
        }

        // Get final success count
        let finalSuccessCount = await successCounter.getCount()

        #if DEBUG
        print("🔄 SupabaseSyncService: Note download completed. Downloaded \(finalSuccessCount) of \(remoteNotes.count) notes")
        #endif

        // Consider success if we processed any notes OR if there were no notes to process
        return finalSuccessCount > 0 || remoteNotes.isEmpty
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

    /// Resolve note conflict using "Last Write Wins" strategy
    /// - Parameters:
    ///   - remoteNote: The note from Supabase
    ///   - context: The NSManagedObjectContext
    ///   - includeBinaryData: Whether to include binary data in the resolution
    /// - Returns: True if conflict was resolved successfully
    private func resolveNoteConflict(remoteNote: SimpleSupabaseNote, context: NSManagedObjectContext, includeBinaryData: Bool) async throws -> Bool {
        // Skip deleted remote notes - they should not be downloaded
        if remoteNote.deletedAt != nil {
            #if DEBUG
            print("🔄 SupabaseSyncService: Skipping deleted remote note \(remoteNote.id)")
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
                    print("🔄 SupabaseSyncService: Local note \(noteId) is deleted, skipping remote update")
                    #endif
                    return (false, false) // Don't update deleted local notes
                }

                // Note exists locally - check for conflicts
                let localModified = localNote.lastModified ?? localNote.timestamp ?? Date.distantPast
                let remoteModified = remoteNote.lastModified

                #if DEBUG
                print("🔄 SupabaseSyncService: Resolving note conflict - Local: \(localModified), Remote: \(remoteModified)")
                #endif

                // "Last Write Wins" strategy
                if remoteModified > localModified {
                    #if DEBUG
                    print("🔄 SupabaseSyncService: Remote note \(noteId) is newer, will update local data")
                    #endif
                    return (true, false) // Existing note, should update, not new
                } else {
                    #if DEBUG
                    print("🔄 SupabaseSyncService: Local note \(noteId) is newer, keeping local data")
                    #endif
                    return (false, false) // Existing note, no update needed, not new
                }
            } else {
                // Note doesn't exist locally - create new note with proper ID
                let newNote = Note(context: context)
                newNote.id = noteId  // Set the ID immediately to satisfy validation
                #if DEBUG
                print("🔄 SupabaseSyncService: Creating new local note \(noteId)")
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
                        print("🔄 SupabaseSyncService: Successfully saved note changes to CoreData")
                        #endif
                    } catch {
                        #if DEBUG
                        print("🔄 SupabaseSyncService: Failed to save note changes to CoreData: \(error.localizedDescription)")
                        #endif
                        throw error
                    }
                }
            }

            // Update conflict counter if this was a conflict resolution (not a new note)
            if !isNewNote {
                await MainActor.run {
                    syncProgress.resolvedConflicts += 1
                }
            }

            #if DEBUG
            print("🔄 SupabaseSyncService: \(isNewNote ? "Created" : "Updated") local note \(noteId)")
            #endif
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
            print("🔄 SupabaseSyncService: Created placeholder content for note \(remoteNote.id)")
            #endif
        }
    }

    /// Download binary data for a note from Supabase (for use within context.perform blocks)
    /// - Parameters:
    ///   - localNote: The local CoreData note to update
    ///   - remoteNoteId: The ID of the remote note
    private func downloadNoteBinaryDataSync(for localNote: Note, remoteNoteId: UUID) async throws {
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
            print("🔄 SupabaseSyncService: No full note found for binary data download for note \(remoteNoteId)")
            #endif
            return
        }

        #if DEBUG
        print("🔄 SupabaseSyncService: Found full note for binary data download (direct bytea format)")
        #endif

        // Directly assign binary data from bytea columns (no encoding/decoding needed)
        if let originalContentData = fullNote.originalContent {
            localNote.originalContent = originalContentData

            #if DEBUG
            let sizeInMB = originalContentData.sizeInMB()
            print("🔄 SupabaseSyncService: Downloaded originalContent (\(String(format: "%.2f", sizeInMB)) MB) from bytea")
            #endif
        } else {
            #if DEBUG
            print("🔄 SupabaseSyncService: No originalContent binary data found for note \(remoteNoteId)")
            #endif
        }

        if let aiGeneratedContentData = fullNote.aiGeneratedContent {
            localNote.aiGeneratedContent = aiGeneratedContentData

            #if DEBUG
            let sizeInMB = aiGeneratedContentData.sizeInMB()
            print("🔄 SupabaseSyncService: Downloaded aiGeneratedContent (\(String(format: "%.2f", sizeInMB)) MB) from bytea")
            #endif
        }

        if let sectionsData = fullNote.sections {
            localNote.sections = sectionsData

            #if DEBUG
            let sizeInMB = sectionsData.sizeInMB()
            print("🔄 SupabaseSyncService: Downloaded sections (\(String(format: "%.2f", sizeInMB)) MB) from bytea")
            #endif
        }

        if let mindMapData = fullNote.mindMap {
            localNote.mindMap = mindMapData

            #if DEBUG
            let sizeInMB = mindMapData.sizeInMB()
            print("🔄 SupabaseSyncService: Downloaded mindMap (\(String(format: "%.2f", sizeInMB)) MB) from bytea")
            #endif
        }

        if let supplementaryMaterialsData = fullNote.supplementaryMaterials {
            localNote.supplementaryMaterials = supplementaryMaterialsData

            #if DEBUG
            let sizeInMB = supplementaryMaterialsData.sizeInMB()
            print("🔄 SupabaseSyncService: Downloaded supplementaryMaterials (\(String(format: "%.2f", sizeInMB)) MB) from bytea")
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
            print("🔄 SupabaseSyncService: No full note found for binary data download for note \(remoteNoteId)")
            #endif
            return
        }

        #if DEBUG
        print("🔄 SupabaseSyncService: Found full note for binary data download (direct bytea format)")
        #endif

        // Directly assign binary data from bytea columns (no encoding/decoding needed)
        if let originalContentData = fullNote.originalContent {
            localNote.originalContent = originalContentData

            #if DEBUG
            let sizeInMB = originalContentData.sizeInMB()
            print("🔄 SupabaseSyncService: Downloaded originalContent (\(String(format: "%.2f", sizeInMB)) MB) from bytea")
            #endif
        } else {
            #if DEBUG
            print("🔄 SupabaseSyncService: No originalContent binary data found for note \(remoteNoteId)")
            #endif
        }

        if let aiGeneratedContentData = fullNote.aiGeneratedContent {
            localNote.aiGeneratedContent = aiGeneratedContentData

            #if DEBUG
            let sizeInMB = aiGeneratedContentData.sizeInMB()
            print("🔄 SupabaseSyncService: Downloaded aiGeneratedContent (\(String(format: "%.2f", sizeInMB)) MB) from bytea")
            #endif
        }

        if let sectionsData = fullNote.sections {
            localNote.sections = sectionsData

            #if DEBUG
            let sizeInMB = sectionsData.sizeInMB()
            print("🔄 SupabaseSyncService: Downloaded sections (\(String(format: "%.2f", sizeInMB)) MB) from bytea")
            #endif
        }

        if let mindMapData = fullNote.mindMap {
            localNote.mindMap = mindMapData

            #if DEBUG
            let sizeInMB = mindMapData.sizeInMB()
            print("🔄 SupabaseSyncService: Downloaded mindMap (\(String(format: "%.2f", sizeInMB)) MB) from bytea")
            #endif
        }

        if let supplementaryMaterialsData = fullNote.supplementaryMaterials {
            localNote.supplementaryMaterials = supplementaryMaterialsData

            #if DEBUG
            let sizeInMB = supplementaryMaterialsData.sizeInMB()
            print("🔄 SupabaseSyncService: Downloaded supplementaryMaterials (\(String(format: "%.2f", sizeInMB)) MB) from bytea")
            #endif
        }
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






