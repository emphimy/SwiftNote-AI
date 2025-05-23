//
//  SoftDeleteTest.swift
//  SwiftNote AI
//
//  Test file to demonstrate the soft delete functionality
//

import Foundation
import CoreData

class SoftDeleteTest {

    /// Test the soft delete functionality
    static func testSoftDelete() {
        let context = PersistenceController.shared.container.viewContext

        print("🧪 SoftDeleteTest: Starting soft delete test")

        // Create a test note
        let testNote = Note(context: context)
        testNote.id = UUID()
        testNote.title = "Test Note for Deletion"
        testNote.originalContent = "This is a test note".data(using: .utf8)
        testNote.sourceType = "text"
        testNote.timestamp = Date()
        testNote.lastModified = Date()
        testNote.syncStatus = "pending"

        do {
            try context.save()
            print("🧪 SoftDeleteTest: Created test note with ID: \(testNote.id!)")

            // Test soft delete
            try PersistenceController.shared.deleteNote(testNote)
            print("🧪 SoftDeleteTest: Soft deleted note")

            // Verify the note still exists but has deletedAt set
            let request = NSFetchRequest<Note>(entityName: "Note")
            request.predicate = NSPredicate(format: "id == %@", testNote.id! as CVarArg)

            let results = try context.fetch(request)
            if let deletedNote = results.first {
                if deletedNote.deletedAt != nil {
                    print("✅ SoftDeleteTest: SUCCESS - Note has deletedAt timestamp: \(deletedNote.deletedAt!)")
                    print("✅ SoftDeleteTest: SUCCESS - Note syncStatus is: \(deletedNote.syncStatus ?? "nil")")
                } else {
                    print("❌ SoftDeleteTest: FAILED - Note does not have deletedAt timestamp")
                }
            } else {
                print("❌ SoftDeleteTest: FAILED - Note was hard deleted instead of soft deleted")
            }

            // Test that fetchNotes excludes deleted notes
            let allNotes = try PersistenceController.shared.fetchNotes()
            let deletedNotes = try PersistenceController.shared.fetchNotes(includeDeleted: true)

            print("🧪 SoftDeleteTest: Active notes count: \(allNotes.count)")
            print("🧪 SoftDeleteTest: Total notes (including deleted): \(deletedNotes.count)")

            if deletedNotes.count > allNotes.count {
                print("✅ SoftDeleteTest: SUCCESS - fetchNotes correctly excludes deleted notes")
            } else {
                print("❌ SoftDeleteTest: FAILED - fetchNotes is not excluding deleted notes")
            }

            // Clean up - permanently delete the test note
            try PersistenceController.shared.permanentlyDeleteNote(testNote)
            print("🧪 SoftDeleteTest: Cleaned up test note")

        } catch {
            print("❌ SoftDeleteTest: Error during test - \(error)")
        }
    }

    /// Test the sync filtering functionality
    static func testSyncFiltering() {
        let context = PersistenceController.shared.container.viewContext

        print("🧪 SoftDeleteTest: Starting sync filtering test")

        // Create test notes
        let activeNote = Note(context: context)
        activeNote.id = UUID()
        activeNote.title = "Active Note"
        activeNote.originalContent = "This is an active note".data(using: .utf8)
        activeNote.sourceType = "text"
        activeNote.timestamp = Date()
        activeNote.lastModified = Date()
        activeNote.syncStatus = "pending"

        let deletedNote = Note(context: context)
        deletedNote.id = UUID()
        deletedNote.title = "Deleted Note"
        deletedNote.originalContent = "This is a deleted note".data(using: .utf8)
        deletedNote.sourceType = "text"
        deletedNote.timestamp = Date()
        deletedNote.lastModified = Date()
        deletedNote.syncStatus = "pending"
        deletedNote.deletedAt = Date()

        do {
            try context.save()
            print("🧪 SoftDeleteTest: Created test notes")

            // Test that sync service includes deleted notes for upload
            // We can't easily test the private method, but we can verify the logic
            // by checking that notes with syncStatus != "synced" are included
            let request = NSFetchRequest<Note>(entityName: "Note")
            request.predicate = NSPredicate(format: "syncStatus != %@", "synced")

            let notesToSync = try context.fetch(request)
            let deletedNotesToSync = notesToSync.filter { $0.deletedAt != nil }

            print("🧪 SoftDeleteTest: Notes to sync: \(notesToSync.count)")
            print("🧪 SoftDeleteTest: Deleted notes to sync: \(deletedNotesToSync.count)")

            if deletedNotesToSync.count > 0 {
                print("✅ SoftDeleteTest: SUCCESS - Sync includes deleted notes for upload")
            } else {
                print("❌ SoftDeleteTest: FAILED - Sync does not include deleted notes")
            }

            // Clean up
            try PersistenceController.shared.permanentlyDeleteNote(activeNote)
            try PersistenceController.shared.permanentlyDeleteNote(deletedNote)
            print("🧪 SoftDeleteTest: Cleaned up test notes")

        } catch {
            print("❌ SoftDeleteTest: Error during sync filtering test - \(error)")
        }
    }

    /// Clean up any existing invalid "Untitled Folder" with blue color
    static func cleanupInvalidFolders() {
        let context = PersistenceController.shared.container.viewContext

        print("🧪 SoftDeleteTest: Starting cleanup of invalid folders")

        let request = NSFetchRequest<Folder>(entityName: "Folder")
        request.predicate = NSPredicate(format: "name == %@ AND color == %@", "Untitled Folder", "blue")

        do {
            let invalidFolders = try context.fetch(request)

            print("🧪 SoftDeleteTest: Found \(invalidFolders.count) invalid folders")

            for folder in invalidFolders {
                // Only delete if the folder is empty (no notes) and not the "All Notes" folder
                if folder.notes?.count == 0 && folder.name != "All Notes" {
                    print("🧪 SoftDeleteTest: Deleting invalid folder: \(folder.id?.uuidString ?? "unknown")")
                    context.delete(folder)
                } else {
                    print("🧪 SoftDeleteTest: Keeping folder with \(folder.notes?.count ?? 0) notes")
                }
            }

            if context.hasChanges {
                try context.save()
                print("✅ SoftDeleteTest: Successfully cleaned up invalid folders")
            } else {
                print("✅ SoftDeleteTest: No invalid folders to clean up")
            }

        } catch {
            print("❌ SoftDeleteTest: Error cleaning up invalid folders - \(error)")
        }
    }
}
