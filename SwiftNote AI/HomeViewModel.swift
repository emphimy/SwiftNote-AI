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

        // If search text is not empty, use filterNotes instead
        if !searchText.isEmpty {
            filterNotes()
            return
        }

        let request = NSFetchRequest<Note>(entityName: "Note")

        // Apply folder filter if a folder is selected
        if let folderId = currentFolderId {
            request.predicate = NSPredicate(format: "folder.id == %@", folderId as CVarArg)
        }

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
                    id: note.id ?? UUID(), // Use the CoreData note's ID
                    title: note.title!,
                    date: note.timestamp!,
                    // Use aiGeneratedContent for preview if available, otherwise fallback to originalContent
                    preview: note.aiGeneratedContent != nil ?
                        String(decoding: note.aiGeneratedContent!, as: UTF8.self) :
                        String(decoding: note.originalContent!, as: UTF8.self),
                    sourceType: NoteSourceType(rawValue: note.sourceType!) ?? .text,
                    isFavorite: note.isFavorite,
                    folder: note.folder,
                    metadata: [
                        "rawTranscript": String(decoding: note.originalContent!, as: UTF8.self),
                        "aiGeneratedContent": note.aiGeneratedContent != nil ?
                            String(decoding: note.aiGeneratedContent!, as: UTF8.self) : nil,
                        "videoId": note.videoId,
                        "language": note.transcriptLanguage
                    ].compactMapValues { $0 },
                    sourceURL: note.sourceURL
                )
            }

            // Sort notes with favorites at the top
            self.notes = sortNotesByFavorite(validNotes)

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

        isLoading = true

        Task {
            do {
                // Get the default folder if none is specified
                var targetFolder = folder
                if targetFolder == nil {
                    // Create a FolderListViewModel to access the All Notes folder
                    let folderViewModel = FolderListViewModel(context: viewContext)
                    // Ensure the All Notes folder exists and get a reference to it
                    folderViewModel.ensureAllNotesFolder()
                    targetFolder = folderViewModel.getDefaultFolder()

                    #if DEBUG
                    print("📝 HomeViewModel: Using default folder: \(targetFolder?.name ?? "nil")")
                    #endif
                }

                // Create the note
                let newNote = try PersistenceController.shared.createNote(
                    title: title,
                    content: content,
                    sourceType: sourceType.rawValue
                )

                // Assign to folder
                if let targetFolder = targetFolder {
                    #if DEBUG
                    print("📝 HomeViewModel: Assigning note to folder: \(targetFolder.name ?? "unnamed")")
                    #endif
                    newNote.folder = targetFolder
                    try viewContext.save()
                } else {
                    #if DEBUG
                    print("📝 HomeViewModel: Warning - No target folder found, note will not be in any folder")
                    #endif
                }

                #if DEBUG
                print("📝 HomeViewModel: Note created successfully and added to folder: \(targetFolder?.name ?? "nil")")
                #endif

                // Refresh the notes list
                await MainActor.run {
                    self.fetchNotes()
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    #if DEBUG
                    print("📝 HomeViewModel: Error creating note - \(error)")
                    #endif
                    self.isLoading = false
                }
            }
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

        isLoading = true

        let request = NSFetchRequest<Note>(entityName: "Note")

        // Create predicate for searching in title
        let titlePredicate = NSPredicate(format: "title CONTAINS[cd] %@", searchText)

        // Note: We'll handle content search separately with manual filtering

        // Apply folder filter if a folder is selected
        if let folderId = currentFolderId {
            let folderPredicate = NSPredicate(format: "folder.id == %@", folderId as CVarArg)
            request.predicate = NSCompoundPredicate(type: .and, subpredicates: [folderPredicate, titlePredicate])
        } else {
            request.predicate = titlePredicate
        }

        request.sortDescriptors = [NSSortDescriptor(keyPath: \Note.timestamp, ascending: false)]

        do {
            // First fetch notes matching the title
            let results = try viewContext.fetch(request)

            // Now fetch notes that might contain the search text in their content
            // We'll do this as a separate query to avoid complex binary data predicates
            let allNotesRequest = NSFetchRequest<Note>(entityName: "Note")
            if let folderId = currentFolderId {
                allNotesRequest.predicate = NSPredicate(format: "folder.id == %@", folderId as CVarArg)
            }
            let allNotes = try viewContext.fetch(allNotesRequest)

            // Filter notes that contain the search text in their content
            let contentMatchingNotes = allNotes.filter { note in
                guard let originalContent = note.originalContent else { return false }

                let originalContentString = String(decoding: originalContent, as: UTF8.self)
                if originalContentString.localizedCaseInsensitiveContains(searchText) {
                    return true
                }

                // Also check aiGeneratedContent if available
                if let aiContent = note.aiGeneratedContent {
                    let aiContentString = String(decoding: aiContent, as: UTF8.self)
                    return aiContentString.localizedCaseInsensitiveContains(searchText)
                }

                return false
            }

            // Combine results, removing duplicates
            let allResults = Array(Set(results + contentMatchingNotes))

            // Convert to view models
            self.notes = allResults.compactMap { note in
                // Skip notes with missing required properties
                guard let title = note.title,
                      let timestamp = note.timestamp,
                      let content = note.originalContent,
                      let sourceTypeStr = note.sourceType else {
                    #if DEBUG
                    print("📝 HomeViewModel: Skipping note with missing required properties")
                    #endif
                    return nil
                }

                return NoteCardConfiguration(
                    id: note.id ?? UUID(),
                    title: title,
                    date: timestamp,
                    preview: note.aiGeneratedContent != nil ?
                        String(decoding: note.aiGeneratedContent!, as: UTF8.self) :
                        String(decoding: content, as: UTF8.self),
                    sourceType: NoteSourceType(rawValue: sourceTypeStr) ?? .text,
                    isFavorite: note.isFavorite,
                    folder: note.folder,
                    metadata: ["language": note.transcriptLanguage].compactMapValues { $0 },
                    sourceURL: note.sourceURL
                )
            }

            // Sort notes with favorites at the top
            self.notes = sortNotesByFavorite(self.notes)

            #if DEBUG
            print("📝 HomeViewModel: Found \(notes.count) matching notes for search: \(searchText)")
            #endif
        } catch {
            #if DEBUG
            print("📝 HomeViewModel: Error filtering notes - \(error)")
            #endif
        }

        isLoading = false
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

            // Fetch notes and sort them with favorites at the top
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
            guard let noteObject = try viewContext.fetch(request).first else {
                throw CoreDataError(message: "Note not found for deletion")
            }

            try PersistenceController.shared.deleteNote(noteObject)

            // Force save to persistent store
            PersistenceController.shared.saveContext()

            // Refresh notes list
            self.fetchNotes()

            #if DEBUG
            print("🏠 HomeViewModel: Note deleted successfully")
            #endif
        } catch {
            #if DEBUG
            print("🏠 HomeViewModel: Error deleting note - \(error)")
            print("Error details: \((error as NSError).userInfo)")
            #endif

            throw CoreDataError(message: "Failed to delete note: \(error.localizedDescription)")
        }
    }

    // MARK: - Helper Methods

    /// Sorts notes with favorites at the top, then by date (newest first)
    private func sortNotesByFavorite(_ notes: [NoteCardConfiguration]) -> [NoteCardConfiguration] {
        return notes.sorted { first, second in
            if first.isFavorite && !second.isFavorite {
                return true
            } else if !first.isFavorite && second.isFavorite {
                return false
            } else {
                // If both have the same favorite status, sort by date (newest first)
                return first.date > second.date
            }
        }
    }
}
