import SwiftUI
import CoreData

// MARK: - Folder List View Model
@MainActor
final class FolderListViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published private(set) var folders: [Folder] = []
    @Published var isAddingFolder = false
    @Published var newFolderName = ""
    @Published var selectedColor: String = "blue"
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var errorState: LoadingState = .idle
    @Published private(set) var allNotesFolder: Folder?


    // MARK: - Private Properties
    private let viewContext: NSManagedObjectContext

    // MARK: - Color Options
    let colorOptions = ["FolderBlue", "FolderGreen", "FolderRed", "FolderPurple", "FolderOrange", "FolderYellow", "FolderTeal", "FolderPink", "FolderBrown"]

    init(context: NSManagedObjectContext) {
        self.viewContext = context
        self.selectedColor = "FolderBlue"

        #if DEBUG
        print("📁 FolderListViewModel: Initializing with context")
        print("📁 FolderListViewModel: Setting initial color to: FolderBlue")
        #endif

        fetchFolders()
        ensureAllNotesFolder()
    }

    // MARK: - Public Methods
    func moveNote(_ note: Note, to folder: Folder?) {
        #if DEBUG
        print("📁 FolderListViewModel: Moving note '\(note.title ?? "")' to folder '\(folder?.name ?? "root")'")
        #endif

        note.folder = folder

        do {
            try viewContext.save()
            #if DEBUG
            print("📁 FolderListViewModel: Successfully moved note")
            #endif
        } catch {
            #if DEBUG
            print("📁 FolderListViewModel: Error moving note - \(error)")
            #endif
            errorMessage = "Failed to move note: \(error.localizedDescription)"
        }
    }

    func fetchFolders() {
        #if DEBUG
        print("📁 FolderListViewModel: Fetching folders")
        #endif

        isLoading = true

        let request = NSFetchRequest<Folder>(entityName: "Folder")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Folder.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \Folder.timestamp, ascending: false)
        ]

        do {
            folders = try viewContext.fetch(request)
            #if DEBUG
            print("📁 FolderListViewModel: Fetched \(folders.count) folders")
            #endif

            // Update the allNotesFolder reference
            allNotesFolder = folders.first(where: { $0.name == "All Notes" })
        } catch {
            #if DEBUG
            print("📁 FolderListViewModel: Error fetching folders - \(error)")
            #endif
            errorMessage = "Failed to load folders: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Ensures that an "All Notes" folder exists in the system
    func ensureAllNotesFolder() {
        #if DEBUG
        print("📁 FolderListViewModel: Ensuring All Notes folder exists")
        #endif

        // Check if All Notes folder already exists
        let request = NSFetchRequest<Folder>(entityName: "Folder")
        request.predicate = NSPredicate(format: "name == %@", "All Notes")

        do {
            let results = try viewContext.fetch(request)

            if !results.isEmpty {
                #if DEBUG
                print("📁 FolderListViewModel: Found \(results.count) All Notes folders")
                #endif

                // Use the first one as our reference
                allNotesFolder = results.first

                // If we have multiple "All Notes" folders, we should consolidate them
                if results.count > 1 {
                    #if DEBUG
                    print("📁 FolderListViewModel: Consolidating multiple All Notes folders")
                    #endif

                    // Keep the first one and delete the rest
                    for i in 1..<results.count {
                        let duplicateFolder = results[i]

                        // Move any notes from the duplicate folder to the main All Notes folder
                        if let notes = duplicateFolder.notes?.allObjects as? [Note] {
                            for note in notes {
                                note.folder = allNotesFolder
                            }
                        }

                        // Delete the duplicate folder
                        viewContext.delete(duplicateFolder)
                    }
                }

                // Ensure it has the lowest sort order and correct color
                if let folder = allNotesFolder {
                    if folder.sortOrder > 0 {
                        folder.sortOrder = 0
                    }

                    // Update color to FolderGray if it's using a different color
                    if folder.color != "FolderGray" {
                        folder.color = "FolderGray"
                        #if DEBUG
                        print("📁 FolderListViewModel: Updated All Notes folder color to FolderGray")
                        #endif
                    }
                }

                try viewContext.save()
            } else {
                #if DEBUG
                print("📁 FolderListViewModel: Creating All Notes folder")
                #endif

                // Create All Notes folder
                let folder = Folder(context: viewContext)
                folder.id = UUID()
                folder.name = "All Notes"
                folder.color = "FolderGray"  // Special color for All Notes folder
                folder.timestamp = Date()
                folder.sortOrder = 0
                folder.updatedAt = Date()
                folder.syncStatus = "pending"

                try viewContext.save()
                allNotesFolder = folder

                // Refresh folders list
                fetchFolders()
            }
        } catch {
            #if DEBUG
            print("📁 FolderListViewModel: Error ensuring All Notes folder - \(error)")
            #endif
            errorMessage = "Failed to create All Notes folder: \(error.localizedDescription)"
        }
    }

    /// Returns the All Notes folder, creating it if needed
    func getDefaultFolder() -> Folder? {
        if allNotesFolder == nil {
            ensureAllNotesFolder()
        }
        return allNotesFolder
    }

    /// Static helper to get the All Notes folder from any context
    static func getAllNotesFolder(context: NSManagedObjectContext) -> Folder? {
        #if DEBUG
        print("📁 FolderListViewModel: Getting All Notes folder statically")
        #endif

        // Check if All Notes folder exists
        let request = NSFetchRequest<Folder>(entityName: "Folder")
        request.predicate = NSPredicate(format: "name == %@", "All Notes")

        do {
            let results = try context.fetch(request)

            if !results.isEmpty {
                #if DEBUG
                print("📁 FolderListViewModel: Found \(results.count) All Notes folders")
                #endif

                // Use the first one as our reference
                let allNotesFolder = results.first

                // If we have multiple "All Notes" folders, we should consolidate them
                if results.count > 1 {
                    #if DEBUG
                    print("📁 FolderListViewModel: Consolidating multiple All Notes folders")
                    #endif

                    // Keep the first one and delete the rest
                    for i in 1..<results.count {
                        let duplicateFolder = results[i]

                        // Move any notes from the duplicate folder to the main All Notes folder
                        if let notes = duplicateFolder.notes?.allObjects as? [Note] {
                            for note in notes {
                                note.folder = allNotesFolder
                            }
                        }

                        // Delete the duplicate folder
                        context.delete(duplicateFolder)
                    }
                }

                // Ensure it has the lowest sort order and correct color
                if let folder = allNotesFolder {
                    var needsSave = false

                    if folder.sortOrder > 0 {
                        folder.sortOrder = 0
                        needsSave = true
                    }

                    // Update color to FolderGray if it's using a different color
                    if folder.color != "FolderGray" {
                        folder.color = "FolderGray"
                        needsSave = true
                        #if DEBUG
                        print("📁 FolderListViewModel: Updated All Notes folder color to FolderGray")
                        #endif
                    }

                    if needsSave {
                        try context.save()
                    }
                }

                return allNotesFolder
            } else {
                #if DEBUG
                print("📁 FolderListViewModel: Creating All Notes folder")
                #endif

                // Create All Notes folder
                let folder = Folder(context: context)
                folder.id = UUID()
                folder.name = "All Notes"
                folder.color = "FolderGray"  // Special color for All Notes folder
                folder.timestamp = Date()
                folder.sortOrder = 0
                folder.updatedAt = Date()
                folder.syncStatus = "pending"

                try context.save()
                return folder
            }
        } catch {
            #if DEBUG
            print("📁 FolderListViewModel: Error getting All Notes folder - \(error)")
            #endif
            return nil
        }
    }

    func createFolder(name: String, color: String) throws {
        #if DEBUG
        print("📁 FolderListViewModel: Creating folder - Name: \(name), Color: \(color)")
        #endif

        guard !name.isEmpty else {
            throw NSError(domain: "Folder", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Folder name cannot be empty"])
        }

        viewContext.performAndWait { [weak self] in
            guard let self = self else { return }

            let folder = Folder(context: self.viewContext)
            folder.id = UUID()
            folder.name = name
            folder.color = color
            folder.timestamp = Date()

            do {
                try self.viewContext.save()
                self.fetchFolders()
                #if DEBUG
                print("📁 FolderListViewModel: Folder created successfully")
                #endif
            } catch {
                #if DEBUG
                print("📁 FolderListViewModel: Failed to create folder - \(error)")
                #endif
            }
        }
    }

    func updateFolder(_ folder: Folder, name: String?, color: String?) throws {
        #if DEBUG
        print("📁 FolderListViewModel: Updating folder \(folder.id?.uuidString ?? "")")
        #endif

        viewContext.performAndWait { [weak self] in
            guard let self = self else { return }

            if let name = name {
                folder.name = name
            }
            if let color = color {
                folder.color = color
            }

            do {
                try self.viewContext.save()
                self.fetchFolders()
                #if DEBUG
                print("📁 FolderListViewModel: Folder updated successfully")
                #endif
            } catch {
                #if DEBUG
                print("📁 FolderListViewModel: Failed to update folder - \(error)")
                #endif
            }
        }
    }

    func deleteFolder(_ folder: Folder, deleteContents: Bool = false) throws {
        #if DEBUG
        print("📁 FolderListViewModel: Deleting folder \(folder.id?.uuidString ?? "") with contents: \(deleteContents)")
        #endif

        viewContext.performAndWait { [weak self] in
            guard let self = self else { return }

            if let notes = folder.notes?.allObjects as? [Note] {
                if deleteContents {
                    notes.forEach { self.viewContext.delete($0) }
                    #if DEBUG
                    print("📁 FolderListViewModel: Deleted \(notes.count) notes from folder")
                    #endif
                } else {
                    notes.forEach { $0.folder = nil }
                    #if DEBUG
                    print("📁 FolderListViewModel: Moved \(notes.count) notes to root")
                    #endif
                }
            }

            self.viewContext.delete(folder)

            do {
                try self.viewContext.save()
                self.fetchFolders()
                #if DEBUG
                print("📁 FolderListViewModel: Folder deleted successfully")
                #endif
            } catch {
                #if DEBUG
                print("📁 FolderListViewModel: Failed to delete folder - \(error)")
                #endif
            }
        }
    }

    func reorderFolders(from source: IndexSet, to destination: Int) throws {
        #if DEBUG
        print("📁 FolderListViewModel: Reordering folders from \(source) to \(destination)")
        #endif

        viewContext.performAndWait { [weak self] in
            guard let self = self else { return }

            var updatedFolders = self.folders
            updatedFolders.move(fromOffsets: source, toOffset: destination)

            for (index, folder) in updatedFolders.enumerated() {
                folder.sortOrder = Int32(index)
            }

            do {
                try self.viewContext.save()
                self.fetchFolders()
                #if DEBUG
                print("📁 FolderListViewModel: Folders reordered successfully")
                #endif
            } catch {
                #if DEBUG
                print("📁 FolderListViewModel: Failed to reorder folders - \(error)")
                #endif
            }
        }
    }
}

// MARK: - Folder List View
struct FolderListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: FolderListViewModel
    @Binding var selectedFolder: Folder?
    @State private var showError = false
    @State private var errorMessage: String?

    init(selectedFolder: Binding<Folder?>) {
        self._selectedFolder = selectedFolder
        self._viewModel = StateObject(wrappedValue: FolderListViewModel(context: PersistenceController.shared.container.viewContext))
    }

    var body: some View {
        NavigationView {
            Group {
                if viewModel.isLoading {
                    LoadingIndicator(message: "Loading folders...")
                } else if viewModel.folders.isEmpty {
                    EmptyStateView(
                        icon: "folder",
                        title: "No Folders",
                        message: "Create your first folder to organize your notes",
                        actionTitle: "Create Folder"
                    ) {
                        #if DEBUG
                        print("📁 FolderListView: Show new folder sheet requested")
                        #endif
                        // Convert async action to sync by wrapping in Task
                        Task { @MainActor in
                            viewModel.isAddingFolder = true
                        }
                    }
                } else {
                    folderList
                }
            }
            .navigationTitle("Folders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        #if DEBUG
                        print("📁 FolderListView: Show new folder sheet requested")
                        #endif
                        // Show the new folder sheet
                        viewModel.isAddingFolder = true
                    }) {
                        Image(systemName: "folder.badge.plus")
                    }
                }
            }
            .sheet(isPresented: $viewModel.isAddingFolder) {
                NewFolderSheet(viewModel: viewModel)
            }
            .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
                Button("OK") {}
            } message: { error in
                Text(error)
            }
        }
    }

    // MARK: - Folder List
    private var folderList: some View {
        List {
            ForEach(viewModel.folders) { folder in
                NavigationLink(destination: FolderDetailView(folder: folder)) {
                    FolderRow(folder: folder, viewModel: viewModel)
                }
            }
            .onDelete { indexSet in
                do {
                    for index in indexSet {
                        try viewModel.deleteFolder(viewModel.folders[index])
                    }
                } catch {
                    #if DEBUG
                    print("📁 FolderListView: Error deleting folders - \(error)")
                    #endif
                }
            }
        }
    }
}

