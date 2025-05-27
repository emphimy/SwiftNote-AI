import Foundation
import CoreData

// MARK: - Sync Transaction Manager

/// Manages atomic transactions for sync operations to ensure data consistency
class SyncTransactionManager {

    /// Transaction state for tracking sync operations
    private struct TransactionState {
        let context: NSManagedObjectContext
        let startTime: Date
        var checkpoints: [String] = []
        var hasChanges: Bool = false
    }

    private var currentTransaction: TransactionState?
    private let transactionQueue = DispatchQueue(label: "com.swiftnote.sync.transaction", qos: .userInitiated)

    /// Begin a new sync transaction with a dedicated background context
    /// - Returns: Background context for sync operations
    /// - Throws: Error if transaction cannot be started
    func beginTransaction() throws -> NSManagedObjectContext {
        return try transactionQueue.sync {
            guard currentTransaction == nil else {
                throw NSError(domain: "SyncTransactionManager", code: 1001, userInfo: [
                    NSLocalizedDescriptionKey: "Transaction already in progress. Cannot start new transaction."
                ])
            }

            // Create dedicated background context for sync operations
            let backgroundContext = PersistenceController.shared.newBackgroundContext()

            // Configure context for sync operations
            backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            backgroundContext.automaticallyMergesChangesFromParent = false // We'll control merging manually

            // Initialize transaction state
            currentTransaction = TransactionState(
                context: backgroundContext,
                startTime: Date()
            )

            #if DEBUG
            print("🔄 SyncTransactionManager: Transaction started with background context")
            #endif

            return backgroundContext
        }
    }

    /// Add a checkpoint to the current transaction
    /// - Parameter name: Name of the checkpoint for debugging
    func addCheckpoint(_ name: String) {
        transactionQueue.sync {
            guard var transaction = currentTransaction else {
                #if DEBUG
                print("🔄 SyncTransactionManager: Warning - No active transaction for checkpoint: \(name)")
                #endif
                return
            }

            transaction.checkpoints.append(name)
            currentTransaction = transaction

            #if DEBUG
            print("🔄 SyncTransactionManager: Checkpoint added: \(name)")
            #endif
        }
    }

    /// Mark that changes have been made to the transaction context
    func markChanges() {
        transactionQueue.sync {
            guard var transaction = currentTransaction else {
                #if DEBUG
                print("🔄 SyncTransactionManager: Warning - No active transaction to mark changes")
                #endif
                return
            }

            transaction.hasChanges = true
            currentTransaction = transaction

            #if DEBUG
            print("🔄 SyncTransactionManager: Transaction marked as having changes")
            #endif
        }
    }

    /// Commit the current transaction, saving all changes atomically
    /// - Throws: Error if commit fails
    func commitTransaction() throws {
        try transactionQueue.sync {
            guard let transaction = currentTransaction else {
                throw NSError(domain: "SyncTransactionManager", code: 1002, userInfo: [
                    NSLocalizedDescriptionKey: "No active transaction to commit."
                ])
            }

            defer {
                currentTransaction = nil
            }

            // Only save if there are actual changes
            if transaction.hasChanges && transaction.context.hasChanges {
                try transaction.context.performAndWait {
                    do {
                        try transaction.context.save()

                        #if DEBUG
                        let duration = Date().timeIntervalSince(transaction.startTime)
                        print("🔄 SyncTransactionManager: Transaction committed successfully")
                        print("🔄 SyncTransactionManager: Duration: \(String(format: "%.2f", duration))s")
                        print("🔄 SyncTransactionManager: Checkpoints: \(transaction.checkpoints.joined(separator: " → "))")
                        #endif
                    } catch {
                        #if DEBUG
                        print("🔄 SyncTransactionManager: Failed to commit transaction: \(error)")
                        #endif
                        throw error
                    }
                }

                // Merge changes to parent context (main context)
                try mergeToParentContext(from: transaction.context)
            } else {
                #if DEBUG
                print("🔄 SyncTransactionManager: Transaction committed with no changes")
                #endif
            }
        }
    }

    /// Rollback the current transaction, discarding all changes
    func rollbackTransaction() {
        transactionQueue.sync {
            guard let transaction = currentTransaction else {
                #if DEBUG
                print("🔄 SyncTransactionManager: Warning - No active transaction to rollback")
                #endif
                return
            }

            defer {
                currentTransaction = nil
            }

            // Rollback all changes in the context
            transaction.context.performAndWait {
                transaction.context.rollback()

                #if DEBUG
                let duration = Date().timeIntervalSince(transaction.startTime)
                print("🔄 SyncTransactionManager: Transaction rolled back")
                print("🔄 SyncTransactionManager: Duration: \(String(format: "%.2f", duration))s")
                print("🔄 SyncTransactionManager: Checkpoints reached: \(transaction.checkpoints.joined(separator: " → "))")
                #endif
            }
        }
    }

    /// Get the current transaction context
    /// - Returns: Current transaction context or nil if no transaction is active
    func getCurrentContext() -> NSManagedObjectContext? {
        return transactionQueue.sync {
            return currentTransaction?.context
        }
    }

    /// Check if a transaction is currently active
    /// - Returns: True if transaction is active
    func isTransactionActive() -> Bool {
        return transactionQueue.sync {
            return currentTransaction != nil
        }
    }

    /// Merge changes from transaction context to parent context
    /// - Parameter context: The transaction context to merge from
    /// - Throws: Error if merge fails
    private func mergeToParentContext(from context: NSManagedObjectContext) throws {
        let mainContext = PersistenceController.shared.container.viewContext

        // Get the object IDs that were changed
        let insertedObjects = context.insertedObjects
        let updatedObjects = context.updatedObjects
        let deletedObjects = context.deletedObjects

        #if DEBUG
        print("🔄 SyncTransactionManager: Merging changes to main context")
        print("🔄 SyncTransactionManager: Inserted: \(insertedObjects.count), Updated: \(updatedObjects.count), Deleted: \(deletedObjects.count)")
        #endif

        // Merge changes to main context
        try mainContext.performAndWait {
            // Process inserted objects
            for object in insertedObjects {
                if let objectID = object.objectID.isTemporaryID ? nil : object.objectID {
                    do {
                        _ = try mainContext.existingObject(with: objectID)
                    } catch {
                        // Object doesn't exist in main context, which is expected for new objects
                        #if DEBUG
                        print("🔄 SyncTransactionManager: New object will be merged: \(objectID)")
                        #endif
                    }
                }
            }

            // Process updated objects
            for object in updatedObjects {
                if let objectID = object.objectID.isTemporaryID ? nil : object.objectID {
                    do {
                        let mainObject = try mainContext.existingObject(with: objectID)
                        mainContext.refresh(mainObject, mergeChanges: true)
                    } catch {
                        #if DEBUG
                        print("🔄 SyncTransactionManager: Could not refresh object in main context: \(error)")
                        #endif
                    }
                }
            }

            // Process deleted objects
            for object in deletedObjects {
                if let objectID = object.objectID.isTemporaryID ? nil : object.objectID {
                    do {
                        let mainObject = try mainContext.existingObject(with: objectID)
                        mainContext.delete(mainObject)
                    } catch {
                        #if DEBUG
                        print("🔄 SyncTransactionManager: Object already deleted from main context: \(objectID)")
                        #endif
                    }
                }
            }

            // Save main context if there are changes
            if mainContext.hasChanges {
                try mainContext.save()
                #if DEBUG
                print("🔄 SyncTransactionManager: Successfully merged changes to main context")
                #endif
            }
        }
    }
}
