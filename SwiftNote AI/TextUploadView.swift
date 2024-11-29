import SwiftUI
import UniformTypeIdentifiers
import CoreData
import Combine
import PDFKit
import Vision
import UIKit
import Foundation

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

// MARK: - Document Stats
private struct DocumentStats {
    let wordCount: Int
    let characterCount: Int
    let pageCount: Int
    
    static let empty = DocumentStats(wordCount: 0, characterCount: 0, pageCount: 0)
    
    static func calculate(from text: String) -> DocumentStats {
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let characters = text.filter { !$0.isWhitespace }
        // Rough estimate of pages based on average words per page
        let pages = max(1, Int(ceil(Double(words.count) / 250.0)))
        
        return DocumentStats(
            wordCount: words.count,
            characterCount: characters.count,
            pageCount: pages
        )
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
    let supportedTypes: [UTType] = [.text, .plainText, .rtf, .pdf, 
                                   UTType("com.microsoft.word.doc")!,
                                   UTType("org.openxmlformats.wordprocessingml.document")!,
                                   UTType("net.daringfireball.markdown")!]
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
            guard let pdf = CGPDFDocument(url as CFURL),
                  let page = pdf.page(at: 1) else {
                throw TextUploadError.readError(NSError(domain: "PDFError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to read PDF"]))
            }
            
            let pageRect = page.getBoxRect(.mediaBox)
            let renderer = UIGraphicsImageRenderer(size: pageRect.size)
            let img = renderer.image { ctx in
                UIColor.white.set()
                ctx.fill(pageRect)
                
                ctx.cgContext.translateBy(x: 0.0, y: pageRect.size.height)
                ctx.cgContext.scaleBy(x: 1.0, y: -1.0)
                
                ctx.cgContext.drawPDFPage(page)
            }
            
            let requestHandler = VNImageRequestHandler(cgImage: img.cgImage!, options: [:])
            let request = VNRecognizeTextRequest()
            try requestHandler.perform([request])
            
            guard let observations = request.results else {
                throw TextUploadError.readError(NSError(domain: "OCRError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No text found in PDF"]))
            }
            
            return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            
        case "doc", "docx":
            // For iOS, we'll use NSAttributedString to read Word documents
            let options = [NSAttributedString.DocumentReadingOptionKey.documentType: NSAttributedString.DocumentType.rtfd]
            let data = try Data(contentsOf: url)
            
            if let attributedString = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
                return attributedString.string
            }
            
            // Fallback to trying RTF if RTFD fails
            let rtfOptions = [NSAttributedString.DocumentReadingOptionKey.documentType: NSAttributedString.DocumentType.rtf]
            if let attributedString = try? NSAttributedString(data: data, options: rtfOptions, documentAttributes: nil) {
                return attributedString.string
            }
            
            throw TextUploadError.readError(NSError(domain: "DocumentError", 
                                                  code: -1, 
                                                  userInfo: [NSLocalizedDescriptionKey: "Unable to read document content"]))
            
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
    
    func getFileSize(for url: URL) -> String? {
        guard let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return nil
        }
        return ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }
}

// MARK: - Document Picker
struct DocumentPicker: UIViewControllerRepresentable {
    let types: [UTType]
    let onResult: (Result<[URL], Error>) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        
        init(_ parent: DocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.onResult(.success(urls))
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onResult(.failure(NSError(domain: "DocumentPicker", code: -1, userInfo: [NSLocalizedDescriptionKey: "Document picker was cancelled"])))
        }
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
    @State private var documentStats: DocumentStats = .empty
    @State private var selectedFile: URL?
    
    init(context: NSManagedObjectContext) {
        self._viewModel = StateObject(wrappedValue: TextUploadViewModel(context: context))
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    headerSection
                    
                    if selectedFile == nil {
                        fileSelectionSection
                    } else if let file = selectedFile {
                        previewSection(for: file)
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingFilePicker) {
                DocumentPicker(types: viewModel.supportedTypes, onResult: handleSelectedFile)
            }
            .alert("Save Note", isPresented: $showingSaveDialog) {
                TextField("Note Title", text: $noteTitle)
                Button("Cancel", role: .cancel) { }
                Button("Save") { saveNote() }
            }
        }
    }
    
    // MARK: - View Components
    
    private var headerSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "doc.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.Colors.primary, Theme.Colors.primary.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.top, Theme.Spacing.xl)
            
            Text("Import Text Document")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(Theme.Colors.text)
            
            Text("Import text from files like TXT, RTF, DOC or PDF")
                .font(.body)
                .foregroundColor(Theme.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
    
    private var fileSelectionSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            Button(action: { showingFilePicker = true }) {
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 48))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Theme.Colors.primary, Theme.Colors.primary.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("Select Document")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.xl)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius)
                        .fill(Theme.Colors.secondaryBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius)
                                .stroke(Theme.Colors.tertiaryBackground, lineWidth: 1)
                        )
                )
            }
            
            // Supported Formats Section
            VStack(spacing: Theme.Spacing.sm) {
                Text("Supported Formats")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
                
                HStack(spacing: Theme.Spacing.md) {
                    ForEach(["TXT", "RTF", "DOC", "DOCX", "PDF"], id: \.self) { format in
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green.gradient)
                            Text(format)
                        }
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                    }
                }
            }
            .padding()
            .background(Theme.Colors.secondaryBackground)
            .cornerRadius(Theme.Layout.cornerRadius)
        }
    }
    
    private func previewSection(for file: URL) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            // File Info Section
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text(file.lastPathComponent)
                            .font(Theme.Typography.h3)
                            .foregroundColor(Theme.Colors.text)
                        
                        if let fileSize = viewModel.getFileSize(for: file) {
                            Text(fileSize)
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.secondaryText)
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: { showingFilePicker = true }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 20))
                            .foregroundStyle(.blue.gradient)
                    }
                }
                .padding()
                .background(Theme.Colors.secondaryBackground)
                .cornerRadius(Theme.Layout.cornerRadius)
            }
            
            // Document Stats Section
            HStack(spacing: Theme.Spacing.lg) {
                StatItem(title: "Words", value: "\(documentStats.wordCount)")
                
                Divider()
                    .frame(height: 40)
                
                StatItem(title: "Characters", value: "\(documentStats.characterCount)")
                
                Divider()
                    .frame(height: 40)
                
                StatItem(title: "Pages", value: String(format: "%.1f", documentStats.pageCount))
            }
            .padding()
            .background(Theme.Colors.secondaryBackground)
            .cornerRadius(Theme.Layout.cornerRadius)
            
            // Save Options
            Toggle("Save original file locally", isOn: $viewModel.saveLocally)
                .padding()
                .background(Theme.Colors.secondaryBackground)
                .cornerRadius(Theme.Layout.cornerRadius)
            
            Button(action: { showingSaveDialog = true }) {
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    HStack {
                        Text("Import Document")
                        Image(systemName: "arrow.right.circle.fill")
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(viewModel.isLoading ? Theme.Colors.primary.opacity(0.5) : Theme.Colors.primary)
            .foregroundColor(.white)
            .cornerRadius(Theme.Layout.cornerRadius)
            .disabled(viewModel.isLoading)
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
                    selectedFile = url
                    
                    // Calculate document stats
                    if let content = try? String(contentsOf: url, encoding: .utf8) {
                        documentStats = DocumentStats.calculate(from: content)
                    }
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

// MARK: - Stat Item View
private struct StatItem: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: Theme.Spacing.xxs) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
            Text(value)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.text)
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
