import SwiftUI
import CoreData
import Combine

// MARK: - Core Data Error
private struct CoreDataError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - Folder Detail Error
enum FolderDetailError: LocalizedError {
    case invalidFolder
    case fetchFailed(Error)
    case saveFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidFolder:
            return "Invalid or missing folder data"
        case .fetchFailed(let error):
            return "Failed to fetch notes: \(error.localizedDescription)"
        case .saveFailed(let error):
            return "Failed to save changes: \(error.localizedDescription)"
        }
    }
}

// MARK: - Folder Detail View Model
@MainActor
final class FolderDetailViewModel: ObservableObject {
    @Published private(set) var notes: [NoteCardConfiguration] = []
    @Published private(set) var isLoading = false
    @Published var searchText = ""
    @Published var errorMessage: String?

    private let folder: Folder
    private let viewContext: NSManagedObjectContext
    private var cancellables = Set<AnyCancellable>()
    private var notificationObserver: NSObjectProtocol?

    init(folder: Folder, context: NSManagedObjectContext) {
        self.folder = folder
        self.viewContext = context

        #if DEBUG
        print("""
        📁 FolderDetailViewModel: Initializing
        - Folder: \(folder.name ?? "Untitled")
        - ID: \(folder.id?.uuidString ?? "nil")
        """)
        #endif

        setupSearchSubscription()

        // Setup notification observer for note changes
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .init("RefreshNotes"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            #if DEBUG
            print("📁 FolderDetailViewModel: Received RefreshNotes notification")
            #endif
            Task { @MainActor [weak self] in
                self?.fetchNotes()
            }
        }

        // Also listen for note deletions from other views
        NotificationCenter.default.addObserver(
            forName: .init("NoteDeleted"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            #if DEBUG
            print("📁 FolderDetailViewModel: Received NoteDeleted notification")
            #endif
            Task { @MainActor [weak self] in
                self?.fetchNotes()
            }
        }
    }

    private func setupSearchSubscription() {
        $searchText
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.filterNotes()
            }
            .store(in: &cancellables)
    }

    func fetchNotes() {
        guard let folderId = folder.id else {
            errorMessage = FolderDetailError.invalidFolder.localizedDescription
            return
        }

        isLoading = true

        let request = NSFetchRequest<Note>(entityName: "Note")

        // Create predicate to exclude deleted notes
        let notDeletedPredicate = NSPredicate(format: "deletedAt == nil")

        // Special handling for "All Notes" folder - show all notes (but exclude deleted)
        if folder.name == "All Notes" {
            request.predicate = notDeletedPredicate
            #if DEBUG
            print("📁 FolderDetailViewModel: Fetching all non-deleted notes for All Notes folder")
            #endif
        } else {
            // For regular folders, only fetch notes assigned to this folder and not deleted
            let folderPredicate = NSPredicate(format: "folder.id == %@", folderId as CVarArg)
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [folderPredicate, notDeletedPredicate])
            #if DEBUG
            print("📁 FolderDetailViewModel: Fetching non-deleted notes for specific folder: \(folder.name ?? "Untitled")")
            #endif
        }

        request.sortDescriptors = [NSSortDescriptor(keyPath: \Note.timestamp, ascending: false)]

