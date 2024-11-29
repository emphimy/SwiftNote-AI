import SwiftUI
import CoreData

// MARK: - Web Link Import View Model
@MainActor
final class WebLinkImportViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var urlInput: String = ""
    @Published var noteTitle: String = ""
    @Published var downloadProgress: Double = 0
    @Published var downloadedFileURL: URL?
    @Published var showingSaveDialog = false
    @Published private(set) var loadingState: LoadingState = .idle
    
    // MARK: - Private Properties
    private let viewContext: NSManagedObjectContext
    private let webLinkService = WebLinkService()
    private var cleanupURL: URL?
    
    init(context: NSManagedObjectContext) {
        self.viewContext = context
        
        #if DEBUG
        print("🌐 WebLinkImportVM: Initializing with context")
        #endif
    }
    
    // MARK: - URL Processing
    func processURL() async {
        guard !urlInput.isEmpty else {
            loadingState = .error(message: "Please enter a URL")
            return
        }
        
        do {
            loadingState = .loading(message: "Downloading content...")
            
            let fileURL = try await webLinkService.downloadContent(from: urlInput) { progress in
                Task { @MainActor in
                    self.downloadProgress = progress
                    self.loadingState = .loading(message: "Downloading... \(Int(progress * 100))%")
                }
            }
            
            await MainActor.run {
                self.downloadedFileURL = fileURL
                self.cleanupURL = fileURL
                self.showingSaveDialog = true
                self.loadingState = .success(message: "Content downloaded successfully")
            }
            
            #if DEBUG
            print("🌐 WebLinkImportVM: Download completed successfully")
            #endif
        } catch {
            #if DEBUG
            print("🌐 WebLinkImportVM: Error processing URL - \(error)")
            #endif
            loadingState = .error(message: error.localizedDescription)
        }
    }
    
    // MARK: - Save Methods
    func saveNote() async throws {
        guard let fileURL = downloadedFileURL else {
            throw WebLinkError.processingFailed("No content available")
        }
        
        guard !noteTitle.isEmpty else {
            throw WebLinkError.processingFailed("Please enter a title")
        }
        
        loadingState = .loading(message: "Saving note...")
        
        do {
            try await viewContext.perform { [weak self] in
                guard let self = self else { return }
                
                let note = NSEntityDescription.insertNewObject(forEntityName: "Note", into: self.viewContext)
                note.setValue(self.noteTitle, forKey: "title")
                note.setValue(Date(), forKey: "timestamp")
                note.setValue("web", forKey: "sourceType")
                note.setValue(self.urlInput, forKey: "sourceURL")
                
                // Save content
                let content = try Data(contentsOf: fileURL)
                note.setValue(content, forKey: "originalContent")
                
                try self.viewContext.save()
                
                #if DEBUG
                print("🌐 WebLinkImportVM: Note saved successfully")
                #endif
            }
            
            loadingState = .success(message: "Note saved successfully")
        } catch {
            #if DEBUG
            print("🌐 WebLinkImportVM: Error saving note - \(error)")
            #endif
            loadingState = .error(message: error.localizedDescription)
            throw error
        }
    }
    
    // MARK: - Cleanup
    func cleanup() {
        #if DEBUG
        print("🌐 WebLinkImportVM: Starting cleanup")
        #endif
        
        if let fileURL = cleanupURL {
            do {
                try FileManager.default.removeItem(at: fileURL)
                #if DEBUG
                print("🌐 WebLinkImportVM: Successfully cleaned up file at \(fileURL)")
                #endif
            } catch {
                #if DEBUG
                print("🌐 WebLinkImportVM: Error cleaning up file - \(error)")
                #endif
            }
        }
        
        webLinkService.cleanup()
    }
    
    deinit {
        #if DEBUG
        print("🌐 WebLinkImportVM: Deinitializing")
        #endif
        
        // Create a task that won't capture self
        let webLinkService = self.webLinkService
        if let fileURL = cleanupURL {
            Task { @MainActor in
                do {
                    try FileManager.default.removeItem(at: fileURL)
                    #if DEBUG
                    print("🌐 WebLinkImportVM: Successfully cleaned up file at \(fileURL)")
                    #endif
                } catch {
                    #if DEBUG
                    print("🌐 WebLinkImportVM: Error cleaning up file - \(error)")
                    #endif
                }
                webLinkService.cleanup()
            }
        } else {
            Task { @MainActor in
                webLinkService.cleanup()
            }
        }
    }
}

// MARK: - Web Link Import View
struct WebLinkImportView: View {
    @StateObject private var viewModel: WebLinkImportViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.toastManager) private var toastManager
    
    init(context: NSManagedObjectContext) {
        self._viewModel = StateObject(wrappedValue: WebLinkImportViewModel(context: context))
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    // URL Input Section
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        HStack {
                            Image(systemName: "link")
                                .foregroundColor(.gray)
                            TextField("Enter URL", text: $viewModel.urlInput)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .autocapitalization(.none)
                            
                            Button(action: {
                                if let clipboardString = UIPasteboard.general.string {
                                    viewModel.urlInput = clipboardString
                                }
                            }) {
                                Image(systemName: "doc.on.clipboard")
                                    .foregroundColor(Theme.Colors.primary)
                            }
                        }
                        
                        Button("Process URL") {
                            Task {
                                await viewModel.processURL()
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(viewModel.urlInput.isEmpty)
                    }
                    .padding()
                    
                    // Progress Indicator
                    if case .loading(let message) = viewModel.loadingState {
                        LoadingIndicator(message: message)
                    }
                    
                    // Supported Links Info
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Supported Links:")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.secondaryText)
                        
                        Text("• Dropbox\n• Google Drive\n• iCloud Drive\n• Google Docs")
                            .font(Theme.Typography.small)
                            .foregroundColor(Theme.Colors.tertiaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Theme.Colors.secondaryBackground)
                    .cornerRadius(Theme.Layout.cornerRadius)
                }
                .padding()
            }
            .navigationTitle("Import from Web")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        viewModel.cleanup()
                        dismiss()
                    }
                }
            }
            .alert("Save Note", isPresented: $viewModel.showingSaveDialog) {
                TextField("Note Title", text: $viewModel.noteTitle)
                Button("Cancel", role: .cancel) { }
                Button("Save") { saveNote() }
            }
        }
    }
    
    private func saveNote() {
        Task {
            do {
                try await viewModel.saveNote()
                dismiss()
                toastManager.show("Web content imported successfully", type: .success)
            } catch {
                toastManager.show(error.localizedDescription, type: .error)
            }
        }
    }
}
