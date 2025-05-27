import SwiftUI
import CoreData
import AVKit
import Combine
import AVFoundation

// MARK: - Export URL Model
struct ExportURLWrapper: Identifiable {
    let id = UUID()
    let url: URL

    #if DEBUG
    var debugDescription: String {
        "ExportURLWrapper - id: \(id), url: \(url)"
    }
    #endif
}

// MARK: - Note Details View Model
@MainActor
final class NoteDetailsViewModel: ObservableObject {
    @Published var note: NoteCardConfiguration
    @Published var isEditing = false
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var playbackRate: Float = 1.0
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var isExporting = false
    @Published var exportURL: ExportURLWrapper?
    @Published var isShowingFolderPicker = false
    @Published var availableFolders: [Folder] = []

    private let _viewContext: NSManagedObjectContext
    private let pdfExportService = PDFExportService()

    var viewContext: NSManagedObjectContext {
        return _viewContext
    }

    init(note: NoteCardConfiguration, context: NSManagedObjectContext) {
        self.note = note
        self._viewContext = context

        #if DEBUG
        print("📝 NoteDetailsViewModel: Initializing with note: \(note.title)")
        #endif

        // Fetch available folders
        fetchAvailableFolders()
    }

    func fetchAvailableFolders() {
        #if DEBUG
        print("📝 NoteDetailsViewModel: Fetching available folders")
        #endif

        let request = NSFetchRequest<Folder>(entityName: "Folder")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Folder.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \Folder.timestamp, ascending: false)
        ]

        do {
            availableFolders = try _viewContext.fetch(request)
            #if DEBUG
            print("📝 NoteDetailsViewModel: Fetched \(availableFolders.count) folders")
            #endif
        } catch {
            #if DEBUG
            print("📝 NoteDetailsViewModel: Error fetching folders - \(error)")
            #endif
            errorMessage = "Failed to load folders: \(error.localizedDescription)"
        }
    }

    func saveChanges() async throws {
        isLoading = true
        defer { isLoading = false }

        #if DEBUG
        print("📝 NoteDetailsViewModel: Saving changes for note: \(note.title)")
        #endif

        let request = NSFetchRequest<NSManagedObject>(entityName: "Note")
        request.predicate = NSPredicate(format: "id == %@", note.id as CVarArg)

        do {
            guard let noteObject = try _viewContext.fetch(request).first else {
                throw NSError(domain: "NoteDetails", code: 404,
                            userInfo: [NSLocalizedDescriptionKey: "Note not found"])
            }

            // Update note properties
            noteObject.setValue(note.title, forKey: "title")

            // Update lastModified timestamp for "Last Write Wins" conflict resolution
            noteObject.setValue(Date(), forKey: "lastModified")

            // Mark note for sync by setting syncStatus to "pending"
            noteObject.setValue("pending", forKey: "syncStatus")

            try _viewContext.save()

            #if DEBUG
            print("📝 NoteDetailsViewModel: Successfully saved changes and marked for sync")
            #endif
        } catch {
            #if DEBUG
            print("📝 NoteDetailsViewModel: Error saving changes - \(error.localizedDescription)")
            #endif
            throw error
        }
    }

    func exportPDF() async throws {
        #if DEBUG
        print("📄 NoteDetailsViewModel: Starting PDF export")
        #endif

        isExporting = true
        defer { isExporting = false }

        let url = try await pdfExportService.exportNote(note)
        let savedURL = try await pdfExportService.savePDF(url, withName: note.title)
        exportURL = ExportURLWrapper(url: savedURL)

        #if DEBUG
        print("📄 NoteDetailsViewModel: PDF export completed successfully")
        #endif
    }

    func moveToFolder(_ folder: Folder?) async throws {
        #if DEBUG
        print("📝 NoteDetailsViewModel: Moving note to folder: \(folder?.name ?? "root")")
        #endif

        isLoading = true
        defer { isLoading = false }

        let request = NSFetchRequest<NSManagedObject>(entityName: "Note")
        request.predicate = NSPredicate(format: "id == %@", note.id as CVarArg)

        do {
            let results = try _viewContext.fetch(request)

            guard let noteObject = results.first as? Note else {
                throw NSError(domain: "NoteDetailsViewModel", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Could not find note with ID \(note.id)"
                ])
            }

            // Update folder
            noteObject.folder = folder

            // Update lastModified timestamp for "Last Write Wins" conflict resolution
            noteObject.lastModified = Date()

            // Mark note for sync by setting syncStatus to "pending"
            noteObject.syncStatus = "pending"

            // Save changes
            try _viewContext.save()

            // Update the note configuration
            note = NoteCardConfiguration(
                id: note.id,
                title: note.title,
                date: note.date,
                preview: note.preview,
                sourceType: note.sourceType,
                isFavorite: note.isFavorite,
                folder: folder,
                metadata: note.metadata,
                sourceURL: note.sourceURL
            )

            #if DEBUG
            print("📝 NoteDetailsViewModel: Successfully moved note to folder: \(folder?.name ?? "root")")
            #endif

            // Notify that notes should be refreshed
            NotificationCenter.default.post(name: .init("RefreshNotes"), object: nil)
        } catch {
            #if DEBUG
            print("📝 NoteDetailsViewModel: Error moving note - \(error)")
            #endif
            throw error
        }
    }
}

