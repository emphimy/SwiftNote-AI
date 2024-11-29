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
    @FocusState private var isURLFieldFocused: Bool
    @State private var showSupportedLinks = false
    
    init(context: NSManagedObjectContext) {
        self._viewModel = StateObject(wrappedValue: WebLinkImportViewModel(context: context))
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    // Header Section
                    VStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "link.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Theme.Colors.primary, Theme.Colors.primary.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .padding(.top, Theme.Spacing.xl)
                        
                        Text("Import Web Content")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.Colors.text)
                        
                        Text("Paste a URL to import content with supported audio or document")
                            .font(.body)
                            .foregroundColor(Theme.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    // URL Input Section
                    VStack(spacing: Theme.Spacing.md) {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "link")
                                .foregroundColor(isURLFieldFocused ? Theme.Colors.primary : .gray)
                                .animation(.easeInOut, value: isURLFieldFocused)
                            
                            TextField("Enter URL", text: $viewModel.urlInput)
                                .textFieldStyle(PlainTextFieldStyle())
                                .autocapitalization(.none)
                                .focused($isURLFieldFocused)
                            
                            if !viewModel.urlInput.isEmpty {
                                Button(action: { viewModel.urlInput = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                }
                                .transition(.scale.combined(with: .opacity))
                            }
                            
                            Button(action: {
                                if let clipboardString = UIPasteboard.general.string {
                                    viewModel.urlInput = clipboardString
                                }
                            }) {
                                Image(systemName: "doc.on.clipboard")
                                    .foregroundColor(Theme.Colors.primary)
                            }
                        }
                        .padding()
                        .background(Theme.Colors.secondaryBackground)
                        .cornerRadius(Theme.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius)
                                .stroke(isURLFieldFocused ? Theme.Colors.primary : Color.clear, lineWidth: 1)
                        )
                        .animation(.easeInOut, value: isURLFieldFocused)
                        
                        Button(action: {
                            Task {
                                await viewModel.processURL()
                            }
                        }) {
                            HStack {
                                Text("Import Content")
                                Image(systemName: "arrow.right.circle.fill")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(viewModel.urlInput.isEmpty ? Theme.Colors.primary.opacity(0.5) : Theme.Colors.primary)
                            .foregroundColor(.white)
                            .cornerRadius(Theme.Layout.cornerRadius)
                        }
                        .disabled(viewModel.urlInput.isEmpty)
                    }
                    .padding(.horizontal)
                    
                    // Progress Indicator
                    if case .loading(let message) = viewModel.loadingState {
                        VStack(spacing: Theme.Spacing.md) {
                            ProgressView()
                                .scaleEffect(1.2)
                            if let message = message {
                                Text(message)
                                    .font(.caption)
                                    .foregroundColor(Theme.Colors.secondaryText)
                            }
                            
                            if viewModel.downloadProgress > 0 {
                                ProgressView(value: viewModel.downloadProgress)
                                    .progressViewStyle(.linear)
                                    .tint(Theme.Colors.primary)
                            }
                        }
                        .padding()
                        .background(Theme.Colors.secondaryBackground)
                        .cornerRadius(Theme.Layout.cornerRadius)
                        .padding(.horizontal)
                    }
                }
            }
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