// MARK: - Folder Row
private struct FolderRow: View {
    let folder: Folder
    let viewModel: FolderListViewModel

    var body: some View {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(getFolderColor(folder.color))
                    .frame(width: 24, height: 24)
                    .onAppear {
                        #if DEBUG
                        print("""
                        📁 FolderRow: Folder icon appearing
                        - Folder name: \(folder.name ?? "Untitled")
                        - Folder color: \(folder.color ?? "FolderBlue")
                        """)
                        #endif
                    }

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(folder.name ?? "Untitled")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.text)

                    if folder.name == "All Notes" {
                        // For All Notes folder, fetch all notes count
                        FolderNoteCountView(folder: folder)
                    } else {
                        // For regular folders, use filtered count excluding soft-deleted notes
                        FolderSpecificNoteCountView(folder: folder)
                    }
                }
                Spacer()
            }
            .padding(.vertical, Theme.Spacing.xs)
        .onDrop(of: [.text],
                delegate: NoteFolderDropDelegate(folder: folder,
                                               viewModel: viewModel))
    }
    private func getFolderColor(_ colorName: String?) -> Color {
        guard let colorName = colorName else { return Color("FolderBlue") }

        // Try to get the color from the asset catalog
        let uiColor = UIColor(named: colorName)
        if uiColor != nil {
            return Color(colorName)
        } else {
            // Fallback to a default color if the color is not found
            #if DEBUG
            print("📁 FolderRow: Color \(colorName) not found, using FolderBlue instead")
            #endif
            return Color("FolderBlue")
        }
    }
}

