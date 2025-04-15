import Foundation
import CoreData

// MARK: - Simple Note Model
struct SimpleNote: Codable {
    let id: UUID
    let title: String
    let content: String
    let sourceType: String
    let timestamp: Date
    let lastModified: Date
    let folderID: UUID?
    let processingStatus: String
    let isFavorite: Bool
    let aiGeneratedContent: String?
    
    init(id: UUID, title: String, content: String, sourceType: String, timestamp: Date, lastModified: Date, folderID: UUID?, 
         processingStatus: String = "completed", isFavorite: Bool = false, aiGeneratedContent: String? = nil) {
        self.id = id
        self.title = title
        self.content = content
        self.sourceType = sourceType
        self.timestamp = timestamp
        self.lastModified = lastModified
        self.folderID = folderID
        self.processingStatus = processingStatus
        self.isFavorite = isFavorite
        self.aiGeneratedContent = aiGeneratedContent
    }
    
    init(from note: Note) {
        self.id = note.id ?? UUID()
        self.title = note.title ?? "Untitled"
        self.content = note.originalContent != nil ? String(decoding: note.originalContent!, as: UTF8.self) : ""
        self.sourceType = note.sourceType ?? "text"
        self.timestamp = note.timestamp ?? Date()
        self.lastModified = note.lastModified ?? Date()
        self.folderID = note.folder?.id
        self.processingStatus = note.processingStatus ?? "completed"
        self.isFavorite = note.isFavorite
        self.aiGeneratedContent = note.aiGeneratedContent != nil ? String(decoding: note.aiGeneratedContent!, as: UTF8.self) : nil
    }
}

// MARK: - Simple Note Persistence
class SimpleNotePersistence {
    // MARK: - Singleton
    static let shared = SimpleNotePersistence()
    
    // MARK: - Properties
    private let defaults = UserDefaults.standard
    private let notesKey = "com.swiftnote.notes"
    
    // MARK: - Initialization
    private init() {
        #if DEBUG
        print("📝 SimpleNotePersistence: Initializing")
        #endif
    }
    
    // MARK: - Public Methods
    
    /// Saves a note to UserDefaults
    func saveNote(_ note: Note) {
        guard let id = note.id, let title = note.title, let originalContent = note.originalContent, let sourceType = note.sourceType else {
            #if DEBUG
            print("📝 SimpleNotePersistence: Cannot save note with missing required properties")
            #endif
            return
        }
        
        let content = String(decoding: originalContent, as: UTF8.self)
        let simpleNote = SimpleNote(
            id: id,
            title: title,
            content: content,
            sourceType: sourceType,
            timestamp: note.timestamp ?? Date(),
            lastModified: note.lastModified ?? Date(),
            folderID: note.folder?.id,
            processingStatus: note.processingStatus ?? "completed",
            isFavorite: note.isFavorite,
            aiGeneratedContent: note.aiGeneratedContent != nil ? String(decoding: note.aiGeneratedContent!, as: UTF8.self) : nil
        )
        
        saveNote(simpleNote)
    }
    
    /// Saves a SimpleNote to UserDefaults
    func saveNote(_ note: SimpleNote) {
        var notes = getAllNotes()
        
        // Remove existing note with same ID if exists
        notes.removeAll { $0.id == note.id }
        
        // Add the new note
        notes.append(note)
        
        // Save to UserDefaults
        saveAllNotes(notes)
        
        #if DEBUG
        print("📝 SimpleNotePersistence: Saved note \(note.id.uuidString)")
        #endif
    }
    
    /// Gets all notes from UserDefaults
    func getAllNotes() -> [SimpleNote] {
        guard let data = defaults.data(forKey: notesKey) else {
            return []
        }
        
        do {
            let notes = try JSONDecoder().decode([SimpleNote].self, from: data)
            #if DEBUG
            print("📝 SimpleNotePersistence: Retrieved \(notes.count) notes from UserDefaults")
            #endif
            return notes
        } catch {
            #if DEBUG
            print("📝 SimpleNotePersistence: Error retrieving notes - \(error)")
            #endif
            return []
        }
    }
    
