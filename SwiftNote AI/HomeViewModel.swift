import SwiftUI
import CoreData
import Combine

// MARK: - Core Data Error
private struct CoreDataError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - HomeViewModel
@MainActor
final class HomeViewModel: ObservableObject {
    @Published var notes: [NoteCardConfiguration] = []
    @Published var searchText: String = ""
    @Published var viewMode: ListGridContainer<AnyView>.ViewMode = .list
    @Published var isShowingAddNote: Bool = false
    @Published var isLoading: Bool = false
    @Published var isShowingSettings = false
    @Published var isShowingRecording = false
    @Published var isShowingYouTubeInput = false
    @Published var isShowingTextUpload = false
    @Published var isShowingAudioUpload = false
    @Published var isShowingTextScan = false
    @Published var isShowingWebLinkInput = false
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Folder Navigation
    @Published var currentFolder: Folder? {
        didSet {
            #if DEBUG
            print("""
            📁 HomeViewModel: currentFolder changed
            - Old Value: \(oldValue?.name ?? "nil")
            - New Value: \(currentFolder?.name ?? "nil")
            - Old ID: \(oldValue?.id?.uuidString ?? "nil")
            - New ID: \(currentFolder?.id?.uuidString ?? "nil")
            """)
            #endif
        }
    }
    
    var currentFolderId: UUID? {
        didSet {
            Task { @MainActor in
                #if DEBUG
                print("""
                📁 HomeViewModel: currentFolderId changed
                - Old: \(oldValue?.uuidString ?? "nil")
                - New: \(currentFolderId?.uuidString ?? "nil")
                """)
                #endif
                self.fetchNotes()
            }
        }
    }
    
    private let viewContext: NSManagedObjectContext
    
    private func persistSelectedFolder(_ folder: Folder?) {
        #if DEBUG
        print("""
        📁 HomeViewModel: Persisting folder selection
        - Folder: \(folder?.name ?? "nil")
        - Notes Count: \(folder?.notes?.count ?? 0)
        """)
        #endif
        
        // Update current folder
        currentFolder = folder
        
        // Force notes refresh
        Task { @MainActor in
            self.fetchNotes()
        }
    }
    
    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.viewContext = context
        
        #if DEBUG
        print("📝 HomeViewModel: Initializing with context")
        #endif
        