// MARK: - Folder Note Count View
private struct FolderNoteCountView: View {
    let folder: Folder
    @State private var noteCount: Int = 0
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        Text("\(noteCount) notes")
            .font(Theme.Typography.caption)
            .foregroundColor(Theme.Colors.secondaryText)
            .onAppear {
                fetchAllNotesCount()
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("NoteDeleted"))) { _ in
                fetchAllNotesCount()
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("RefreshNotes"))) { _ in
                fetchAllNotesCount()
            }
    }

    private func fetchAllNotesCount() {
        let request = NSFetchRequest<Note>(entityName: "Note")
        request.resultType = .countResultType

        // Exclude soft-deleted notes
        request.predicate = NSPredicate(format: "deletedAt == nil")

        do {
            let count = try viewContext.count(for: request)
            self.noteCount = count

            #if DEBUG
            print("📁 FolderNoteCountView: Fetched total non-deleted note count: \(count)")
            #endif
        } catch {
            #if DEBUG
            print("📁 FolderNoteCountView: Error fetching note count - \(error)")
            #endif
        }
    }
}

// MARK: - Folder Specific Note Count View
private struct FolderSpecificNoteCountView: View {
    let folder: Folder
    @State private var noteCount: Int = 0
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        Text("\(noteCount) notes")
            .font(Theme.Typography.caption)
            .foregroundColor(Theme.Colors.secondaryText)
            .onAppear {
                fetchFolderNotesCount()
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("NoteDeleted"))) { _ in
                fetchFolderNotesCount()
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("RefreshNotes"))) { _ in
                fetchFolderNotesCount()
            }
    }

    private func fetchFolderNotesCount() {
        guard let folderId = folder.id else {
            self.noteCount = 0
            return
        }

        let request = NSFetchRequest<Note>(entityName: "Note")
        request.resultType = .countResultType

        // Filter by folder and exclude soft-deleted notes
        let folderPredicate = NSPredicate(format: "folder.id == %@", folderId as CVarArg)
        let notDeletedPredicate = NSPredicate(format: "deletedAt == nil")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [folderPredicate, notDeletedPredicate])

        do {
            let count = try viewContext.count(for: request)
            self.noteCount = count

            #if DEBUG
            print("📁 FolderSpecificNoteCountView: Fetched note count for folder '\(folder.name ?? "Untitled")': \(count)")
            #endif
        } catch {
            #if DEBUG
            print("📁 FolderSpecificNoteCountView: Error fetching note count for folder '\(folder.name ?? "Untitled")' - \(error)")
            #endif
            self.noteCount = 0
        }
    }
}

