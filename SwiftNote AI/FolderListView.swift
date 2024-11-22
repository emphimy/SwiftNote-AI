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
    
    // MARK: - Private Properties
    private let viewContext: NSManagedObjectContext
    
    // MARK: - Color Options
    let colorOptions = ["FolderBlue", "FolderGreen", "FolderRed", "FolderPurple", "FolderOrange"]
    
    init(context: NSManagedObjectContext) {
        self.viewContext = context
        
        #if DEBUG
        print("📁 FolderListViewModel: Initializing with context")
        #endif
        
        fetchFolders()
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
            print("📁 FolderListViewModel: Starting folder fetch")
            #endif
            
            isLoading = true
            defer { isLoading = false }
            
            let request = NSFetchRequest<Folder>(entityName: "Folder")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Folder.timestamp, ascending: false)]
            
            do {
                folders = try viewContext.fetch(request)
                #if DEBUG
                print("""
                📁 FolderListViewModel: Folders fetched successfully
                - Count: \(folders.count)
                - Folders: \(folders.map { "Name: \($0.name ?? "Untitled"), Color: \($0.color ?? "blue")" })
                """)
                #endif
            } catch {
                #if DEBUG
                print("📁 FolderListViewModel: Error fetching folders - \(error)")
                #endif
                errorMessage = "Failed to load folders: \(error.localizedDescription)"
            }
        }
    
    func createFolder() {
        guard !newFolderName.isEmpty else {
            #if DEBUG
            print("📁 FolderListViewModel: Attempted to create folder with empty name")
            #endif
            errorMessage = "Folder name cannot be empty"
            return
        }
        
        #if DEBUG
        print("📁 FolderListViewModel: Creating new folder: \(newFolderName)")
        #endif
        
        let folder = Folder(context: viewContext)
        folder.id = UUID()
        folder.name = newFolderName
        folder.color = selectedColor
        folder.timestamp = Date()
        
        do {
            try viewContext.save()
            fetchFolders()
            newFolderName = ""
            isAddingFolder = false
            
            #if DEBUG
            print("📁 FolderListViewModel: Successfully created folder")
            #endif
        } catch {
            #if DEBUG
            print("📁 FolderListViewModel: Error creating folder - \(error)")
            #endif
            errorMessage = "Failed to create folder: \(error.localizedDescription)"
        }
    }
    
    func deleteFolder(_ folder: Folder) {
        #if DEBUG
        print("📁 FolderListViewModel: Deleting folder: \(folder.name ?? "")")
        #endif
        
        viewContext.delete(folder)
        
        do {
            try viewContext.save()
            fetchFolders()
            
            #if DEBUG
            print("📁 FolderListViewModel: Successfully deleted folder")
            #endif
        } catch {
            #if DEBUG
            print("📁 FolderListViewModel: Error deleting folder - \(error)")
            #endif
            errorMessage = "Failed to delete folder: \(error.localizedDescription)"
        }
    }
}

// MARK: - Folder List View
struct FolderListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: FolderListViewModel
    @Binding var selectedFolder: Folder?
    
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
                        viewModel.isAddingFolder = true
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
                        viewModel.isAddingFolder = true
                    }) {
                        Image(systemName: "folder.badge.plus")
                    }
                }
            }
            .sheet(isPresented: $viewModel.isAddingFolder) {
                NewFolderSheet(viewModel: viewModel)
            }
        }
    }
    
    // MARK: - Folder List
    private var folderList: some View {
        List {
            ForEach(viewModel.folders) { folder in
                FolderRow(folder: folder,
                         onSelect: {
                             selectedFolder = folder
                             dismiss()
                         },
                         viewModel: viewModel)
            }
            .onDelete { indexSet in
                indexSet.forEach { index in
                    viewModel.deleteFolder(viewModel.folders[index])
                }
            }
        }
    }
}

// MARK: - Folder Row
private struct FolderRow: View {
    let folder: Folder
    let onSelect: () -> Void
    let viewModel: FolderListViewModel
    
    var body: some View {
        Button(action: onSelect) {
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
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
            }
            .padding(.vertical, Theme.Spacing.xs)
        }
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
                        viewModel.createFolder()
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
