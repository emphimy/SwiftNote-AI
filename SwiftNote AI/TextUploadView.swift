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
    @Published var processingStatus: String = ""
    @Published var aiGeneratedContent: Data?
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
    private let aiService = AIProxyService.shared
    
    init(context: NSManagedObjectContext) {
        self.viewContext = context
        
        #if DEBUG
        print("📄 TextUploadVM: Initializing")
        #endif
    }
    
    // MARK: - File Processing
    func processSelectedFile(_ url: URL) async throws {
        isLoading = true
        processingStatus = "Reading file..."
        
        do {
            // Start accessing security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                throw TextUploadError.readError(NSError(domain: "FileAccessError", 
                                                      code: -1, 
                                                      userInfo: [NSLocalizedDescriptionKey: "Failed to access file"]))
            }
            
            defer {
                url.stopAccessingSecurityScopedResource()
            }
            
            // Validate file size
            let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            if fileSize > 50 * 1024 * 1024 { // 50MB limit
                throw TextUploadError.fileTooBig(Int64(fileSize))
            }
            
            // Store original URL for later use
            originalFileURL = url
            selectedFileName = url.lastPathComponent
            
            do {
                #if DEBUG
                print("📄 TextUploadVM: Processing file: \(url.lastPathComponent)")
                #endif
                
                // Read file content
                textContent = try await readFileContent(from: url)
                
                // Process with AI if content is not empty
                if !textContent.isEmpty {
                    processingStatus = "Analyzing content with AI..."
                    aiGeneratedContent = try await processWithAI(text: textContent)
                }
                
                // Calculate stats
                stats = TextStats(text: textContent, fileSize: Int64(fileSize))
                
                isLoading = false
                processingStatus = ""
            } catch {
                isLoading = false
                processingStatus = ""
                throw error
            }
        } catch {
            isLoading = false
            processingStatus = ""
            throw error
        }
    }
    
    // MARK: - File Reading
    private func extractTextFromPDF(_ pdfDoc: PDFDocument) async throws -> String {
        var extractedText = ""
        let pageCount = pdfDoc.pageCount
        
        #if DEBUG
        print("📄 TextUploadVM: PDF has \(pageCount) pages")
        #endif
        
        for pageIndex in 0..<pageCount {
            guard let page = pdfDoc.page(at: pageIndex) else { continue }
            
            // Try PDFKit text extraction first
            if let pageText = page.string {
                #if DEBUG
                print("📄 TextUploadVM: Successfully extracted text from page \(pageIndex + 1)")
                #endif
                extractedText += pageText + "\n"
                continue
            }
            
            // If PDFKit fails, try OCR
            let pageBounds = page.bounds(for: .mediaBox)
            let pageImage = page.thumbnail(of: pageBounds.size, for: .mediaBox)
            
            // Convert CGImage to UIImage for Vision framework
            if let cgImage = pageImage.cgImage {
                let uiImage = UIImage(cgImage: cgImage)
                let text = try await performOCR(on: uiImage)
                extractedText += text + "\n"
                #if DEBUG
                print("📄 TextUploadVM: Successfully extracted text using OCR from page \(pageIndex + 1)")
                #endif
            } else {
                #if DEBUG
                print("📄 TextUploadVM: Failed to convert page \(pageIndex + 1) to image for OCR")
                #endif
            }
            
            if (pageIndex + 1) % 5 == 0 {
                #if DEBUG
                print("📄 TextUploadVM: Processed \(pageIndex + 1) of \(pageCount) pages")
                #endif
            }
        }
        
        return extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func performOCR(on image: UIImage) async throws -> String {
        let requestHandler = VNImageRequestHandler(cgImage: image.cgImage!, options: [:])
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["en-US"]
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        
        try requestHandler.perform([request])
        
        guard let observations = request.results else {
            throw TextUploadError.readError(NSError(domain: "OCRError",
                                                  code: -1,
                                                  userInfo: [NSLocalizedDescriptionKey: "Failed to perform OCR"]))
        }
        
        return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    private func readFileContent(from url: URL) async throws -> String {
        // Get content type
        guard let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            throw TextUploadError.invalidFile
        }
        
        #if DEBUG
        print("📄 TextUploadVM: Processing file with type: \(contentType.description)")
        #endif
        
        if contentType.conforms(to: .pdf) {
            #if DEBUG
            print("📄 TextUploadVM: Processing PDF file: \(url.lastPathComponent)")
            #endif
            
            guard let pdfDocument = PDFDocument(url: url) else {
                throw TextUploadError.readError(NSError(domain: "PDFError",
                                                      code: -1,
                                                      userInfo: [NSLocalizedDescriptionKey: "Unable to open PDF"]))
            }
            
            return try await extractTextFromPDF(pdfDocument)
        } else if contentType.conforms(to: .text) {
            return try String(contentsOf: url, encoding: .utf8)
        } else if contentType.conforms(to: .rtf) {
            // Handle RTF files
            let options = [NSAttributedString.DocumentReadingOptionKey.documentType: NSAttributedString.DocumentType.rtf]
            let data = try Data(contentsOf: url)
            if let attributedString = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
                return attributedString.string
            }
            throw TextUploadError.readError(NSError(domain: "RTFError",
                                                  code: -1,
                                                  userInfo: [NSLocalizedDescriptionKey: "Unable to read RTF content"]))
        } else if contentType.conforms(to: UTType("com.microsoft.word.doc")!) || 
                  contentType.conforms(to: UTType("org.openxmlformats.wordprocessingml.document")!) {
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
        } else {
            throw TextUploadError.unsupportedFileType(url.pathExtension)
        }
    }
    
    private func processWithAI(text: String) async throws -> Data {
        let prompt = """
        Please analyze this transcript and create a well-structured detailed note using proper markdown formatting:
        
        Add 1-2 table into different section of the note if anything can be represented better in table. Notes are always between summary and conclusion sections.
        No need another header before summary. If you have to use ##
        
        Only use the detected language even for the base headers and subheaders. 

        ## Summary (with custom header)
        Create a detailed summary with a couple of paragraphs.

        ## Key Points (with custom header)
        - Use bullet points for key points. 

        ## Important Details (with custom header)
        as many topic as you need with the topic format below
        
        ### Topic (with custom header)
        Content for topic

        ## Notable Quotes (only impactful and important ones, with custom header)
        > Include quotes if any

        ## Conclusion (with custom header)
        Detailed conclusion based on the whole content with a couple of paragraph.

        Use proper markdown formatting:
        1. Use ## for main headers
        2. Use ### for subheaders
        3. Use proper table formatting with | and -
        4. Use > for quotes
        5. Use - for bullet points
        6. Use ` for code or technical terms
        7. Use ** for emphasis

        \(text)
        """
        
        let aiResponse = try await aiService.generateCompletion(prompt: prompt)
        return aiResponse.data(using: .utf8) ?? Data()
    }
    
    // MARK: - Save Note
    func saveNote(title: String) async throws {
        guard !textContent.isEmpty else {
            throw TextUploadError.emptyContent
        }
        
        try await viewContext.perform { [weak self] in
            guard let self = self else { return }
            
            let note = NSEntityDescription.insertNewObject(forEntityName: "Note", into: self.viewContext)
            note.setValue(UUID(), forKey: "id")
            note.setValue(title, forKey: "title")
            note.setValue(Date(), forKey: "timestamp")
            note.setValue(Date(), forKey: "lastModified")
            note.setValue("text", forKey: "sourceType")
            note.setValue("completed", forKey: "processingStatus")
            note.setValue(textContent.data(using: .utf8), forKey: "originalContent") // Store as Binary
            
            // Save AI-generated content if available
            if let aiContent = aiGeneratedContent {
                note.setValue(aiContent, forKey: "aiGeneratedContent")
            }
            
            // Create a preview from the first few lines
            let preview = String(textContent.prefix(500))
            note.setValue(preview, forKey: "transcript") // Using transcript for preview
            
            if self.saveLocally, let originalURL = self.originalFileURL {
                // Save copy to app documents
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let destinationURL = documentsPath.appendingPathComponent(originalURL.lastPathComponent)
                try FileManager.default.copyItem(at: originalURL, to: destinationURL)
                
                // Save file URL
                note.setValue(destinationURL, forKey: "sourceURL")
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
                
                #if DEBUG
                print("📄 TextUploadView: Selected file: \(url.lastPathComponent)")
                if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
                    print("📄 TextUploadView: File content type: \(type.description)")
                }
                #endif
                
                // Process the file first, which now includes proper type checking
                try await viewModel.processSelectedFile(url)
                selectedFile = url
                
                // Calculate document stats based on the processed content
                documentStats = DocumentStats.calculate(from: viewModel.textContent)
            } catch {
                #if DEBUG
                print("📄 TextUploadView: Error handling file: \(error.localizedDescription)")
                #endif
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