        do {
            let fetchedNotes = try viewContext.fetch(request)
            var noteConfigurations: [NoteCardConfiguration] = []

            for note in fetchedNotes {
                guard let title = note.title,
                      let timestamp = note.timestamp,
                      let content = note.originalContent,
                      let sourceTypeStr = note.sourceType else {
                    continue
                }

                // Create metadata dictionary with necessary content for tabs
                var metadata: [String: Any] = [:]

                // Add AI generated content if available
                if let aiContent = note.aiGeneratedContent {
                    metadata["aiGeneratedContent"] = String(decoding: aiContent, as: UTF8.self)
                }

                // Add transcript if available (use the dedicated transcript field)
                if let transcript = note.transcript {
                    metadata["rawTranscript"] = transcript // Use the correct key expected by TranscriptViewModel
                }

                // Add videoId if available (for YouTube notes)
                if let videoId = note.videoId {
                    metadata["videoId"] = videoId
                }

                let noteConfig = NoteCardConfiguration(
                    id: note.id ?? UUID(),
                    title: title,
                    date: timestamp,
                    preview: note.aiGeneratedContent != nil ?
                        String(decoding: note.aiGeneratedContent!, as: UTF8.self) :
                        String(decoding: content, as: UTF8.self),
                    sourceType: NoteSourceType(rawValue: sourceTypeStr) ?? .text,
                    isFavorite: note.isFavorite,
                    tags: note.tags?.components(separatedBy: ",") ?? [],
                    folder: note.folder,
                    metadata: metadata,
                    sourceURL: note.sourceURL
                )

                noteConfigurations.append(noteConfig)
            }

            notes = noteConfigurations

            #if DEBUG
            print("""
            📁 FolderDetailViewModel: Fetched notes
            - Count: \(notes.count)
            - Folder: \(folder.name ?? "Untitled")
            """)
            #endif

        } catch {
            errorMessage = FolderDetailError.fetchFailed(error).localizedDescription
            #if DEBUG
            print("📁 FolderDetailViewModel: Error fetching notes - \(error)")
            #endif
        }

        isLoading = false
    }

    private func filterNotes() {
        guard !searchText.isEmpty else {
            fetchNotes()
            return
        }

        #if DEBUG
        print("📁 FolderDetailViewModel: Filtering notes with search: \(searchText)")
        #endif

        // If we're in the "All Notes" folder, we need to fetch all notes first
        if folder.name == "All Notes" {
            let request = NSFetchRequest<Note>(entityName: "Note")
            // Exclude deleted notes from search
            request.predicate = NSPredicate(format: "deletedAt == nil")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Note.timestamp, ascending: false)]

            do {
                let fetchedNotes = try viewContext.fetch(request)
                var allNotes: [NoteCardConfiguration] = []

                for note in fetchedNotes {
                    guard let title = note.title,
                          let timestamp = note.timestamp,
                          let content = note.originalContent,
                          let sourceTypeStr = note.sourceType else {
                        continue
                    }

                    // Create metadata dictionary with necessary content for tabs
                    var metadata: [String: Any] = [:]

                    // Add AI generated content if available
                    if let aiContent = note.aiGeneratedContent {
                        metadata["aiGeneratedContent"] = String(decoding: aiContent, as: UTF8.self)
                    }

                    // Add transcript if available (use the dedicated transcript field)
                    if let transcript = note.transcript {
                        metadata["rawTranscript"] = transcript // Use the correct key expected by TranscriptViewModel
                    }

                    // Add videoId if available (for YouTube notes)
                    if let videoId = note.videoId {
                        metadata["videoId"] = videoId
                    }

                    let noteConfig = NoteCardConfiguration(
                        id: note.id ?? UUID(),
                        title: title,
                        date: timestamp,
                        preview: note.aiGeneratedContent != nil ?
                            String(decoding: note.aiGeneratedContent!, as: UTF8.self) :
                            String(decoding: content, as: UTF8.self),
                        sourceType: NoteSourceType(rawValue: sourceTypeStr) ?? .text,
                        isFavorite: note.isFavorite,
                        tags: note.tags?.components(separatedBy: ",") ?? [],
                        folder: note.folder,
                        metadata: metadata,
                        sourceURL: note.sourceURL
                    )

                    allNotes.append(noteConfig)
                }

                // Filter the notes based on search text
                notes = allNotes.filter { note in
                    note.title.localizedCaseInsensitiveContains(searchText) ||
                    note.preview.localizedCaseInsensitiveContains(searchText) ||
                    note.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
                }
            } catch {
                #if DEBUG
                print("📁 FolderDetailViewModel: Error fetching all notes for search - \(error)")
                #endif
            }
        } else {
            // For regular folders, just filter the existing notes
            notes = notes.filter { note in
                note.title.localizedCaseInsensitiveContains(searchText) ||
                note.preview.localizedCaseInsensitiveContains(searchText) ||
                note.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
    }

    // MARK: - Note Operations
    func deleteNote(_ note: NoteCardConfiguration) async throws {
        #if DEBUG
        print("📁 FolderDetailViewModel: Deleting note: \(note.title)")
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

            // Refresh notes list for this folder
            await MainActor.run {
                self.fetchNotes()

                // Notify other views that a note was deleted
                NotificationCenter.default.post(name: .init("NoteDeleted"), object: nil)
            }

            #if DEBUG
            print("📁 FolderDetailViewModel: Note deleted successfully")
            #endif
        } catch {
            #if DEBUG
            print("📁 FolderDetailViewModel: Error deleting note - \(error)")
            print("Error details: \((error as NSError).userInfo)")
            #endif

            throw CoreDataError(message: "Failed to delete note: \(error.localizedDescription)")
        }
    }

    func toggleFavorite(_ note: NoteCardConfiguration) async throws {
        #if DEBUG
        print("📁 FolderDetailViewModel: Toggling favorite for note: \(note.title)")
        #endif

        let request = NSFetchRequest<Note>(entityName: "Note")
        request.predicate = NSPredicate(format: "title == %@ AND timestamp == %@", note.title, note.date as CVarArg)

        do {
            guard let noteObject = try viewContext.fetch(request).first else {
                throw CoreDataError(message: "Note not found for favorite toggle")
            }

            noteObject.isFavorite.toggle()
            noteObject.lastModified = Date()
            noteObject.syncStatus = "pending" // Mark for sync

            try viewContext.save()

            // Force save to persistent store
            PersistenceController.shared.saveContext()

            // Refresh notes list for this folder
            await MainActor.run {
                self.fetchNotes()
            }

            #if DEBUG
            print("📁 FolderDetailViewModel: Favorite toggled successfully")
            #endif
        } catch {
            #if DEBUG
            print("📁 FolderDetailViewModel: Error toggling favorite - \(error)")
            #endif

            throw CoreDataError(message: "Failed to toggle favorite: \(error.localizedDescription)")
        }
    }

    deinit {
        #if DEBUG
        print("📁 FolderDetailViewModel: Deinitializing")
        #endif
        cancellables.forEach { $0.cancel() }

        // Remove notification observer
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
            #if DEBUG
            print("📁 FolderDetailViewModel: Removed notification observer")
            #endif
        }
    }
}