        // Setup search text observation
        $searchText
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.fetchNotes()
            }
            .store(in: &cancellables)
            
        // Listen for note refresh notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshNotes),
            name: .init("RefreshNotes"),
            object: nil
        )
        
        // Initial fetch
        fetchNotes()
    }
    
    @objc private func refreshNotes() {
        fetchNotes()
    }
    
    // MARK: - SQL Debug Logging
    private let sqlDebugEnabled = true
    private func logSQLQuery(_ request: NSFetchRequest<Note>) {
        guard sqlDebugEnabled else { return }
        #if DEBUG
        print("""
        🔍 SQL Debug:
        - Entity: \(request.entityName ?? "Unknown")
        - Predicate: \(String(describing: request.predicate))
        - Sort Descriptors: \(String(describing: request.sortDescriptors))
        - Relationship Key Paths: \(String(describing: request.relationshipKeyPathsForPrefetching))
        """)
        
        if let folder = currentFolder {
            print("""
            - Current Folder Stats:
              - ID: \(folder.id?.uuidString ?? "nil")
              - Name: \(folder.name ?? "nil")
              - Notes Count: \(folder.notes?.count ?? 0)
              - Notes: \(folder.notes?.allObjects.map { ($0 as? Note)?.title ?? "unknown" } ?? [])
            """)
        }
        #endif
    }
    
    // MARK: - Core Data Operations
    func fetchNotes() {
        #if DEBUG
        print("🏠 HomeViewModel: Starting fetch with search: \(searchText)")
        #endif
        
        isLoading = true
        
        let request = NSFetchRequest<Note>(entityName: "Note")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Note.timestamp, ascending: false)]
        
        do {
            let results = try viewContext.fetch(request)
            #if DEBUG
            print("📊 Fetched \(results.count) notes")
            #endif
            
            let validNotes: [NoteCardConfiguration] = results.filter { note in
                // Filter out invalid notes
                guard note.title != nil,
                      note.timestamp != nil,
                      note.originalContent != nil,
                      note.sourceType != nil else {
                    #if DEBUG
                    print("""
                    🏠 HomeViewModel: Invalid note detected:
                    - ID: \(note.id?.uuidString ?? "unknown")
                    - Title: \(note.title ?? "missing")
                    - Timestamp: \(note.timestamp?.description ?? "missing")
                    """)
                    #endif
                    return false
                }
                return true
            }.map { note -> NoteCardConfiguration in
                // Explicitly typed closure return
                return NoteCardConfiguration(
                    title: note.title!,
                    date: note.timestamp!,
                    // Use aiGeneratedContent for preview if available, otherwise fallback to originalContent
                    preview: note.aiGeneratedContent != nil ?
                        String(decoding: note.aiGeneratedContent!, as: UTF8.self) :
                        String(decoding: note.originalContent!, as: UTF8.self),
                    sourceType: NoteSourceType(rawValue: note.sourceType!) ?? .text,
                    isFavorite: note.isFavorite,
                    tags: note.tags?.components(separatedBy: ",") ?? [],
                    folder: note.folder,
                    metadata: [
                        "rawTranscript": String(decoding: note.originalContent!, as: UTF8.self),
                        "aiGeneratedContent": note.aiGeneratedContent != nil ?
                            String(decoding: note.aiGeneratedContent!, as: UTF8.self) : nil
                    ].compactMapValues { $0 }
                )
            }
            
            self.notes = validNotes
            
            #if DEBUG
            print("🏠 HomeViewModel: Converted \(self.notes.count) notes to view models")
            #endif
            
        } catch {
            #if DEBUG
            print("❌ HomeViewModel: Error fetching notes - \(error)")
            print("Error details: \((error as NSError).userInfo)")
            #endif
        }
        
        isLoading = false
    }
    
    // MARK: - Note CRUD Operations
    /// Creates a new note
    func createNote(title: String, content: String, sourceType: NoteSourceType, folder: Folder? = nil) {
        #if DEBUG
        print("📝 HomeViewModel: Creating note - Title: \(title), Type: \(sourceType)")
        #endif
        
        // Create a new note directly in the view context
        let note = Note(context: viewContext)
        
        // Set all required attributes
        let noteId = UUID()
        note.id = noteId
        note.title = title
        note.originalContent = content.data(using: .utf8)
        
        // For notes that should appear as transcripts, don't set aiGeneratedContent initially
        // This ensures they appear in the "Process" section rather than the "Read" section
        if sourceType == .text {
            // For manual text notes, we can generate AI content immediately
            // In a real app, you'd likely do more processing here
            note.aiGeneratedContent = content.data(using: .utf8)
        }
        
        note.sourceType = sourceType.rawValue
        note.timestamp = Date()
        note.lastModified = Date()
        note.processingStatus = "completed"
        note.folder = folder
        note.isFavorite = false
        
        // Save in multiple steps to ensure persistence
        do {
            // First save to the view context
            try viewContext.save()
            #if DEBUG
            print("📝 HomeViewModel: Initial save successful")
            #endif
            
            // Force save to the persistent store
            PersistenceController.shared.saveContext()
            #if DEBUG
            print("📝 HomeViewModel: Forced save to persistent store")
            #endif
            
            // Save to UserDefaults for guaranteed persistence
            SimpleNotePersistence.shared.saveNote(note)
            
            // Refresh notes list
            self.fetchNotes()
            
            #if DEBUG
            print("📝 HomeViewModel: Note created successfully with ID: \(note.id?.uuidString ?? "unknown")")
            #endif
        } catch {
            #if DEBUG
            print("📝 HomeViewModel: Error creating note - \(error)")
            print("Error details: \((error as NSError).userInfo)")
            #endif
            
            // Even if CoreData fails, still try to save to UserDefaults
            SimpleNotePersistence.shared.saveNote(SimpleNote(
                id: noteId,
                title: title,
                content: content,
                sourceType: sourceType.rawValue,
                timestamp: Date(),
                lastModified: Date(),
                folderID: folder?.id,
                processingStatus: "completed",
                isFavorite: false,
                aiGeneratedContent: sourceType == .text ? content : nil
            ))
        }
    }
    
    /// Updates existing note
    func updateNote(_ note: NoteCardConfiguration, newContent: String? = nil) {
        #if DEBUG
        print("📝 HomeViewModel: Updating note - Title: \(note.title)")
        #endif
        
        let request = NSFetchRequest<Note>(entityName: "Note")
        request.predicate = NSPredicate(format: "title == %@ AND timestamp == %@", note.title, note.date as CVarArg)
        
        do {
            guard let existingNote = try viewContext.fetch(request).first else {
                #if DEBUG
                print("📝 HomeViewModel: Error - Note not found for update")
                #endif
                return
            }
            
            if let newContent = newContent {
                try PersistenceController.shared.updateNote(
                    existingNote,
                    title: existingNote.title,
                    content: newContent
                )
            } else {
                // Just update the lastModified timestamp
                existingNote.lastModified = Date()
                try viewContext.save()
            }
            
            // Force save to persistent store
            PersistenceController.shared.saveContext()
            
            // Refresh notes list
            self.fetchNotes()
            
            #if DEBUG
            print("📝 HomeViewModel: Note updated successfully")
            #endif
        } catch {
            #if DEBUG
            print("📝 HomeViewModel: Error updating note - \(error)")
            print("Error details: \((error as NSError).userInfo)")
            #endif
        }
    }
    
    func deleteNoteSync(_ note: NoteCardConfiguration) {
        #if DEBUG
        print("🏠 HomeViewModel: Starting synchronous delete for note: \(note.title)")
        #endif
        
        Task {
            do {
                try await self.deleteNote(note)
                #if DEBUG
                print("🏠 HomeViewModel: Successfully completed synchronous delete wrapper")
                #endif
            } catch {
                #if DEBUG
                print("🏠 HomeViewModel: Error in synchronous delete wrapper - \(error)")
                #endif
            }
        }
    }
    
    /// Moves note to a folder
    func moveNote(_ note: NoteCardConfiguration, to folder: Folder?) async throws {
        #if DEBUG
        print("📝 HomeViewModel: Moving note \(note.id) to folder: \(folder?.name ?? "root")")
        #endif
        
        // Use performAndWait for synchronous execution
        return try viewContext.performAndWait {
            let request = NSFetchRequest<Note>(entityName: "Note")
            request.predicate = NSPredicate(format: "id == %@", note.id as CVarArg)
            
            guard let existingNote = try self.viewContext.fetch(request).first else {
                #if DEBUG
                print("📝 HomeViewModel: Error - Note not found for move operation")
                #endif
                throw NSError(domain: "HomeViewModel", code: 404,
                              userInfo: [NSLocalizedDescriptionKey: "Note not found"])
            }
            
            existingNote.folder = folder
            try self.viewContext.save()
            
            Task { @MainActor in
                self.fetchNotes()
            }
            
            #if DEBUG
            print("📝 HomeViewModel: Note moved successfully")
            #endif
        }
    }
    
    /// Filters notes by search text
    private func filterNotes() {
        guard !searchText.isEmpty else {
            fetchNotes()
            return
        }
        
        #if DEBUG
        print("📝 HomeViewModel: Filtering notes with search text: \(searchText)")
        #endif
        
        let request = NSFetchRequest<Note>(entityName: "Note")
        request.predicate = NSPredicate(
            format: "title CONTAINS[cd] %@ OR content CONTAINS[cd] %@ OR tags CONTAINS[cd] %@",
            searchText, searchText, searchText
        )
        
        do {
            let results = try viewContext.fetch(request)
            self.notes = results.compactMap { note in
                guard let title = note.title,
                      let timestamp = note.timestamp,
                      let content = note.originalContent,
                      let sourceTypeStr = note.sourceType else {
                    return nil
                }
                
                return NoteCardConfiguration(
                    title: title,
                    date: timestamp,
                    preview: String(decoding: content, as: UTF8.self),
                    sourceType: NoteSourceType(rawValue: sourceTypeStr) ?? .text,
                    isFavorite: note.isFavorite,
                    tags: note.tags?.components(separatedBy: ",") ?? [],
                    folder: note.folder
                )
            }
            
            #if DEBUG
            print("📝 HomeViewModel: Found \(notes.count) matching notes")
            #endif
        } catch {
            #if DEBUG
            print("📝 HomeViewModel: Error filtering notes - \(error)")
            #endif
        }
    }
    
    func toggleFavorite(_ note: NoteCardConfiguration) async throws {
        #if DEBUG
        print("🏠 HomeViewModel: Toggling favorite for note: \(note.title)")
        #endif
        
        let request = NSFetchRequest<NSManagedObject>(entityName: "Note")
        request.predicate = NSPredicate(format: "title == %@ AND timestamp == %@", note.title, note.date as CVarArg)
        
        do {
            let results = try viewContext.fetch(request)
            guard let noteObject = results.first else {
                throw CoreDataError(message: "Note not found")
            }
            
            let currentValue = noteObject.value(forKey: "isFavorite") as? Bool ?? false
            noteObject.setValue(!currentValue, forKey: "isFavorite")
            
            try viewContext.save()
            fetchNotes()
            
            #if DEBUG
            print("🏠 HomeViewModel: Successfully toggled favorite state")
            #endif
        } catch {
            #if DEBUG
            print("🏠 HomeViewModel: Error toggling favorite: \(error.localizedDescription)")
            #endif
            throw CoreDataError(message: "Failed to update favorite status: \(error.localizedDescription)")
        }
    }
    
    func deleteNote(_ note: NoteCardConfiguration) async throws {
        #if DEBUG
        print("🏠 HomeViewModel: Deleting note: \(note.title)")
        #endif
        
        let request = NSFetchRequest<Note>(entityName: "Note")
        request.predicate = NSPredicate(format: "title == %@ AND timestamp == %@", note.title, note.date as CVarArg)
        
        do {
            let results = try viewContext.fetch(request)
            guard let noteObject = results.first else {
                throw CoreDataError(message: "Note not found")
            }
            
            // Use PersistenceController's delete operation
            try PersistenceController.shared.deleteNote(noteObject)
            
            // Force save to persistent store
            PersistenceController.shared.saveContext()
            
            // Refresh notes list
            fetchNotes()
            
            #if DEBUG
            print("🏠 HomeViewModel: Successfully deleted note")
            #endif
        } catch {
            #if DEBUG
            print("🏠 HomeViewModel: Error deleting note: \(error.localizedDescription)")
            #endif
            throw CoreDataError(message: "Failed to delete note: \(error.localizedDescription)")
        }
    }
}