// MARK: - New Folder Sheet
private struct NewFolderSheet: View {
    @ObservedObject var viewModel: FolderListViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Folder Details")) {
                    TextField("Folder Name", text: $viewModel.newFolderName)

                    // Color grid
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: Theme.Spacing.md) {
                        ForEach(viewModel.colorOptions, id: \.self) { color in
                            Button(action: {
                                viewModel.selectedColor = color
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(Color(color))
                                        .frame(width: 44, height: 44)
                                        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)

                                    if viewModel.selectedColor == color {
                                        Circle()
                                            .stroke(Color.white, lineWidth: 2)
                                            .frame(width: 44, height: 44)

                                        Image(systemName: "checkmark")
                                            .foregroundColor(.white)
                                            .font(.system(size: 14, weight: .bold))
                                    }
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.vertical, Theme.Spacing.sm)
                }
            }
            .navigationTitle("New Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        do {
                            try viewModel.createFolder(name: viewModel.newFolderName, color: viewModel.selectedColor)
                            dismiss()
                        } catch {
                            #if DEBUG
                            print("📁 NewFolderSheet: Error creating folder - \(error)")
                            #endif
                        }
                    }
                    .disabled(viewModel.newFolderName.isEmpty)
                }
            }
        }
    }
}

// MARK: - Preview Provider
#if DEBUG
struct FolderListView_Previews: PreviewProvider {
    static var previews: some View {
        FolderListView(selectedFolder: .constant(nil))
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
#endif