// MARK: - Folder Detail View
struct FolderDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.toastManager) private var toastManager
    @StateObject private var viewModel: FolderDetailViewModel
    let folder: Folder
    @State private var viewMode: ListGridContainer<AnyView>.ViewMode = .list
    @State private var selectedNote: NoteCardConfiguration?

    init(folder: Folder) {
        self.folder = folder
        self._viewModel = StateObject(wrappedValue: FolderDetailViewModel(
            folder: folder,
            context: PersistenceController.shared.container.viewContext
        ))

        #if DEBUG
        print("""
        📁 FolderDetailView: Initializing
        - Folder: \(folder.name ?? "Untitled")
        - Notes Count: \(folder.notes?.count ?? 0)
        """)
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Search Bar
            SearchBar(
                text: $viewModel.searchText,
                placeholder: "Search notes",
                onCancel: {
                    #if DEBUG
                    print("🔍 FolderDetail: Search cancelled")
                    #endif
                    viewModel.searchText = ""
                }
            )
            .padding()

            // MARK: - Folder Header
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Circle()
                        .fill(Color(folder.color ?? "blue"))
                        .frame(width: 12, height: 12)

                    Text("\(viewModel.notes.count) notes")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)

                    Spacer()

                    Button(action: {
                        #if DEBUG
                        print("📁 FolderDetailView: Toggle view mode to: \(viewMode == .list ? "grid" : "list")")
                        #endif
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            viewMode = viewMode == .list ? .grid : .list
                        }
                    }) {
                        Image(systemName: viewMode == .list ? "square.grid.2x2" : "list.bullet")
                            .foregroundColor(Theme.Colors.primary)
                            .padding(Theme.Spacing.xs)
                            .background(
                                Circle()
                                    .fill(Theme.Colors.primary.opacity(0.1))
                            )
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, Theme.Spacing.sm)

            // MARK: - Notes Content
            if viewModel.isLoading {
                LoadingIndicator(message: "Loading notes...")
            } else if viewModel.notes.isEmpty {
                EmptyStateView(
                    icon: "folder",
                    title: "Empty Folder",
                    message: "Start adding notes to this folder",
                    actionTitle: nil
                ) {
                    #if DEBUG
                    print("📁 FolderDetailView: Empty state action triggered")
                    #endif
                }
            } else {
                ListGridContainer(viewMode: $viewMode) {
                    AnyView(
                        ForEach(viewModel.notes, id: \.title) { note in
                            NoteCardView(
                                note: note,
                                viewMode: viewMode,
                                cardActions: makeCardActions,
                                selectedNote: $selectedNote
                            )
                        }
                    )
                }
                .padding(.horizontal)
            }
        }
        .navigationTitle(folder.name ?? "Untitled Folder")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $selectedNote) { note in
            NoteDetailsView(note: note, context: viewContext)
        }
        .onChange(of: viewModel.errorMessage) { error in
            if let error = error {
                toastManager.show(error, type: .error)
            }
        }
        .onAppear {
            #if DEBUG
            print("📁 FolderDetailView: View appeared for folder: \(folder.name ?? "Untitled")")
            #endif
            viewModel.fetchNotes()
        }
    }

    // MARK: - Helper Methods
    private func makeCardActions(for note: NoteCardConfiguration) -> CardActions {
        return FolderCardActionsImplementation(
            note: note,
            folderViewModel: viewModel,
            toastManager: toastManager
        )
    }
}

