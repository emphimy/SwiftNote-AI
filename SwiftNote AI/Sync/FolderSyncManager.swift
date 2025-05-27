//
//  FolderSyncManager.swift
//  SwiftNote AI
//
//  Created by Augment Agent on 1/27/25.
//  Extracted from SupabaseSyncService.swift for better code organization
//

import Foundation
import CoreData
import Supabase

// MARK: - Folder Sync Manager

/// Manages all folder-related sync operations between CoreData and Supabase
class FolderSyncManager {

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
    }

    // MARK: - Public Methods

    /// Sync folders from CoreData to Supabase (one-way, metadata only)
    /// - Parameters:
    ///   - context: The NSManagedObjectContext to fetch folders from
    ///   - syncProgress: The sync progress tracker (passed by reference via closure)
    /// - Returns: Success flag
    func syncFoldersToSupabase(context: NSManagedObjectContext, updateProgress: @escaping (SyncProgress) -> Void) async throws -> Bool {
        // Get current user ID
        let session = try await supabaseService.getSession()
        let userId = session.user.id

        #if DEBUG
        print("🔄 FolderSyncManager: Starting folder sync for user: \(userId)")
        #endif

        // Fetch folders from CoreData that need syncing
        let folders = try await fetchFoldersForSync(context: context)

        #if DEBUG
        print("🔄 FolderSyncManager: Found \(folders.count) folders to sync")
        #endif

        // Update progress
        await MainActor.run {
            var progress = SyncProgress()
            progress.totalFolders = folders.count
            progress.syncedFolders = 0
            updateProgress(progress)
        }

        // Use an actor-isolated counter to track success
        let successCounter = SuccessCounter()

        for (index, folder) in folders.enumerated() {
            do {
                // Update progress status with throttling
                progressCoordinator.scheduleUpdate {
                    var progress = SyncProgress()
                    progress.currentStatus = "Syncing folder \(index + 1) of \(folders.count)"
                    updateProgress(progress)
                }

                // Skip folders with invalid/default values that shouldn't be synced
                if let folderName = folder.name,
                   folderName == "Untitled Folder" && folder.color == "blue" && folder.notes?.count == 0 {
                    #if DEBUG
                    print("🔄 FolderSyncManager: Skipping empty default folder: \(folder.id?.uuidString ?? "unknown")")
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
                        print("🔄 FolderSyncManager: Inserted folder: \(metadataFolder.id)")
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
                        print("🔄 FolderSyncManager: Updated folder: \(metadataFolder.id)")
                        #endif
                    }
                }

                // Update sync status in CoreData
                await updateFolderSyncStatus(folderId: folder.id ?? UUID(), status: "synced", context: context)

                // Increment success counter in a thread-safe way
                await successCounter.increment()

                // Update progress with throttling
                let currentSuccessCount = await successCounter.getCount()
                progressCoordinator.scheduleUpdate {
                    var progress = SyncProgress()
                    progress.syncedFolders = currentSuccessCount
                    updateProgress(progress)
                }
            } catch {
                #if DEBUG
                print("🔄 FolderSyncManager: Error syncing folder \(folder.id?.uuidString ?? "unknown"): \(error)")
                #endif
            }
        }

        let finalSuccessCount = await successCounter.getCount()
        let success = finalSuccessCount > 0

        #if DEBUG
        print("🔄 FolderSyncManager: Completed folder sync - \(finalSuccessCount)/\(folders.count) successful")
        #endif

        return success
    }

    /// Download folders from Supabase to CoreData
    /// - Parameters:
    ///   - context: The NSManagedObjectContext to save folders to
    ///   - updateProgress: Closure to update sync progress
    /// - Returns: Success flag
    func downloadFoldersFromSupabase(context: NSManagedObjectContext, updateProgress: @escaping (SyncProgress) -> Void) async throws -> Bool {
        // Get current user ID
        let session = try await supabaseService.getSession()
        let userId = session.user.id

        #if DEBUG
        print("🔄 FolderSyncManager: Starting folder download for user: \(userId)")
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
        print("🔄 FolderSyncManager: Found \(remoteFolders.count) remote folders")
        #endif

        // Update progress
        await MainActor.run {
            var progress = SyncProgress()
            progress.totalFolders = remoteFolders.count
            progress.downloadedFolders = 0
            updateProgress(progress)
        }

        // Use an actor-isolated counter to track success
        let successCounter = SuccessCounter()

        for (index, remoteFolder) in remoteFolders.enumerated() {
            do {
                // Update progress status
                await MainActor.run {
                    var progress = SyncProgress()
                    progress.currentStatus = "Downloading folder \(index + 1) of \(remoteFolders.count)"
                    updateProgress(progress)
                }

                #if DEBUG
                print("🔄 FolderSyncManager: Processing folder \(remoteFolder.id) - \(remoteFolder.name)")
                #endif

                // Check if folder exists locally and resolve conflicts
                let conflictResolved = try await resolveFolderConflict(remoteFolder: remoteFolder, context: context, updateProgress: updateProgress)

                if conflictResolved {
                    await successCounter.increment()
                    #if DEBUG
                    print("🔄 FolderSyncManager: Successfully processed folder \(remoteFolder.id)")
                    #endif
                } else {
                    #if DEBUG
                    print("🔄 FolderSyncManager: Failed to process folder \(remoteFolder.id)")
                    #endif
                }

                // Update progress
                let currentSuccessCount = await successCounter.getCount()
                await MainActor.run {
                    var progress = SyncProgress()
                    progress.downloadedFolders = currentSuccessCount
                    updateProgress(progress)
                }
            } catch {
                #if DEBUG
                print("🔄 FolderSyncManager: Error downloading folder \(remoteFolder.id): \(error.localizedDescription)")
                print("🔄 FolderSyncManager: Full error details: \(error)")
                #endif
                // Continue processing other folders even if one fails
            }
        }

        let finalSuccessCount = await successCounter.getCount()
        let success = finalSuccessCount > 0

        #if DEBUG
        print("🔄 FolderSyncManager: Completed folder download - \(finalSuccessCount)/\(remoteFolders.count) successful")
        #endif

        return success
    }

    /// Clean up any invalid default folders
    /// - Parameter context: The NSManagedObjectContext
    func cleanupInvalidFolders(context: NSManagedObjectContext) async throws {
        await context.perform {
            // Find folders with default values that are empty
            let request = NSFetchRequest<Folder>(entityName: "Folder")
            request.predicate = NSPredicate(format: "name == %@ AND color == %@", "Untitled Folder", "blue")

            do {
                let defaultFolders = try context.fetch(request)

                #if DEBUG
                print("🔄 FolderSyncManager: Found \(defaultFolders.count) default folders to check")
                #endif

                for folder in defaultFolders {
                    // Only delete if the folder is empty (no notes) and not the "All Notes" folder
                    if folder.notes?.count == 0 && folder.name != "All Notes" {
                        #if DEBUG
                        print("🔄 FolderSyncManager: Deleting empty default folder: \(folder.id?.uuidString ?? "unknown")")
                        #endif
                        context.delete(folder)
                    }
                }

                // Save changes if any
                if context.hasChanges {
                    try context.save()
                    #if DEBUG
                    print("🔄 FolderSyncManager: Successfully cleaned up invalid folders")
                    #endif
                }
            } catch {
                #if DEBUG
                print("🔄 FolderSyncManager: Error cleaning up invalid folders - \(error)")
                #endif
            }
        }
    }

    /// Fix folders with pending sync status in Supabase
    /// - Returns: Number of folders fixed
    func fixPendingFoldersInSupabase() async throws -> Int {
        // Get current user ID
        let session = try await supabaseService.getSession()
        let userId = session.user.id

        var foldersFixed = 0

        #if DEBUG
        print("🔧 FolderSyncManager: Fixing folders with pending sync status for user: \(userId)")
        #endif

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
            print("🔧 FolderSyncManager: Fixed \(foldersFixed) folders in Supabase")
            #endif
        } catch {
            #if DEBUG
            print("🔧 FolderSyncManager: Error fixing folders in Supabase: \(error)")
            #endif
        }

        return foldersFixed
    }

    // MARK: - Private Helper Methods

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
            print("🔄 FolderSyncManager: Fetched \(allFolders.count) folders for sync")
            #endif

            return allFolders
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
            print("🔄 FolderSyncManager: Cannot delete folder - missing ID")
            #endif
            return
        }

        #if DEBUG
        print("🔄 FolderSyncManager: Deleting folder from Supabase: \(folderId)")
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
        print("🔄 FolderSyncManager: Successfully deleted folder from Supabase: \(folderId)")
        #endif

        // After successful deletion from Supabase, mark for permanent deletion
        // We'll delete it from CoreData after the sync loop completes to avoid threading issues
        try await context.perform {
            // Mark the folder as successfully deleted from Supabase
            folder.syncStatus = "deleted_from_supabase"

            if context.hasChanges {
                try context.save()
                #if DEBUG
                print("🔄 FolderSyncManager: Marked folder as deleted from Supabase: \(folderId)")
                #endif
            }
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
                        print("🔄 FolderSyncManager: Updated sync status for folder \(folderId) to \(status)")
                        #endif
                    } else if isTransactionContext {
                        #if DEBUG
                        print("🔄 FolderSyncManager: Marked folder \(folderId) sync status as \(status) in transaction")
                        #endif
                    }
                }
            } catch {
                #if DEBUG
                print("🔄 FolderSyncManager: Error updating folder sync status: \(error)")
                #endif
            }
        }
    }

    /// Resolve folder conflict using "Last Write Wins" strategy
    /// - Parameters:
    ///   - remoteFolder: The folder from Supabase
    ///   - context: The NSManagedObjectContext
    ///   - updateProgress: Closure to update sync progress
    /// - Returns: True if conflict was resolved successfully
    private func resolveFolderConflict(remoteFolder: SimpleSupabaseFolder, context: NSManagedObjectContext, updateProgress: @escaping (SyncProgress) -> Void) async throws -> Bool {
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
                print("🔄 FolderSyncManager: Resolving folder conflict - Local: \(localModified), Remote: \(remoteModified)")
                #endif

                // "Last Write Wins" strategy
                if remoteModified > localModified {
                    // Remote is newer - update local folder
                    self.updateLocalFolderFromRemote(localFolder: localFolder, remoteFolder: remoteFolder)

                    #if DEBUG
                    print("🔄 FolderSyncManager: Updated local folder \(remoteFolder.id) with remote data")
                    #endif

                    return (true, true) // Should update conflict counter, was updated
                } else {
                    #if DEBUG
                    print("🔄 FolderSyncManager: Local folder \(remoteFolder.id) is newer, keeping local data")
                    #endif
                    return (false, false) // No conflict counter update, not updated
                }
            } else {
                // Folder doesn't exist locally - create new folder
                let newFolder = Folder(context: context)
                self.updateLocalFolderFromRemote(localFolder: newFolder, remoteFolder: remoteFolder)

                #if DEBUG
                print("🔄 FolderSyncManager: Created new local folder \(remoteFolder.id)")
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
                        print("🔄 FolderSyncManager: Successfully saved folder changes to CoreData")
                        #endif
                    } catch {
                        #if DEBUG
                        print("🔄 FolderSyncManager: Failed to save folder changes to CoreData: \(error.localizedDescription)")
                        #endif
                        throw error
                    }
                }
            }
        }

        // Update conflict counter if needed
        if shouldUpdateConflictCounter {
            await MainActor.run {
                var progress = SyncProgress()
                progress.resolvedConflicts = 1
                updateProgress(progress)
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

    /// Clean up folders marked as deleted from Supabase
    /// - Parameter context: The NSManagedObjectContext
    func cleanupDeletedFolders(context: NSManagedObjectContext) async throws {
        await context.perform {
            // Clean up folders marked as deleted from Supabase
            let folderRequest = NSFetchRequest<Folder>(entityName: "Folder")
            folderRequest.predicate = NSPredicate(format: "syncStatus == %@", "deleted_from_supabase")

            do {
                let deletedFolders = try context.fetch(folderRequest)

                #if DEBUG
                print("🔄 FolderSyncManager: Found \(deletedFolders.count) folders to permanently delete")
                #endif

                for folder in deletedFolders {
                    context.delete(folder)
                }

                // Save changes if any
                if context.hasChanges {
                    try context.save()
                    #if DEBUG
                    print("🔄 FolderSyncManager: Successfully cleaned up deleted folders")
                    #endif
                }
            } catch {
                #if DEBUG
                print("🔄 FolderSyncManager: Error fetching deleted folders - \(error)")
                #endif
            }
        }
    }
}
