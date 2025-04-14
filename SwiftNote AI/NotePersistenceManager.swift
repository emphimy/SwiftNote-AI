import Foundation
import CoreData

// MARK: - Note Persistence Manager
class NotePersistenceManager {
    // MARK: - Singleton
    static let shared = NotePersistenceManager()
    
    // MARK: - Properties
    private let fileManager = FileManager.default
    private let persistenceController = PersistenceController.shared
    
    // MARK: - File Paths
    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    private var notesDirectory: URL {
        let directory = documentsDirectory.appendingPathComponent("notes", isDirectory: true)
        
        if !fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                #if DEBUG
                print("📝 NotePersistenceManager: Created notes directory at \(directory.path)")
                #endif
            } catch {
                #if DEBUG
                print("📝 NotePersistenceManager: Error creating notes directory - \(error)")
                #endif
            }
        }
        
        return directory
    }
    
    // MARK: - Initialization
    private init() {
        #if DEBUG
        print("📝 NotePersistenceManager: Initializing")
        #endif
        
        // Ensure notes directory exists
        _ = notesDirectory
    }
    
    // MARK: - Public Methods
    
    /// Backs up a note to file storage
    func backupNote(id: UUID, title: String, content: Data, sourceType: String, timestamp: Date) {
        let noteData: [String: Any] = [
            "id": id.uuidString,
            "title": title,
            "content": content,
            "sourceType": sourceType,
            "timestamp": timestamp,
            "lastModified": Date()
        ]
        
        let noteURL = notesDirectory.appendingPathComponent("\(id.uuidString).json")
        
        do {
            let data = try JSONSerialization.data(withJSONObject: noteData)
            try data.write(to: noteURL)
            
            #if DEBUG
            print("📝 NotePersistenceManager: Successfully backed up note \(id.uuidString)")
            #endif
        } catch {
            #if DEBUG
            print("📝 NotePersistenceManager: Error backing up note - \(error)")
            #endif
        }
    }
    
    /// Restores notes from file storage if CoreData is empty
    func restoreNotesIfNeeded(context: NSManagedObjectContext) {
        // Check if CoreData has any notes
        let fetchRequest = NSFetchRequest<Note>(entityName: "Note")
        
        do {
            let count = try context.count(for: fetchRequest)
            
            if count == 0 {
                #if DEBUG
                print("📝 NotePersistenceManager: No notes found in CoreData, attempting to restore from backup")
                #endif
                
                restoreNotes(context: context)
            } else {
                #if DEBUG
                print("📝 NotePersistenceManager: Found \(count) notes in CoreData, no restoration needed")
                #endif
            }
        } catch {
            #if DEBUG
            print("📝 NotePersistenceManager: Error checking for notes - \(error)")
            #endif
            
            // If we can't check, try to restore anyway
            restoreNotes(context: context)
        }
    }
    
    // MARK: - Private Methods
    
    /// Restores notes from file storage to CoreData
    private func restoreNotes(context: NSManagedObjectContext) {
        do {
            let noteFiles = try fileManager.contentsOfDirectory(at: notesDirectory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
            
            #if DEBUG
            print("📝 NotePersistenceManager: Found \(noteFiles.count) backup notes")
            #endif
            
            for noteURL in noteFiles {
                do {
                    let data = try Data(contentsOf: noteURL)
                    guard let noteData = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let idString = noteData["id"] as? String,
                          let id = UUID(uuidString: idString),
                          let title = noteData["title"] as? String,
                          let content = noteData["content"] as? Data,
                          let sourceType = noteData["sourceType"] as? String,
                          let timestamp = noteData["timestamp"] as? Date else {
                        continue
                    }
                    
                    // Create note in CoreData
                    let note = Note(context: context)
                    note.id = id
                    note.title = title
                    note.originalContent = content
                    note.sourceType = sourceType
                    note.timestamp = timestamp
                    note.lastModified = noteData["lastModified"] as? Date ?? Date()
                    note.processingStatus = "completed"
                    
                    #if DEBUG
                    print("📝 NotePersistenceManager: Restored note \(id.uuidString)")
                    #endif
                } catch {
                    #if DEBUG
                    print("📝 NotePersistenceManager: Error restoring note \(noteURL.lastPathComponent) - \(error)")
                    #endif
                }
            }
            
            // Save context
            if context.hasChanges {
                try context.save()
                #if DEBUG
                print("📝 NotePersistenceManager: Successfully saved restored notes to CoreData")
                #endif
            }
        } catch {
            #if DEBUG
            print("📝 NotePersistenceManager: Error restoring notes - \(error)")
            #endif
        }
    }
}
