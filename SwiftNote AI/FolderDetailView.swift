import SwiftUI
import CoreData
import Combine

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
        request.predicate = NSPredicate(format: "folder.id == %@", folderId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Note.timestamp, ascending: false)]

        do {
            let fetchedNotes = try viewContext.fetch(request)
            notes = fetchedNotes.compactMap { note in
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
                    folder: note.folder,
                    sourceURL: note.sourceURL
                )
            }

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

        notes = notes.filter { note in
            note.title.localizedCaseInsensitiveContains(searchText) ||
            note.preview.localizedCaseInsensitiveContains(searchText) ||
            note.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    deinit {
        #if DEBUG
        print("📁 FolderDetailViewModel: Deinitializing")
        #endif
        cancellables.forEach { $0.cancel() }
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

                    Text("\(folder.notes?.count ?? 0) notes")
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
        .sheet(item: $selectedNote) { note in
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
        return CardActionsImplementation(
            note: note,
            viewModel: HomeViewModel(context: viewContext),  // Create temporary instance for actions
            toastManager: toastManager
        )
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
