import SwiftUI
import CoreData
import Combine
import UniformTypeIdentifiers

// MARK: - Text Upload Error
enum TextUploadError: LocalizedError {
    case invalidFile
    case readError(Error)
    case emptyContent
    case fileTooBig(Int64)
    case unsupportedFileType(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidFile:
            return "Invalid file selected"
        case .readError(let error):
            return "Failed to read file: \(error.localizedDescription)"
        case .emptyContent:
            return "File contains no text content"
        case .fileTooBig(let size):
            return "File too large (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))"
        case .unsupportedFileType(let ext):
            return "Unsupported file type: \(ext)"
        }
    }
}

// MARK: - Text Upload Stats
struct TextStats {
    let wordCount: Int
    let charCount: Int
    let lineCount: Int
    let fileSize: Int64
    
    init(text: String, fileSize: Int64) {
        self.wordCount = text.split(separator: " ").count
        self.charCount = text.count
        self.lineCount = text.components(separatedBy: .newlines).count
        self.fileSize = fileSize
    }
}

// MARK: - Text Upload ViewModel
@MainActor
final class TextUploadViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var textContent: String = ""
    @Published var selectedFileName: String?
    @Published var stats: TextStats?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var saveLocally = false
    @Published private(set) var loadingState: LoadingState = .idle
    
    // MARK: - Private Properties
    private let viewContext: NSManagedObjectContext
    let supportedTypes: [UTType] = [.text, .plainText, .rtf, .pdf]
    private var originalFileURL: URL?
    
    init(context: NSManagedObjectContext) {
        self.viewContext = context
        
        #if DEBUG
        print("📄 TextUploadVM: Initializing")
        #endif
    }
    
    // MARK: - File Processing
    func processSelectedFile(_ url: URL) async throws {
        loadingState = .loading(message: "Reading file...")
        
        do {
            guard url.startAccessingSecurityScopedResource() else {
                throw TextUploadError.invalidFile
            }
            
            defer {
                url.stopAccessingSecurityScopedResource()
            }
            
            let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            
            // Arbitrary 10MB limit for text files
            if fileSize > 10_000_000 {
                throw TextUploadError.fileTooBig(Int64(fileSize))
            }
            
            // Read file content
            let content = try await readFileContent(from: url)
            guard !content.isEmpty else {
                throw TextUploadError.emptyContent
            }
            
            await MainActor.run {
                self.textContent = content
                self.selectedFileName = url.lastPathComponent
                self.stats = TextStats(text: content, fileSize: Int64(fileSize))
                self.originalFileURL = url
                self.loadingState = .success(message: "File loaded successfully")
            }
            
            #if DEBUG
            print("📄 TextUploadVM: File processed successfully - Size: \(fileSize) bytes")
            #endif
        } catch {
            #if DEBUG
            print("📄 TextUploadVM: Error processing file - \(error)")
            #endif
            loadingState = .error(message: error.localizedDescription)
            throw error
        }
    }
    
    // MARK: - File Reading
    private func readFileContent(from url: URL) async throws -> String {
        // Handle different file types
        switch url.pathExtension.lowercased() {
        case "txt", "rtf", "md":
            return try String(contentsOf: url, encoding: .utf8)
            
        case "pdf":
            // For PDF, we'd use PDFKit to extract text
            // This is a placeholder for now
            throw TextUploadError.unsupportedFileType("PDF")
            
        default:
            throw TextUploadError.unsupportedFileType(url.pathExtension)
        }
    }
    
    // MARK: - Save Note
    func saveNote(title: String) async throws {
        guard !textContent.isEmpty else {
            throw TextUploadError.emptyContent
        }
        
        try await viewContext.perform { [weak self] in
            guard let self = self else { return }
            
            let note = NSEntityDescription.insertNewObject(forEntityName: "Note", into: self.viewContext)
            note.setValue(title, forKey: "title")
            note.setValue(Date(), forKey: "timestamp")
            note.setValue("text", forKey: "sourceType")
            note.setValue(self.textContent, forKey: "content")
            
            if self.saveLocally, let originalURL = self.originalFileURL {
                // Save copy to app documents
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let destinationURL = documentsPath.appendingPathComponent(originalURL.lastPathComponent)
                try FileManager.default.copyItem(at: originalURL, to: destinationURL)
            }
            
            try self.viewContext.save()
            
            #if DEBUG
            print("📄 TextUploadVM: Note saved successfully")
            #endif
        }
    }
    
    // MARK: - Type Checking
    func canHandle(_ url: URL) -> Bool {
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return false
        }
        return supportedTypes.contains { type.conforms(to: $0) }
    }
}

