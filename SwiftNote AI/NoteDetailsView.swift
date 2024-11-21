import SwiftUI
import CoreData
import AVKit
import Combine

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

    private let viewContext: NSManagedObjectContext
    private let pdfExportService = PDFExportService()
    
    init(note: NoteCardConfiguration, context: NSManagedObjectContext) {
        self.note = note
        self.viewContext = context
        
        #if DEBUG
        print("📝 NoteDetailsViewModel: Initializing with note: \(note.title)")
        #endif
    }
    
    func saveChanges() async throws {
        isLoading = true
        defer { isLoading = false }
        
        #if DEBUG
        print("📝 NoteDetailsViewModel: Saving changes for note: \(note.title)")
        #endif
        
        let request = NSFetchRequest<NSManagedObject>(entityName: "Note")
        request.predicate = NSPredicate(format: "title == %@ AND timestamp == %@",
                                      note.title, note.date as CVarArg)
        
        do {
            guard let noteObject = try viewContext.fetch(request).first else {
                throw NSError(domain: "NoteDetails", code: 404,
                            userInfo: [NSLocalizedDescriptionKey: "Note not found"])
            }
            
            // Update note properties
            noteObject.setValue(note.title, forKey: "title")
            noteObject.setValue(note.tags.joined(separator: ","), forKey: "tags")
            
            try viewContext.save()
            
            #if DEBUG
            print("📝 NoteDetailsViewModel: Successfully saved changes")
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
                    
                    // Tags Section
                    tagsSection
                }
                .padding(Theme.Spacing.md)
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
                    LoadingIndicator(message: "Saving changes...")
                }
            }
            .sheet(item: $viewModel.exportURL) { wrapper in
                ShareSheet(items: [wrapper.url])
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                viewModel.note.sourceType.icon
                    .foregroundColor(viewModel.note.sourceType.color)
                    .font(.title2)
                
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
                    .font(Theme.Typography.h2)
                } else {
                    Text(viewModel.note.title)
                        .font(Theme.Typography.h2)
                }
            }
            
            Text(viewModel.note.date, style: .date)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
        }
    }
    
    // MARK: - Content Section
    private var contentSection: some View {
        NoteStudyTabs(note: viewModel.note)
            .padding(.top, Theme.Spacing.md)
    }
    
    // MARK: - Tags Section
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Tags")
                .font(Theme.Typography.h3)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(viewModel.note.tags, id: \.self) { tag in
                        TagView(tag: tag) {
                            #if DEBUG
                            print("📝 NoteDetailsView: Tag selected: \(tag)")
                            #endif
                        }
                    }
                }
            }
        }
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
            tags: ["Work", "Meeting", "Planning", "Q4"]
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
