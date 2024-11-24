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
    
    @Published var currentFolder: Folder? {
        didSet {
            #if DEBUG
            print("🏠 HomeViewModel: Current folder changed to: \(currentFolder?.name ?? "All")")
            #endif
            fetchNotes()
        }
    }
    
    private let viewContext: NSManagedObjectContext
    
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
    
    // MARK: - Core Data Operations
    func fetchNotes() {
        #if DEBUG
        print("🏠 HomeViewModel: Fetching notes")
        #endif
        
        isLoading = true
        
        let request = NSFetchRequest<Note>(entityName: "Note")
        
        // Add folder filter if selected
        if let folder = currentFolder {
            request.predicate = NSPredicate(format: "folder == %@", folder)
        }
        
        do {
            let results = try viewContext.fetch(request)
            self.notes = results.compactMap { note in
                guard let title = note.title,
                      let timestamp = note.timestamp,
                      let content = note.content,
                      let sourceTypeStr = note.sourceType else {
                    #if DEBUG
                    print("🏠 HomeViewModel: Failed to parse note: \(note)")
                    #endif
                    return nil
                }
                
                return NoteCardConfiguration(
                    title: title,
                    date: timestamp,
                    preview: content,
                    sourceType: NoteSourceType(rawValue: sourceTypeStr) ?? .text,
                    isFavorite: note.isFavorite,
                    tags: note.tags?.components(separatedBy: ",").filter { !$0.isEmpty } ?? []
                )
            }
            
            #if DEBUG
            print("🏠 HomeViewModel: Successfully fetched \(self.notes.count) notes")
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
            note.content = content
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
                    existingNote.content = newContent
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
                      let content = note.content,
                      let sourceTypeStr = note.sourceType else {
                    return nil
                }
                
                return NoteCardConfiguration(
                    title: title,
                    date: timestamp,
                    preview: content,
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
