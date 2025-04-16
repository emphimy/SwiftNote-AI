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
    let colorOptions = ["FolderBlue", "FolderGreen", "FolderRed", "FolderPurple", "FolderOrange"]

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
            
            if let existingFolder = results.first {
                #if DEBUG
                print("📁 FolderListViewModel: All Notes folder already exists")
                #endif
                allNotesFolder = existingFolder
                
                // Ensure it has the lowest sort order
                if existingFolder.sortOrder > 0 {
                    existingFolder.sortOrder = 0
                    try viewContext.save()
                }
            } else {
                #if DEBUG
                print("📁 FolderListViewModel: Creating All Notes folder")
                #endif
                
                // Create All Notes folder
                let folder = Folder(context: viewContext)
                folder.id = UUID()
                folder.name = "All Notes"
                folder.color = "FolderBlue"
                folder.timestamp = Date()
                folder.sortOrder = 0
                
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
                    .foregroundColor(Color(folder.color ?? "blue"))
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
                    
                    if let notes = folder.notes?.allObjects as? [Note] {
                        Text("\(notes.count) notes")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.secondaryText)
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
        return Color(colorName)
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
                    
                    Picker("Color", selection: $viewModel.selectedColor) {
                        ForEach(viewModel.colorOptions, id: \.self) { color in
                            HStack {
                                Circle()
                                    .fill(Color(color))
                                    .frame(width: 20, height: 20)
                                Text(color.replacingOccurrences(of: "Folder", with: ""))
                                    .foregroundColor(Theme.Colors.text)
                            }
                            .tag(color)
                        }
                    }
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
