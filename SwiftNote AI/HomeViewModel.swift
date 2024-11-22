import SwiftUI
import CoreData

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
        print("🏠 HomeViewModel: Initializing")
        #endif
    }
   
   // MARK: - Core Data Operations
    func fetchNotes() {
        #if DEBUG
        print("🏠 HomeViewModel: Fetching notes")
        #endif
        
        isLoading = true
        defer { isLoading = false }
        
        let request = NSFetchRequest<NSManagedObject>(entityName: "Note")
        
        // Add folder filter if selected
        if let folder = currentFolder {
            request.predicate = NSPredicate(format: "folder == %@", folder)
        }
        
        do {
            let results = try viewContext.fetch(request)
            self.notes = results.compactMap { note in
                guard let title = note.value(forKey: "title") as? String,
                      let timestamp = note.value(forKey: "timestamp") as? Date,
                      let content = note.value(forKey: "content") as? String,
                      let sourceTypeStr = note.value(forKey: "sourceType") as? String,
                      let tags = note.value(forKey: "tags") as? String else {
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
                    isFavorite: note.value(forKey: "isFavorite") as? Bool ?? false,
                    tags: tags.components(separatedBy: ",").filter { !$0.isEmpty }
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
   
   // MARK: - Search
   private func filterNotes() {
       guard !searchText.isEmpty else {
           return
       }
       
       notes = notes.filter { note in
           note.title.localizedCaseInsensitiveContains(searchText) ||
           note.preview.localizedCaseInsensitiveContains(searchText) ||
           note.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
       }
       
       #if DEBUG
       print("🏠 HomeViewModel: Filtered notes, found \(notes.count) matches for '\(searchText)'")
       #endif
   }
}