// MARK: - Text Upload View
struct TextUploadView: View {
    @StateObject private var viewModel: TextUploadViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.toastManager) private var toastManager
    @State private var showingFilePicker = false
    @State private var showingSaveDialog = false
    @State private var noteTitle: String = ""
    
    init(context: NSManagedObjectContext) {
        self._viewModel = StateObject(wrappedValue: TextUploadViewModel(context: context))
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    // File Selection Button
                    if viewModel.selectedFileName == nil {
                        Button(action: {
                            #if DEBUG
                            print("📄 TextUploadView: Showing file picker")
                            #endif
                            showingFilePicker = true
                        }) {
                            VStack(spacing: Theme.Spacing.md) {
                                Image(systemName: "doc.badge.plus")
                                    .font(.system(size: 48))
                                    .foregroundColor(Theme.Colors.primary)
                                
                                Text("Select Text File")
                                    .font(Theme.Typography.body)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.xl)
                            .background(Theme.Colors.secondaryBackground)
                            .cornerRadius(Theme.Layout.cornerRadius)
                        }
                    }
                    
                    // Content Preview
                    if !viewModel.textContent.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                            // File Info Header
                            HStack {
                                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                                    Text(viewModel.selectedFileName ?? "Untitled")
                                        .font(Theme.Typography.h3)
                                    
                                    if let stats = viewModel.stats {
                                        Text("\(stats.wordCount) words • \(stats.charCount) characters")
                                            .font(Theme.Typography.caption)
                                            .foregroundColor(Theme.Colors.secondaryText)
                                    }
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    #if DEBUG
                                    print("📄 TextUploadView: Showing file picker for new file")
                                    #endif
                                    showingFilePicker = true
                                }) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .foregroundColor(Theme.Colors.primary)
                                }
                            }
                            
                            // Text Preview
                            Text(viewModel.textContent)
                                .font(Theme.Typography.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Theme.Colors.secondaryBackground)
                                .cornerRadius(Theme.Layout.cornerRadius)
                            
                            // Local Storage Toggle
                            Toggle("Save original file locally", isOn: $viewModel.saveLocally)
                                .padding()
                                .background(Theme.Colors.secondaryBackground)
                                .cornerRadius(Theme.Layout.cornerRadius)
                            
                            // Save Button
                            Button("Import Text") {
                                #if DEBUG
                                print("📄 TextUploadView: Showing save dialog")
                                #endif
                                showingSaveDialog = true
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Import Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        #if DEBUG
                        print("📄 TextUploadView: Canceling import")
                        #endif
                        dismiss()
                    }
                }
            }
            .alert("Save Note", isPresented: $showingSaveDialog) {
                TextField("Note Title", text: $noteTitle)
                Button("Cancel", role: .cancel) { }
                Button("Save") { saveNote() }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: viewModel.supportedTypes,
                allowsMultipleSelection: false
            ) { result in
                handleSelectedFile(result)
            }
            .overlay {
                if viewModel.isLoading {
                    LoadingIndicator(message: "Processing file...")
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    private func handleSelectedFile(_ result: Result<[URL], Error>) {
        Task {
            do {
                let urls = try result.get()
                guard let url = urls.first else { return }
                
                if viewModel.canHandle(url) {
                    try await viewModel.processSelectedFile(url)
                } else {
                    throw TextUploadError.unsupportedFileType(url.pathExtension)
                }
            } catch {
                toastManager.show(error.localizedDescription, type: .error)
            }
        }
    }
    
    private func saveNote() {
        guard !noteTitle.isEmpty else {
            toastManager.show("Please enter a title", type: .warning)
            return
        }
        
        Task {
            do {
                try await viewModel.saveNote(title: noteTitle)
                toastManager.show("Text imported successfully", type: .success)
                dismiss()
            } catch {
                toastManager.show(error.localizedDescription, type: .error)
            }
        }
    }
}

// MARK: - Preview Provider
#if DEBUG
struct TextUploadView_Previews: PreviewProvider {
    static var previews: some View {
        TextUploadView(context: PersistenceController.preview.container.viewContext)
    }
}
#endif