// MARK: - Folder Card Actions Implementation
struct FolderCardActionsImplementation: CardActions {
    let note: NoteCardConfiguration
    let folderViewModel: FolderDetailViewModel
    let toastManager: ToastManager

    func onFavorite() {
        Task {
            do {
                try await folderViewModel.toggleFavorite(note)
                await MainActor.run {
                    toastManager.show("Favorite updated", type: .success)
                }
            } catch {
                #if DEBUG
                print("📁 FolderCardActions: Error toggling favorite: \(error.localizedDescription)")
                #endif
                await MainActor.run {
                    toastManager.show("Failed to update favorite status", type: .error)
                }
            }
        }
    }

    func onShare() {
        #if DEBUG
        print("📁 FolderCardActions: Share triggered for note: \(note.title)")
        #endif

        // Create share content
        var shareText = "📝 \(note.title)\n\n"
        shareText += note.preview

        if !note.tags.isEmpty {
            shareText += "\n\n🏷️ Tags: \(note.tags.joined(separator: ", "))"
        }

        shareText += "\n\n📅 Created: \(DateFormatter.localizedString(from: note.date, dateStyle: .medium, timeStyle: .short))"

        // Present share sheet
        DispatchQueue.main.async {
            let activityVC = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)

            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootViewController = window.rootViewController {

                // For iPad, set popover presentation
                if let popover = activityVC.popoverPresentationController {
                    popover.sourceView = window
                    popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                    popover.permittedArrowDirections = []
                }

                rootViewController.present(activityVC, animated: true)
            }
        }
    }

    func onDelete() {
        Task {
            do {
                try await folderViewModel.deleteNote(note)
                await MainActor.run {
                    toastManager.show("Note deleted", type: .success)
                }
            } catch {
                #if DEBUG
                print("📁 FolderCardActions: Error deleting note: \(error.localizedDescription)")
                #endif
                await MainActor.run {
                    toastManager.show("Failed to delete note", type: .error)
                }
            }
        }
    }

    func onTagSelected(_ tag: String) {
        #if DEBUG
        print("📁 FolderCardActions: Tag selected: \(tag) for note: \(note.title)")
        #endif
        // TODO: Implement tag selection handling for folder views
    }
}

// MARK: - Preview Provider
#if DEBUG
struct FolderDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            FolderDetailView(folder: {
                let folder = Folder(context: PersistenceController.preview.container.viewContext)
                folder.id = UUID()
                folder.name = "Preview Folder"
                folder.color = "FolderBlue"
                return folder
            }())
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        }
    }
}
#endif
