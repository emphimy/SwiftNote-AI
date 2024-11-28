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
    @Published var isShowingCloudStorageImport = false
    @Published var selectedCloudStorage: CloudStorageProvider?
    private var cancellables = Set<AnyCancellable>()
    
    enum CloudStorageProvider {
        case googleDrive
        case dropbox
    }
    
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
    
    init(context: NSManagedObjectContext) {
        self.viewContext = context
        
        #if DEBUG
        print("📝 HomeViewModel: Initializing with context")
        #endif
        
        // Add search text observation
        $searchText
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.filterNotes()
            }
            .store(in: &cancellables)
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
        print("""
        🏠 HomeViewModel: Starting fetch
        - Current folder: \(currentFolder?.name ?? "All")
        - Folder ID: \(currentFolder?.id?.uuidString ?? "nil")
        """)
        #endif
        
        isLoading = true
        
        let request = NSFetchRequest<Note>(entityName: "Note")
        
        // Add folder predicate
        if let folderId = currentFolderId {
                request.predicate = NSPredicate(format: "folder.id == %@", folderId as CVarArg)
                
                #if DEBUG
                print("""
                🏠 HomeViewModel: Fetching notes for folder
                - FolderID: \(folderId)
                - Predicate: \(String(describing: request.predicate))
                """)
                #endif
            }
        
        // Add search predicate if needed
        if !searchText.isEmpty {
            let searchPredicate = NSPredicate(
                format: "title CONTAINS[cd] %@ OR content CONTAINS[cd] %@ OR tags CONTAINS[cd] %@",
                searchText, searchText, searchText
            )
            
            // Combine with folder predicate if exists
            if let existingPredicate = request.predicate {
                request.predicate = NSCompoundPredicate(
                    type: .and,
                    subpredicates: [existingPredicate, searchPredicate]
                )
            } else {
                request.predicate = searchPredicate
            }
        }

        logSQLQuery(request)

        do {
            let results = try viewContext.fetch(request)
            self.notes = results.compactMap { note in
                guard let title = note.title,
                      let timestamp = note.timestamp,
                      let content = note.originalContent, // Changed from content
                      let sourceTypeStr = note.sourceType else {
                    return nil
                }
                
                return NoteCardConfiguration(
                    title: title,
                    date: timestamp,
                    preview: String(decoding: content, as: UTF8.self), // Convert Data to String
                    sourceType: NoteSourceType(rawValue: sourceTypeStr) ?? .text,
                    isFavorite: note.isFavorite,
                    tags: note.tags?.components(separatedBy: ",").filter { !$0.isEmpty } ?? [],
                    folder: note.folder
                )
            }
            
            #if DEBUG
            print("🏠 HomeViewModel: Fetched \(self.notes.count) notes for folder: \(currentFolder?.name ?? "All")")
            #endif
        } catch {
            #if DEBUG
            print("🏠 HomeViewModel: Error fetching notes - \(error)")
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
        
        viewContext.performAndWait {
            let note = Note(context: self.viewContext)
            note.title = title
            note.originalContent = content.data(using: .utf8)
            note.sourceType = sourceType.rawValue
            note.timestamp = Date()
            note.folder = folder
            
            do {
                try self.viewContext.save()
                self.fetchNotes()
                
                #if DEBUG
                print("📝 HomeViewModel: Note created successfully")
                #endif
            } catch {
                #if DEBUG
                print("📝 HomeViewModel: Error creating note - \(error)")
                #endif
            }
        }
    }
    
    /// Updates existing note
    func updateNote(_ note: NoteCardConfiguration, newContent: String? = nil) {
        #if DEBUG
        print("📝 HomeViewModel: Updating note - Title: \(note.title)")
        #endif
        
        viewContext.performAndWait {
            let request = NSFetchRequest<Note>(entityName: "Note")
            request.predicate = NSPredicate(format: "title == %@ AND timestamp == %@", note.title, note.date as CVarArg)
            
            do {
                guard let existingNote = try self.viewContext.fetch(request).first else {
                    #if DEBUG
                    print("📝 HomeViewModel: Error - Note not found for update")
                    #endif
                    return
                }
                
                if let newContent = newContent {
                    existingNote.originalContent = newContent.data(using: .utf8)
                }
                existingNote.lastModified = Date()
                
                try self.viewContext.save()
                self.fetchNotes()
                
                #if DEBUG
                print("📝 HomeViewModel: Note updated successfully")
                #endif
            } catch {
                #if DEBUG
                print("📝 HomeViewModel: Error updating note - \(error)")
                #endif
            }
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
        
        let request = NSFetchRequest<NSManagedObject>(entityName: "Note")
        request.predicate = NSPredicate(format: "title == %@ AND timestamp == %@", note.title, note.date as CVarArg)
        
        do {
            let results = try viewContext.fetch(request)
            guard let noteObject = results.first else {
                throw CoreDataError(message: "Note not found")
            }
            
            viewContext.delete(noteObject)
            try viewContext.save()
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
