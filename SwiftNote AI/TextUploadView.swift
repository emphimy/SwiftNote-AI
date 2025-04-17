import SwiftUI
import UniformTypeIdentifiers
import CoreData
import Combine
import PDFKit
import Vision
import UIKit
import Foundation
import Down

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
    @Published var errorMessage: String?
    @Published var saveLocally = false
    @Published private(set) var loadingState: LoadingState = .idle
    @Published var aiGeneratedContent: Data?
    
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
        loadingState = .loading(message: "Reading file...")
        
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
                    loadingState = .loading(message: "Analyzing content with AI...")
                    aiGeneratedContent = try await processWithAI(text: textContent)
                }
                
                // Calculate stats
                stats = TextStats(text: textContent, fileSize: Int64(fileSize))
                
                loadingState = .success(message: "File processed successfully")
            } catch {
                loadingState = .error(message: error.localizedDescription)
                throw error
            }
        } catch {
            loadingState = .error(message: error.localizedDescription)
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
        Please analyze this text document and create a well-structured educational note using proper markdown formatting.

        # Instructions:
        - Detect and use the primary language of the document for all content
        - Create a comprehensive yet concise educational note
        - Use proper markdown formatting throughout
        - Organize information in a logical, hierarchical structure
        - Include tables where data can be better represented visually
        - Highlight key concepts and important terminology

        # Note Structure:
        
        ## Summary
        Begin with a concise 2-3 paragraph summary that captures the main ideas and purpose of the document.
        
        ## Key Concepts
        - List 5-7 essential concepts from the document
        - Use **bold** for concept names
        - Provide brief, clear explanations for each
        - Include relevant relationships between concepts
        
        ## Main Content
        Organize the main content into logical sections with appropriate headings.
        For each important topic:
        
        ### [Topic Name]
        - Present information clearly with proper context
        - Use **bold** for important terms and definitions
        - Use _italic_ for emphasis and technical terminology
        - Use `code blocks` for formulas, equations, or code snippets
        - Create tables for comparative data or structured information
        - Include bullet points for lists of related items
        - Use numbered lists for sequential steps or processes
        
        ## Examples & Applications
        If applicable, include practical examples, case studies, or applications of the concepts.
        
        ## Conclusion
        Summarize the key takeaways and their significance.
        
        # Formatting Guidelines:
        - Use ## for main sections
        - Use ### for subsections
        - Use **bold** for important terms and definitions
        - Use _italic_ for emphasis
        - Use `code` for technical elements
        - Use > for important quotes or highlights
        - Use proper table formatting with headers
        - Use bullet points (-) for unordered lists
        - Use numbers (1.) for ordered lists
        
        Document to analyze:
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
        
        loadingState = .loading(message: "Saving note...")
        
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
        
        loadingState = .success(message: "Note saved successfully")
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

// MARK: - Markdown Preview
struct MarkdownPreview: View {
    let markdown: String
    let maxHeight: CGFloat?
    
    init(markdown: String, maxHeight: CGFloat? = nil) {
        self.markdown = markdown
        self.maxHeight = maxHeight
    }
    
    var body: some View {
        if let attributedString = try? Down(markdownString: markdown).toAttributedString() {
            ScrollView {
                Text(AttributedString(attributedString))
                    .padding(8)
            }
            .frame(maxHeight: maxHeight)
            .background(Theme.Colors.background)
            .cornerRadius(Theme.Layout.cornerRadius)
        } else {
            Text(markdown)
                .frame(maxHeight: maxHeight)
                .background(Theme.Colors.background)
                .cornerRadius(Theme.Layout.cornerRadius)
        }
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
    @State private var selectedFile: URL?
    @State private var noteTitle = ""
    @State private var documentStats: DocumentStats?
    
    // MARK: - Initialization
    init(context: NSManagedObjectContext) {
        _viewModel = StateObject(wrappedValue: TextUploadViewModel(context: context))
    }
    
    // MARK: - View Components
    private var headerSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "doc.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.Colors.primary, Theme.Colors.primary.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .scaleEffect(1.0)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: UUID())
            
            Text("Import Text Document")
                .font(Theme.Typography.h2)
                .foregroundColor(Theme.Colors.text)
            
            Text("Import text from files like TXT, RTF, DOC or PDF")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.top, Theme.Spacing.xl)
    }
    
    // MARK: - Body
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    headerSection
                    
                    if viewModel.loadingState.isLoading {
                        loadingSection
                    } else if let file = selectedFile {
                        previewSection(for: file)
                    } else {
                        fileSelectionSection
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Import Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(viewModel.loadingState.isLoading)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !viewModel.textContent.isEmpty {
                        Button("Save") {
                            showingSaveDialog = true
                        }
                        .disabled(viewModel.loadingState.isLoading)
                    }
                }
            }
            .sheet(isPresented: $showingFilePicker) {
                DocumentPicker(types: viewModel.supportedTypes, onResult: handleSelectedFile)
            }
            .alert("Save Note", isPresented: $showingSaveDialog) {
                TextField("Note Title", text: $noteTitle)
                Button("Cancel", role: .cancel) { }
                Button("Save") {
                    Task {
                        do {
                            try await viewModel.saveNote(title: noteTitle)
                            toastManager.show("Note saved successfully", type: .success)
                            dismiss()
                        } catch {
                            toastManager.show(error.localizedDescription, type: .error)
                        }
                    }
                }
                .disabled(noteTitle.isEmpty)
            } message: {
                Text("Enter a title for your note")
            }
        }
    }
    
    // MARK: - Loading Section
    private var loadingSection: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ProgressView()
                .scaleEffect(1.5)
                .frame(height: 100)
            
            if case let .loading(message) = viewModel.loadingState {
                HStack(spacing: 12) {
                    Text(message ?? "Processing...")
                        .font(Theme.Typography.body)
                        .fontWeight(.medium)
                        .foregroundColor(Theme.Colors.text)
                        .lineLimit(1)
                }
                .frame(minWidth: 200)
            } else if case let .success(message) = viewModel.loadingState {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(message)
                        .font(Theme.Typography.body)
                        .foregroundColor(.green)
                }
            } else if case let .error(message) = viewModel.loadingState {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(message)
                        .font(Theme.Typography.body)
                        .foregroundColor(.red)
                }
            }
            
            if let file = selectedFile {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Processing File:")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                    
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundStyle(Theme.Colors.primary)
                        Text(file.lastPathComponent)
                            .lineLimit(1)
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.text)
                    }
                }
                .padding()
                .background(Theme.Colors.secondaryBackground)
                .cornerRadius(Theme.Layout.cornerRadius)
                .shadow(radius: 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
    
    // MARK: - File Selection Section
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
            
            supportedFormatsSection
        }
    }
    
    private var supportedFormatsSection: some View {
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
    
    // MARK: - Preview Section
    private func previewSection(for file: URL) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            // File Info Section
            fileInfoSection(for: file)
            
            // Document Stats Section
            documentStatsSection
            
            // Content Preview with Markdown Support
            contentPreviewSection
            
            // Save Options
            localStorageToggle
            
            importButton
        }
    }
    
    private func fileInfoSection(for file: URL) -> some View {
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
    }
    
    private var documentStatsSection: some View {
        HStack(spacing: Theme.Spacing.lg) {
            StatItem(title: "Words", value: "\(documentStats?.wordCount ?? 0)")
            
            Divider()
                .frame(height: 40)
            
            StatItem(title: "Characters", value: "\(documentStats?.characterCount ?? 0)")
            
            Divider()
                .frame(height: 40)
            
            StatItem(title: "Pages", value: String(format: "%.1f", documentStats?.pageCount ?? 0))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius)
                .fill(Theme.Colors.secondaryBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius)
                        .stroke(Theme.Colors.tertiaryBackground, lineWidth: 1)
                )
        )
    }
    
    private var contentPreviewSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Content Preview")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
                .padding(.horizontal)
            
            ScrollView {
                Text(LocalizedStringKey(formatMarkdown(viewModel.textContent.prefix(1000) + (viewModel.textContent.count > 1000 ? "\n\n*... content truncated ...*" : "")))
                )
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
            .background(
                RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius)
                    .fill(Theme.Colors.secondaryBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius)
                            .stroke(Theme.Colors.tertiaryBackground, lineWidth: 1)
                    )
            )
        }
    }
    
    private var localStorageToggle: some View {
        Toggle("Save original file locally", isOn: $viewModel.saveLocally)
            .padding()
            .background(Theme.Colors.secondaryBackground)
            .cornerRadius(Theme.Layout.cornerRadius)
    }
    
    private var importButton: some View {
        Button(action: { showingSaveDialog = true }) {
            if viewModel.loadingState.isLoading {
                HStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.8)
                        .tint(.white)
                    
                    if case let .loading(message) = viewModel.loadingState {
                        Text(message ?? "Processing...")
                            .font(Theme.Typography.body)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                }
                .frame(minWidth: 200)
            } else {
                HStack(spacing: 8) {
                    Text("Import Document")
                        .font(Theme.Typography.body)
                        .fontWeight(.semibold)
                    
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 16))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(viewModel.loadingState.isLoading ? Theme.Colors.primary.opacity(0.5) : Theme.Colors.primary)
        .foregroundColor(.white)
        .cornerRadius(Theme.Layout.cornerRadius)
        .disabled(viewModel.loadingState.isLoading)
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
    
    private func formatMarkdown(_ text: String.SubSequence) -> String {
        // This uses SwiftUI's built-in markdown rendering capability
        // by passing the text to a Text view with LocalizedStringKey
        // which automatically renders basic markdown like ** for bold and * for italic
        return String(text)
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