    /// Saves all notes to UserDefaults
    func saveAllNotes(_ notes: [SimpleNote]) {
        do {
            let data = try JSONEncoder().encode(notes)
            defaults.set(data, forKey: notesKey)
            #if DEBUG
            print("📝 SimpleNotePersistence: Saved \(notes.count) notes to UserDefaults")
            #endif
        } catch {
            #if DEBUG
            print("📝 SimpleNotePersistence: Error saving notes - \(error)")
            #endif
        }
    }
    
    /// Restores notes from UserDefaults to CoreData
    func restoreNotes(context: NSManagedObjectContext) {
        let notes = getAllNotes()
        
        if notes.isEmpty {
            #if DEBUG
            print("📝 SimpleNotePersistence: No notes to restore")
            #endif
            return
        }
        
        #if DEBUG
        print("📝 SimpleNotePersistence: Restoring \(notes.count) notes to CoreData")
        #endif
        
        for simpleNote in notes {
            // Check if note already exists
            let fetchRequest = NSFetchRequest<Note>(entityName: "Note")
            fetchRequest.predicate = NSPredicate(format: "id == %@", simpleNote.id as CVarArg)
            
            do {
                let existingNotes = try context.fetch(fetchRequest)
                
                if let existingNote = existingNotes.first {
                    // Update existing note
                    existingNote.title = simpleNote.title
                    existingNote.originalContent = simpleNote.content.data(using: .utf8)
                    existingNote.lastModified = simpleNote.lastModified
                    existingNote.processingStatus = simpleNote.processingStatus
                    existingNote.isFavorite = simpleNote.isFavorite
                    existingNote.aiGeneratedContent = simpleNote.aiGeneratedContent?.data(using: .utf8)
                    #if DEBUG
                    print("📝 SimpleNotePersistence: Updated existing note \(simpleNote.id.uuidString)")
                    #endif
                } else {
                    // Create new note
                    let note = Note(context: context)
                    note.id = simpleNote.id
                    note.title = simpleNote.title
                    note.originalContent = simpleNote.content.data(using: .utf8)
                    note.sourceType = simpleNote.sourceType
                    note.timestamp = simpleNote.timestamp
                    note.lastModified = simpleNote.lastModified
                    note.processingStatus = simpleNote.processingStatus
                    note.isFavorite = simpleNote.isFavorite
                    note.aiGeneratedContent = simpleNote.aiGeneratedContent?.data(using: .utf8)
                    
                    // Try to set folder if folderID exists
                    if let folderID = simpleNote.folderID {
                        let folderRequest = NSFetchRequest<Folder>(entityName: "Folder")
                        folderRequest.predicate = NSPredicate(format: "id == %@", folderID as CVarArg)
                        if let folder = try? context.fetch(folderRequest).first {
                            note.folder = folder
                        }
                    }
                    
                    #if DEBUG
                    print("📝 SimpleNotePersistence: Created new note \(simpleNote.id.uuidString)")
                    #endif
                }
            } catch {
                #if DEBUG
                print("📝 SimpleNotePersistence: Error checking for existing note - \(error)")
                #endif
                
                // Create new note anyway
                let note = Note(context: context)
                note.id = simpleNote.id
                note.title = simpleNote.title
                note.originalContent = simpleNote.content.data(using: .utf8)
                note.sourceType = simpleNote.sourceType
                note.timestamp = simpleNote.timestamp
                note.lastModified = simpleNote.lastModified
                note.processingStatus = simpleNote.processingStatus
                note.isFavorite = simpleNote.isFavorite
                note.aiGeneratedContent = simpleNote.aiGeneratedContent?.data(using: .utf8)
            }
        }
        
        // Save context
        do {
            try context.save()
            #if DEBUG
            print("📝 SimpleNotePersistence: Successfully saved restored notes to CoreData")
            #endif
        } catch {
            #if DEBUG
            print("📝 SimpleNotePersistence: Error saving context - \(error)")
            #endif
        }
    }
    
    /// Clears all notes from UserDefaults
    func clearAllNotes() {
        defaults.removeObject(forKey: notesKey)
        #if DEBUG
        print("📝 SimpleNotePersistence: Cleared all notes from UserDefaults")
        #endif
    }
}