// MARK: - Note Details View
struct NoteDetailsView: View {
    @StateObject private var viewModel: NoteDetailsViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.toastManager) private var toastManager

    init(note: NoteCardConfiguration, context: NSManagedObjectContext) {
        _viewModel = StateObject(wrappedValue: NoteDetailsViewModel(note: note, context: context))

        #if DEBUG
        print("📝 NoteDetailsView: Initializing view for note: \(note.title)")
        #endif
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    // Header Section
                    headerSection

                    // Content Section
                    contentSection
                }
                .padding(.horizontal, Theme.Spacing.xs)
                .padding(.vertical, Theme.Spacing.md)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        #if DEBUG
                        print("📝 NoteDetailsView: Close button tapped")
                        #endif
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: Theme.Spacing.sm) {
                        // Folder button
                        Button(action: {
                            #if DEBUG
                            print("📁 NoteDetailsView: Folder button tapped")
                            #endif
                            viewModel.isShowingFolderPicker = true
                        }) {
                            Image(systemName: "folder")
                                .foregroundColor(Theme.Colors.primary)
                        }

                        Button(action: {
                            #if DEBUG
                            print("📄 NoteDetailsView: Export button tapped")
                            #endif
                            handleExport()
                        }) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(Theme.Colors.primary)
                        }
                        .disabled(viewModel.isExporting)

                        Button(viewModel.isEditing ? "Save" : "Edit") {
                            handleEditSave()
                        }
                    }
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView("Loading...")
                        .padding()
                        .background(Color.white.opacity(0.8))
                        .cornerRadius(Theme.Layout.cornerRadius)
                }
            }
            .sheet(isPresented: $viewModel.isShowingFolderPicker) {
                FolderPickerView(
                    folders: viewModel.availableFolders,
                    currentFolderName: viewModel.note.folderName,
                    onSelect: { selectedFolder in
                        moveNoteToFolder(selectedFolder)
                    }
                )
            }
            .sheet(item: $viewModel.exportURL) { wrapper in
                ShareSheet(items: [wrapper.url])
            }
        }
        .onAppear {
            #if DEBUG
            print("📝 NoteDetailsView: View appeared for note: \(viewModel.note.title)")
            #endif

            // Refresh the note to ensure we have the latest audio URL
            Task {
                await refreshNoteAudioURL()
            }
        }
        .onDisappear {
            #if DEBUG
            print("📝 NoteDetailsView: View disappeared for note: \(viewModel.note.title)")
            #endif
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                // Source icon with enhanced styling
                viewModel.note.sourceType.icon
                    .foregroundStyle(
                        LinearGradient(
                            colors: [viewModel.note.sourceType.color, viewModel.note.sourceType.color.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .font(.system(size: 28, weight: .bold))
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    if viewModel.isEditing {
                        TextField("Title", text: Binding(
                            get: { viewModel.note.title },
                            set: { newTitle in
                                #if DEBUG
                                print("📝 NoteDetailsView: Updating title to: \(newTitle)")
                                #endif
                                var updatedNote = viewModel.note
                                updatedNote.title = newTitle
                                viewModel.note = updatedNote
                            }
                        ))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Theme.Colors.text)
                    } else {
                        Text(viewModel.note.title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(Theme.Colors.text)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer()
            }

            // Metadata row with better spacing and styling
            HStack(spacing: Theme.Spacing.lg) {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.Colors.primary)

                    Text(viewModel.note.date, style: .date)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.Colors.secondaryText)
                }

                if let language = viewModel.note.language {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "globe")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.Colors.primary)

                        LanguageDisplay(language: language, compact: true)
                    }
                }

                Spacer()
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    // MARK: - Content Section
    private var contentSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Study Tabs
            NoteStudyTabs(note: viewModel.note)
        }
        .padding(.top, Theme.Spacing.md)
    }

    // MARK: - Helper Methods
    private func handleEditSave() {
        if viewModel.isEditing {
            Task {
                do {
                    try await viewModel.saveChanges()
                    await MainActor.run {
                        viewModel.isEditing = false
                        toastManager.show("Changes saved successfully", type: .success)
                    }
                } catch {
                    #if DEBUG
                    print("📝 NoteDetailsView: Error saving changes - \(error.localizedDescription)")
                    #endif
                    await MainActor.run {
                        toastManager.show("Failed to save changes", type: .error)
                    }
                }
            }
        } else {
            viewModel.isEditing = true
        }
    }

    private func handleExport() {
        Task {
            do {
                try await viewModel.exportPDF()
                toastManager.show("PDF exported successfully", type: .success)
            } catch {
                #if DEBUG
                print("📄 NoteDetailsView: PDF export failed - \(error)")
                #endif
                toastManager.show(error.localizedDescription, type: .error)
            }
        }
    }

    private func moveNoteToFolder(_ folder: Folder?) {
        #if DEBUG
        print("📝 NoteDetailsView: Moving note to folder: \(folder?.name ?? "root")")
        #endif

        Task {
            do {
                try await viewModel.moveToFolder(folder)
                let folderName = folder?.name ?? "All Notes"
                toastManager.show("Note moved to \(folderName)", type: .success)
            } catch {
                #if DEBUG
                print("📝 NoteDetailsView: Error moving note - \(error)")
                #endif
                toastManager.show("Failed to move note: \(error.localizedDescription)", type: .error)
            }
        }
    }

    private func refreshNoteAudioURL() async {
        #if DEBUG
        print("📝 NoteDetailsView: Refreshing note audio URL")
        #endif

        // Only proceed for audio and recording notes
        guard viewModel.note.sourceType == .audio || viewModel.note.sourceType == .recording else {
            return
        }

        // Fetch the note from Core Data to get the latest sourceURL
        let request = NSFetchRequest<Note>(entityName: "Note")
        request.predicate = NSPredicate(format: "id == %@", viewModel.note.id as CVarArg)

        do {
            let results = try viewModel.viewContext.fetch(request)

            guard let noteObject = results.first else {
                #if DEBUG
                print("📝 NoteDetailsView: Note not found in database")
                #endif
                return
            }

            // Get the sourceURL from Core Data
            if let sourceURL = noteObject.sourceURL {
                #if DEBUG
                print("📝 NoteDetailsView: Found sourceURL in database: \(sourceURL)")
                #endif

                // Check if the file exists at this URL
                if FileManager.default.fileExists(atPath: sourceURL.path) {
                    #if DEBUG
                    print("📝 NoteDetailsView: File exists at sourceURL path")
                    #endif

                    // Update the note configuration with the correct URL
                    await MainActor.run {
                        var updatedNote = viewModel.note
                        updatedNote.sourceURL = sourceURL
                        viewModel.note = updatedNote
                    }
                } else {
                    #if DEBUG
                    print("📝 NoteDetailsView: File does not exist at sourceURL path, trying alternative")
                    #endif

                    // Try to find the file by UUID
                    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

                    // Try multiple possible filename formats
                    let noteId = viewModel.note.id
                    let originalFilename = sourceURL.lastPathComponent

                    // Possible filenames to try
                    var possibleFilenames = [
                        "\(noteId).m4a",                      // Standard format for recorded files
                        "\(noteId)-\(originalFilename)",      // Possible format with note ID prefix
                        originalFilename                      // Original filename
                    ]

                    // If we can extract a UUID from the filename, try those formats too
                    if let uuid = extractUUID(from: originalFilename) {
                        let uuidFilenames = [
                            "\(uuid).m4a",                     // Simple UUID format
                            "\(uuid)-\(originalFilename)"      // UUID-prefixed format for imported files
                        ]
                        possibleFilenames.append(contentsOf: uuidFilenames)
                    }

                    #if DEBUG
                    print("📝 NoteDetailsView: Trying multiple possible filenames: \(possibleFilenames)")
                    #endif

                    // Try each possible filename
                    for filename in possibleFilenames {
                        let alternativeURL = documentsPath.appendingPathComponent(filename)

                        #if DEBUG
                        print("📝 NoteDetailsView: Checking path: \(alternativeURL.path)")
                        print("📝 NoteDetailsView: File exists: \(FileManager.default.fileExists(atPath: alternativeURL.path))")
                        #endif

                        if FileManager.default.fileExists(atPath: alternativeURL.path) {
                            #if DEBUG
                            print("📝 NoteDetailsView: File found at alternative path: \(alternativeURL.path)")
                            #endif

                            // Update the note in Core Data with the correct URL
                            noteObject.sourceURL = alternativeURL
                            try viewModel.viewContext.save()

                            // Update the note configuration
                            await MainActor.run {
                                var updatedNote = viewModel.note
                                updatedNote.sourceURL = alternativeURL
                                viewModel.note = updatedNote
                            }

                            // Found a working file, no need to try more
                            break
                        }
                    }
                }
            }
        } catch {
            #if DEBUG
            print("📝 NoteDetailsView: Error refreshing audio URL - \(error)")
            #endif
        }
    }

    // Extract UUID from filename
    private func extractUUID(from filename: String) -> UUID? {
        // Try to find a UUID pattern in the filename
        let pattern = "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}"
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)

        if let match = regex?.firstMatch(in: filename, options: [], range: NSRange(location: 0, length: filename.count)) {
            let matchRange = match.range
            if let range = Range(matchRange, in: filename) {
                let uuidString = String(filename[range])
                return UUID(uuidString: uuidString)
            }
        }
        return nil
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        #if DEBUG
        print("📄 ShareSheet: Creating activity view controller")
        #endif
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Folder Picker View
struct FolderPickerView: View {
    let folders: [Folder]
    let currentFolderName: String?
    let onSelect: (Folder?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                // List of folders (including "All Notes" as the default/root folder)
                ForEach(folders) { folder in
                    Button(action: {
                        // If selecting "All Notes", pass nil to remove from specific folder
                        if folder.name == "All Notes" {
                            onSelect(nil)
                        } else {
                            onSelect(folder)
                        }
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(Color(folder.color ?? "FolderBlue"))

                            Text(folder.name ?? "Unnamed Folder")

                            Spacer()

                            // Show checkmark for current folder or "All Notes" if no folder assigned
                            if (currentFolderName == folder.name) ||
                               (currentFolderName == nil && folder.name == "All Notes") {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Theme.Colors.primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview Provider
#if DEBUG
struct NoteDetailsView_Previews: PreviewProvider {
    static var previewNote: NoteCardConfiguration {
        NoteCardConfiguration(
            title: "Weekly Team Meeting",
            date: Date(),
            preview: """
            Discussed Q4 goals and project timeline:
            - Mobile app release scheduled for December
            - New feature prioritization complete
            - Team capacity planning for Q1
            - Budget review and resource allocation

            Action items:
            1. Follow up with design team on UI specs
            2. Schedule technical review for security features
            3. Update project documentation
            """,
            sourceType: .audio,
            isFavorite: true,
            metadata: [
                "duration": 180.0
            ]
        )
    }

    static var previews: some View {
        Group {
            // Default state
            NoteDetailsView(
                note: previewNote,
                context: PersistenceController.preview.container.viewContext
            )
            .previewDisplayName("Default State")

            // Audio note with editing
            NoteDetailsView(
                note: previewNote,
                context: PersistenceController.preview.container.viewContext
            )
            .onAppear {
                let vm = NoteDetailsViewModel(note: previewNote,
                                          context: PersistenceController.preview.container.viewContext)
                vm.isEditing = true
            }
            .previewDisplayName("Editing State")

            // Loading state
            NoteDetailsView(
                note: previewNote,
                context: PersistenceController.preview.container.viewContext
            )
            .onAppear {
                let vm = NoteDetailsViewModel(note: previewNote,
                                          context: PersistenceController.preview.container.viewContext)
                vm.isLoading = true
            }
            .previewDisplayName("Loading State")
        }
        .environment(\.colorScheme, .light)
    }
}
#endif
