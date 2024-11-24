import SwiftUI
import CoreData
import UniformTypeIdentifiers

// MARK: - Cloud Storage Import View Model
@MainActor
final class CloudStorageImportViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var urlInput: String = ""
    @Published var noteTitle: String = ""
    @Published var saveLocally = false
    @Published var showingSaveDialog = false
    @Published var downloadedFileURL: URL?
    @Published private(set) var loadingState: LoadingState = .idle
    
    // MARK: - Private Properties
    private let viewContext: NSManagedObjectContext
    private let cloudService = CloudStorageService()
    private let supportedTypes = [UTType.audio, UTType.plainText, UTType.pdf]
    private var cleanupURL: URL?
    private var isCleanedUp = false
    
    init(context: NSManagedObjectContext) {
        self.viewContext = context
        
        #if DEBUG
        print("☁️ CloudStorageImportVM: Initializing with context")
        #endif
    }
    
    // MARK: - URL Processing
    func processURL() async {
        guard !urlInput.isEmpty else {
            #if DEBUG
            print("☁️ CloudStorageImportVM: Empty URL input")
            #endif
            loadingState = .error(message: "Please enter a URL")
            return
        }
        
        do {
            let fileURL = try await cloudService.downloadFile(from: urlInput)
            
            // Fix file type validation
            if let contentType = try? fileURL.resourceValues(forKeys: [.contentTypeKey]).contentType {
                let isSupported = supportedTypes.contains { type in
                    contentType.conforms(to: type)
                }
                
                guard isSupported else {
                    throw CloudStorageError.unsupportedFileType(fileURL.pathExtension)
                }
            } else {
                throw CloudStorageError.unsupportedFileType(fileURL.pathExtension)
            }
            
            await MainActor.run {
                self.downloadedFileURL = fileURL
                self.showingSaveDialog = true
                self.loadingState = .success(message: "File downloaded successfully")
            }
            
            #if DEBUG
            print("☁️ CloudStorageImportVM: File downloaded and validated successfully")
            #endif
            
        } catch {
            #if DEBUG
            print("☁️ CloudStorageImportVM: Error processing URL - \(error)")
            #endif
            loadingState = .error(message: error.localizedDescription)
        }
    }
    
    // MARK: - Save Methods
    func saveNote() async throws {
        guard let fileURL = downloadedFileURL else {
            #if DEBUG
            print("☁️ CloudStorageImportVM: No file URL available")
            #endif
            throw CloudStorageError.invalidURL
        }
        
        guard !noteTitle.isEmpty else {
            #if DEBUG
            print("☁️ CloudStorageImportVM: Empty note title")
            #endif
            throw NSError(domain: "CloudStorageImport",
                         code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Please enter a title"])
        }
        
        loadingState = .loading(message: "Saving note...")
        
        do {
            try await viewContext.perform { [weak self] in
                guard let self = self else { return }
                
                let note = NSEntityDescription.insertNewObject(forEntityName: "Note", into: self.viewContext)
                note.setValue(self.noteTitle, forKey: "title")
                note.setValue(Date(), forKey: "timestamp")
                
                // Determine source type based on file type
                let sourceType: String
                if let fileType = try? fileURL.resourceValues(forKeys: [.contentTypeKey]).contentType {
                    if fileType.conforms(to: .audio) {
                        sourceType = "audio"
                    } else if fileType.conforms(to: .plainText) {
                        sourceType = "text"
                    } else {
                        sourceType = "upload"
                    }
                } else {
                    sourceType = "upload"
                }
                note.setValue(sourceType, forKey: "sourceType")
                
                if self.saveLocally {
                    // Move file to permanent storage
                    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let destinationURL = documentsPath.appendingPathComponent("\(UUID().uuidString).\(fileURL.pathExtension)")
                    try FileManager.default.copyItem(at: fileURL, to: destinationURL)
                    
                    #if DEBUG
                    print("☁️ CloudStorageImportVM: File saved to permanent storage at \(destinationURL)")
                    #endif
                }
                
                try self.viewContext.save()
                
                #if DEBUG
                print("☁️ CloudStorageImportVM: Note saved successfully")
                #endif
            }
            
            loadingState = .success(message: "Note saved successfully")
            
        } catch {
            #if DEBUG
            print("☁️ CloudStorageImportVM: Error saving note - \(error)")
            #endif
            loadingState = .error(message: error.localizedDescription)
            throw error
        }
    }
    
    // MARK: - Cleanup
    func cleanup() {
        #if DEBUG
        print("☁️ CloudStorageImportVM: Starting cleanup")
        #endif
        
        // Store URL for cleanup
        let urlToClean = downloadedFileURL
        
        // Clear state
        downloadedFileURL = nil
        cleanupURL = nil
        loadingState = .idle
        urlInput = ""
        noteTitle = ""
        saveLocally = false
        showingSaveDialog = false
        
        // Perform file cleanup if needed
        if let fileURL = urlToClean {
            do {
                try FileManager.default.removeItem(at: fileURL)
                #if DEBUG
                print("☁️ CloudStorageImportVM: Successfully cleaned up file at \(fileURL)")
                #endif
            } catch {
                #if DEBUG
                print("☁️ CloudStorageImportVM: Error cleaning up file - \(error)")
                #endif
            }
        }
    }
        
    deinit {
        #if DEBUG
        print("☁️ CloudStorageImportVM: Starting deinit")
        #endif
        
        // Create a task that won't capture self
        let urlToCleanup = cleanupURL
        Task {
            if let fileURL = urlToCleanup {
                do {
                    try FileManager.default.removeItem(at: fileURL)
                    #if DEBUG
                    print("☁️ CloudStorageImportVM: Successfully cleaned up file at \(fileURL)")
                    #endif
                } catch {
                    #if DEBUG
                    print("☁️ CloudStorageImportVM: Failed to cleanup file - \(error)")
                    #endif
                }
            }
            
            #if DEBUG
            print("☁️ CloudStorageImportVM: Deinit cleanup completed")
            #endif
        }
    }
        
    // Add new private cleanup method
    private func performCleanup() async {
        await MainActor.run {
            cleanup()
            #if DEBUG
            print("☁️ CloudStorageImportVM: Deinit cleanup completed")
            #endif
        }
    }
}

// MARK: - Cloud Storage Import View
struct CloudStorageImportView: View {
    @StateObject private var viewModel: CloudStorageImportViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.toastManager) private var toastManager
    
    let storageProvider: HomeViewModel.CloudStorageProvider
    
    init(context: NSManagedObjectContext, provider: HomeViewModel.CloudStorageProvider) {
        self._viewModel = StateObject(wrappedValue: CloudStorageImportViewModel(context: context))
        self.storageProvider = provider
        
        #if DEBUG
        print("☁️ CloudStorageImportView: Initializing with provider: \(provider)")
        #endif
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    // URL Input Section
                    urlInputSection
                    
                    // Processing Status
                    if case .loading(let message) = viewModel.loadingState {
                        LoadingIndicator(message: message)
                    }
                    
                    // Local Storage Toggle
                    if viewModel.downloadedFileURL != nil {
                        Toggle("Save file locally", isOn: $viewModel.saveLocally)
                            .padding()
                            .background(Theme.Colors.secondaryBackground)
                            .cornerRadius(Theme.Layout.cornerRadius)
                    }
                    
                    // Help Text
                    helpText
                }
                .padding()
            }
            .navigationTitle(storageProvider == .googleDrive ? "Google Drive" : "Dropbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        #if DEBUG
                        print("☁️ CloudStorageImportView: Cancel button tapped")
                        #endif
                        viewModel.cleanup()
                        dismiss()
                    }
                }
            }
            .alert("Save Note", isPresented: $viewModel.showingSaveDialog) {
                TextField("Note Title", text: $viewModel.noteTitle)
                Button("Cancel", role: .cancel) {
                    #if DEBUG
                    print("☁️ CloudStorageImportView: Save dialog cancelled")
                    #endif
                    viewModel.cleanup()
                }
                Button("Save") {
                    saveNote()
                }
            }
            .onChange(of: viewModel.loadingState) { state in
                if case .error(let message) = state {
                    toastManager.show(message, type: .error)
                }
            }
        }
    }
    
    // MARK: - View Components
    private var urlInputSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Shared URL")
                .font(Theme.Typography.h3)
            
            HStack {
                CustomTextField(
                    placeholder: storageProvider == .googleDrive ? 
                        "https://drive.google.com/..." :
                        "https://dropbox.com/...",
                    text: $viewModel.urlInput,
                    keyboardType: .URL
                )
                
                // Paste Button
                Button(action: {
                    #if DEBUG
                    print("☁️ CloudStorageImportView: Paste button tapped")
                    #endif
                    if let clipboardString = UIPasteboard.general.string {
                        viewModel.urlInput = clipboardString
                    }
                }) {
                    Image(systemName: "doc.on.clipboard")
                        .foregroundColor(Theme.Colors.primary)
                }
                .padding(.horizontal, Theme.Spacing.sm)
            }
            
            Button("Process URL") {
                #if DEBUG
                print("☁️ CloudStorageImportView: Process URL button tapped")
                #endif
                Task {
                    await viewModel.processURL()
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(viewModel.urlInput.isEmpty)
        }
    }
    
    private var helpText: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Supported Files:")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
            
            Text("• Audio files (MP3, M4A, WAV)\n• Text files (TXT, RTF)\n• PDF documents")
                .font(Theme.Typography.small)
                .foregroundColor(Theme.Colors.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.Colors.secondaryBackground)
        .cornerRadius(Theme.Layout.cornerRadius)
    }
    
    // MARK: - Helper Methods
    private func saveNote() {
        Task {
            do {
                try await viewModel.saveNote()
                dismiss()
                toastManager.show("Note saved successfully", type: .success)
            } catch {
                toastManager.show(error.localizedDescription, type: .error)
            }
        }
    }
}
