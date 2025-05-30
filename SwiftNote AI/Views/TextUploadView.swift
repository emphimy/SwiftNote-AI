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
    case downloadFailed
    case invalidUrl

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
        case .downloadFailed:
            return "Failed to download PDF from URL"
        case .invalidUrl:
            return "Invalid URL provided"
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

    static func calculate(from text: String, actualPageCount: Int? = nil) -> DocumentStats {
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let characters = text.filter { !$0.isWhitespace }

        #if DEBUG
        print("📄 DocumentStats: Calculating with actualPageCount: \(String(describing: actualPageCount))")
        #endif

        // Use actual page count if provided, otherwise estimate based on word count
        let pages = actualPageCount ?? max(1, Int(ceil(Double(words.count) / 250.0)))

        #if DEBUG
        print("📄 DocumentStats: Final page count: \(pages)")
        #endif

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
    // Removed saveLocally property
    @Published private(set) var loadingState: LoadingState = .idle
    @Published var aiGeneratedContent: Data?
    @Published private(set) var pdfPageCount: Int?
    @Published var selectedLanguage: Language = Language.supportedLanguages[0] // Default to English
    @Published var processingProgress: Double = 0.0

    // MARK: - Private Properties
    let viewContext: NSManagedObjectContext
    let supportedTypes: [UTType] = [.pdf]
    private(set) var originalFileURL: URL?
    private let aiService = AIProxyService.shared

    init(context: NSManagedObjectContext) {
        self.viewContext = context

        #if DEBUG
        print("📄 TextUploadVM: Initializing")
        #endif
    }

    // MARK: - File Processing
    func processSelectedFile(_ url: URL) async throws {
        processingProgress = 0.0
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
            processingProgress = 0.2

            do {
                #if DEBUG
                print("📄 TextUploadVM: Processing file: \(url.lastPathComponent)")
                #endif

                // Read file content
                loadingState = .loading(message: "Extracting text from PDF...")
                textContent = try await readFileContent(from: url)
                processingProgress = 0.8

                // AI processing will happen in the unified loading screen

                // Calculate stats
                stats = TextStats(text: textContent, fileSize: Int64(fileSize))
                processingProgress = 1.0

                loadingState = .success(message: "File processed successfully")
            } catch {
                processingProgress = 0.0
                loadingState = .error(message: error.localizedDescription)
                throw error
            }
        } catch {
            processingProgress = 0.0
            loadingState = .error(message: error.localizedDescription)
            throw error
        }
    }

    // MARK: - File Reading
    private func extractTextFromPDF(_ pdfDoc: PDFDocument) async throws -> String {
        var extractedText = ""
        let pageCount = pdfDoc.pageCount

        // Store the actual PDF page count
        self.pdfPageCount = pageCount

        #if DEBUG
        print("📄 TextUploadVM: PDF has \(pageCount) pages")
        #endif

        let baseProgress = processingProgress // Current progress before text extraction
        let extractionProgressRange = 0.3 // Text extraction takes 30% of total progress

        for pageIndex in 0..<pageCount {
            guard let page = pdfDoc.page(at: pageIndex) else { continue }

            // Update progress for each page
            let pageProgress = Double(pageIndex + 1) / Double(pageCount)
            processingProgress = baseProgress + (extractionProgressRange * pageProgress)

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
        let startProgress = processingProgress
        let aiProgressRange = 0.25 // AI processing takes 25% of total progress

        // Use NoteGenerationService with real streaming progress
        let noteGenerationService = NoteGenerationService()
        let processedContent = try await noteGenerationService.generateNoteWithProgress(
            from: text,
            detectedLanguage: selectedLanguage.code
        ) { progress in
            Task { @MainActor in
                self.processingProgress = startProgress + (aiProgressRange * progress)
            }
        }

        return processedContent.data(using: .utf8) ?? Data()
    }

    // MARK: - Generate Title
    func generateTitle() async throws -> String {
        guard !textContent.isEmpty else {
            throw TextUploadError.emptyContent
        }

        loadingState = .loading(message: "Generating title...")

        do {
            let noteGenerationService = NoteGenerationService()
            let title = try await noteGenerationService.generateTitle(from: textContent, detectedLanguage: selectedLanguage.code)

            #if DEBUG
            print("📄 TextUploadVM: Generated title: \(title)")
            #endif

            return title
        } catch {
            #if DEBUG
            print("📄 TextUploadVM: Failed to generate title - \(error)")
            #endif
            throw error
        }
    }

    // MARK: - Save Note
    func saveNote(title: String? = nil) async throws {
        guard !textContent.isEmpty else {
            throw TextUploadError.emptyContent
        }

        loadingState = .loading(message: "Saving note...")

        // Generate title if not provided
        let noteTitle: String
        if let title = title, !title.isEmpty {
            noteTitle = title
        } else {
            noteTitle = try await generateTitle()
        }

        try await viewContext.perform { [weak self] in
            guard let self = self else { return }

            let note = NSEntityDescription.insertNewObject(forEntityName: "Note", into: self.viewContext)
            note.setValue(UUID(), forKey: "id")
            note.setValue(noteTitle, forKey: "title")
            note.setValue(Date(), forKey: "timestamp")
            note.setValue(Date(), forKey: "lastModified")
            note.setValue("text", forKey: "sourceType")
            note.setValue("completed", forKey: "processingStatus")
            note.setValue("pending", forKey: "syncStatus") // Mark for sync
            note.setValue(textContent.data(using: .utf8), forKey: "originalContent") // Store as Binary

            // Save AI-generated content if available
            if let aiContent = aiGeneratedContent {
                note.setValue(aiContent, forKey: "aiGeneratedContent")
            }

            // Store language information
            note.setValue(self.selectedLanguage.code, forKey: "transcriptLanguage")

            // Store the full extracted text in the transcript field
            note.setValue(textContent, forKey: "transcript") // Store full content, not just preview

            // We don't save the original file locally anymore

            // Assign to All Notes folder
            if let allNotesFolder = FolderListViewModel.getAllNotesFolder(context: self.viewContext) {
                note.setValue(allNotesFolder, forKey: "folder")
                #if DEBUG
                print("📄 TextUploadVM: Assigned note to All Notes folder")
                #endif
            }

            try self.viewContext.save()

            #if DEBUG
            print("📄 TextUploadVM: Note saved successfully with title: \(noteTitle)")
            #endif
        }

        loadingState = .success(message: "Note saved successfully")
    }

    // MARK: - URL PDF Processing
    func processUrlPdf(_ url: URL) async throws {
        processingProgress = 0.0
        loadingState = .loading(message: "Downloading PDF...")

        do {
            // Download the PDF file
            let (data, response) = try await URLSession.shared.data(from: url)
            processingProgress = 0.3

            // Check if the response is valid
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw TextUploadError.downloadFailed
            }

            // Check if the content type is PDF
            if let mimeType = httpResponse.mimeType, !mimeType.contains("pdf") {
                throw TextUploadError.unsupportedFileType("URL does not point to a PDF file")
            }

            // Create a temporary file
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let fileName = url.lastPathComponent.isEmpty ? "downloaded.pdf" : url.lastPathComponent
            let localURL = documentsDirectory.appendingPathComponent(fileName)

            // Remove any existing file with the same name
            if FileManager.default.fileExists(atPath: localURL.path) {
                try FileManager.default.removeItem(at: localURL)
            }

            // Write the data to the file
            try data.write(to: localURL)
            originalFileURL = localURL
            selectedFileName = fileName
            processingProgress = 0.4

            loadingState = .loading(message: "Extracting text from PDF...")

            // Create PDF document from the downloaded data
            guard let pdfDocument = PDFDocument(data: data) else {
                throw TextUploadError.invalidFile
            }

            #if DEBUG
            print("📄 TextUploadVM: PDF document created with \(pdfDocument.pageCount) pages")
            #endif

            // Extract text from the PDF
            textContent = try await extractTextFromPDF(pdfDocument)
            processingProgress = 0.8

            #if DEBUG
            print("📄 TextUploadVM: After extraction, pdfPageCount = \(String(describing: pdfPageCount))")
            #endif

            if textContent.isEmpty {
                throw TextUploadError.emptyContent
            }

            // AI processing will happen in the unified loading screen

            // Calculate stats
            let fileSize = (try? localURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            stats = TextStats(text: textContent, fileSize: Int64(fileSize))
            processingProgress = 1.0

            loadingState = .success(message: "PDF processed successfully")

            #if DEBUG
            print("📄 TextUploadVM: Successfully processed PDF from URL with \(textContent.count) characters")
            #endif
        } catch {
            processingProgress = 0.0
            loadingState = .error(message: error.localizedDescription)

            #if DEBUG
            print("📄 TextUploadVM: Error processing PDF from URL - \(error)")
            #endif

            throw error
        }
    }

    // MARK: - Reset Processing
    func resetProcessing() {
        processingProgress = 0.0
        loadingState = .idle
        errorMessage = nil

        #if DEBUG
        print("📄 TextUploadVM: Reset processing state")
        #endif
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
    @StateObject private var loadingCoordinator = NoteGenerationCoordinator()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.toastManager) private var toastManager
    @State private var showingFilePicker = false
    @State private var selectedFile: URL?
    @State private var documentStats: DocumentStats?
    @State private var pdfUrl: String = ""
    @State private var isImportingFromUrl: Bool = false
    @FocusState private var isURLFieldFocused: Bool

    // MARK: - Initialization
    init(context: NSManagedObjectContext) {
        _viewModel = StateObject(wrappedValue: TextUploadViewModel(context: context))
    }

    // MARK: - View Components
    private var headerSection: some View {
        NoteCreationHeader(
            icon: "doc.circle.fill",
            title: "Import PDF",
            subtitle: "Import and convert PDF documents to notes"
        )
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
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
            .navigationTitle("Import PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(viewModel.loadingState.isLoading)
                }
            }
            .sheet(isPresented: $showingFilePicker) {
                DocumentPicker(types: viewModel.supportedTypes, onResult: handleSelectedFile)
            }
            .noteGenerationLoading(coordinator: loadingCoordinator)
        }
    }

    // MARK: - Loading Section
    private var loadingSection: some View {
        VStack(spacing: Theme.Spacing.xl) {
            // Simple loading indicator
            VStack(spacing: Theme.Spacing.md) {
                // Document with magnifier icon
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundColor(Theme.Colors.primary)

                // Horizontal progress bar
                ProgressView(value: viewModel.processingProgress, total: 1.0)
                    .progressViewStyle(LinearProgressViewStyle(tint: Theme.Colors.primary))
                    .frame(width: 200)
                    .scaleEffect(y: 2.0) // Make it a bit thicker
                    .animation(.easeInOut(duration: 0.3), value: viewModel.processingProgress)
            }
            .padding(.top, Theme.Spacing.lg)

            // Status content
            VStack(spacing: Theme.Spacing.md) {
                if case let .loading(message) = viewModel.loadingState {
                    VStack(spacing: Theme.Spacing.sm) {
                        Text("Analyzing Content with AI")
                            .font(Theme.Typography.h3)
                            .fontWeight(.semibold)
                            .foregroundColor(Theme.Colors.text)

                        // Only show the message if it's different from the title
                        if let message = message, !message.lowercased().contains("analyzing") {
                            Text(message)
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.secondaryText)
                                .multilineTextAlignment(.center)
                        } else {
                            Text("Processing your document...")
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.secondaryText)
                                .multilineTextAlignment(.center)
                        }
                    }
                } else if case let .success(message) = viewModel.loadingState {
                    VStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.green)

                        Text("Processing Complete")
                            .font(Theme.Typography.h3)
                            .fontWeight(.semibold)
                            .foregroundColor(Theme.Colors.text)

                        Text(message)
                            .font(Theme.Typography.body)
                            .foregroundColor(.green)
                            .multilineTextAlignment(.center)
                    }
                } else if case let .error(message) = viewModel.loadingState {
                    VStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.red)

                        Text("Processing Failed")
                            .font(Theme.Typography.h3)
                            .fontWeight(.semibold)
                            .foregroundColor(Theme.Colors.text)

                        Text(message)
                            .font(Theme.Typography.body)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                }

                // File info card
                if let file = selectedFile {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Theme.Colors.primary)

                        Text(file.lastPathComponent)
                            .font(Theme.Typography.body)
                            .fontWeight(.medium)
                            .foregroundColor(Theme.Colors.text)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                            .fill(Theme.Colors.secondaryBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                                    .stroke(Theme.Colors.primary.opacity(0.2), lineWidth: 1)
                            )
                    )
                }

                // Simple status message
                if case .loading = viewModel.loadingState {
                    Text("This may take a moment...")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                        .padding(.top, Theme.Spacing.sm)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                .fill(Theme.Colors.cardBackground)
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
        )
        .padding(.horizontal)
    }

    // MARK: - File Selection Section
    private var fileSelectionSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Local file selection
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

                    Text("Select PDF from Files")
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

            // URL input section
            VStack(spacing: Theme.Spacing.sm) {
                Text("Or Import from URL")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.secondaryText)
                    .padding(.top, Theme.Spacing.sm)

                // URL Input Field with YouTube-style
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "link")
                        .foregroundColor(isURLFieldFocused ? Theme.Colors.primary : .gray)
                        .animation(.easeInOut, value: isURLFieldFocused)

                    TextField("Enter PDF URL", text: $pdfUrl)
                        .textFieldStyle(PlainTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                        .focused($isURLFieldFocused)

                    if !pdfUrl.isEmpty {
                        Button(action: { pdfUrl = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }

                    Button(action: {
                        if let clipboardString = UIPasteboard.general.string {
                            pdfUrl = clipboardString
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

                // Import Button
                Button(action: { importFromUrl() }) {
                    HStack {
                        if isImportingFromUrl {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .tint(.white)
                                .scaleEffect(0.8)
                            Text("Downloading PDF...")
                        } else {
                            Text("Import PDF")
                            Image(systemName: "arrow.right.circle.fill")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(pdfUrl.isEmpty || isImportingFromUrl ? Theme.Colors.primary.opacity(0.5) : Theme.Colors.primary)
                    .foregroundColor(.white)
                    .cornerRadius(Theme.Layout.cornerRadius)
                }
                .disabled(pdfUrl.isEmpty || isImportingFromUrl)
            }
            .padding()
            .background(Theme.Colors.tertiaryBackground.opacity(0.3))
            .cornerRadius(Theme.Layout.cornerRadius)

            // Language Picker Section
            StandardLanguagePicker(selectedLanguage: $viewModel.selectedLanguage)
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
            // File Info Section (now includes stats)
            fileInfoSection(for: file)

            // Language Picker Section
            StandardLanguagePicker(selectedLanguage: $viewModel.selectedLanguage)

            // Content Preview with Markdown Support
            contentPreviewSection

            importButton
        }
    }

    private func fileInfoSection(for file: URL) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            // File icon
            Image(systemName: "doc.text.fill")
                .font(.system(size: 20))
                .foregroundColor(Theme.Colors.primary)
                .frame(width: 24)

            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(file.lastPathComponent)
                    .font(Theme.Typography.body)
                    .fontWeight(.medium)
                    .foregroundColor(Theme.Colors.text)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: Theme.Spacing.xs) {
                    if let fileSize = viewModel.getFileSize(for: file) {
                        Text(fileSize)
                            .font(Theme.Typography.small)
                            .foregroundColor(Theme.Colors.secondaryText)
                    }

                    if let stats = documentStats {
                        Text("•")
                            .font(Theme.Typography.small)
                            .foregroundColor(Theme.Colors.secondaryText)

                        Text("\(stats.wordCount) words")
                            .font(Theme.Typography.small)
                            .foregroundColor(Theme.Colors.secondaryText)

                        Text("•")
                            .font(Theme.Typography.small)
                            .foregroundColor(Theme.Colors.secondaryText)

                        Text("\(stats.pageCount) pages")
                            .font(Theme.Typography.small)
                            .foregroundColor(Theme.Colors.secondaryText)
                    }
                }
            }

            Spacer()

            // Change file button
            Button(action: { showingFilePicker = true }) {
                Text("Change")
                    .font(Theme.Typography.caption)
                    .fontWeight(.medium)
                    .foregroundColor(Theme.Colors.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Theme.Colors.primary.opacity(0.1))
                    )
            }
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                .fill(Theme.Colors.secondaryBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
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

    // Removed localStorageToggle

    private var importButton: some View {
        PrimaryActionButton(
            title: "Import PDF",
            icon: "doc.circle.fill",
            isEnabled: !viewModel.textContent.isEmpty,
            isLoading: false,
            action: {
                processPDF()
            }
        )
    }

    // MARK: - Helper Methods
    private func processPDF() {
        // Start the unified loading experience
        loadingCoordinator.startGeneration(
            type: .pdfImport,
            onComplete: {
                dismiss()
                toastManager.show("PDF imported successfully", type: .success)
            },
            onCancel: {
                // Reset any processing state if needed
                viewModel.resetProcessing()
            }
        )

        // Start the actual processing
        Task {
            await processPDFWithProgress(
                updateProgress: loadingCoordinator.updateProgress,
                onComplete: loadingCoordinator.completeGeneration,
                onError: loadingCoordinator.setError
            )
        }
    }

    private func processPDFWithProgress(
        updateProgress: @escaping (NoteGenerationProgressModel.GenerationStep, Double) -> Void,
        onComplete: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) async {
        do {
            // Step 1: Processing (text extraction from PDF)
            await MainActor.run { updateProgress(.processing(progress: 0.0), 0.0) }

            // If text content is empty, we need to extract it first
            if viewModel.textContent.isEmpty {
                // This should not happen since file selection should extract text
                await MainActor.run { onError("No text content found in PDF") }
                return
            }

            await MainActor.run { updateProgress(.processing(progress: 1.0), 1.0) }

            // Step 2: Generating note content
            await MainActor.run { updateProgress(.generating(progress: 0.0), 0.0) }

            let noteGenerationService = NoteGenerationService()

            // Generate AI content with progress tracking
            let aiContent = try await noteGenerationService.generateNoteWithProgress(
                from: viewModel.textContent,
                detectedLanguage: viewModel.selectedLanguage.code
            ) { progress in
                Task { @MainActor in
                    updateProgress(.generating(progress: progress * 0.7), progress * 0.7) // Use 70% for note generation
                }
            }

            // Generate title with progress tracking
            let title = try await noteGenerationService.generateTitleWithProgress(
                from: viewModel.textContent,
                detectedLanguage: viewModel.selectedLanguage.code
            ) { progress in
                Task { @MainActor in
                    updateProgress(.generating(progress: 0.7 + (progress * 0.3)), 0.7 + (progress * 0.3)) // Use remaining 30% for title
                }
            }

            await MainActor.run {
                viewModel.aiGeneratedContent = aiContent.data(using: .utf8) ?? Data()
                updateProgress(.generating(progress: 1.0), 1.0)
            }

            // Step 3: Saving
            await MainActor.run { updateProgress(.saving(progress: 0.0), 0.0) }

            try await saveNoteToDatabase(title: title, content: aiContent, originalContent: viewModel.textContent)

            await MainActor.run { updateProgress(.saving(progress: 1.0), 1.0) }

            await MainActor.run { onComplete() }

        } catch {
            await MainActor.run { onError(error.localizedDescription) }
        }
    }

    private func saveNoteToDatabase(title: String, content: String, originalContent: String) async throws {
        try await viewModel.viewContext.perform {
            let note = Note(context: viewModel.viewContext)
            note.id = UUID()
            note.title = title
            note.aiGeneratedContent = content.data(using: .utf8)
            note.originalContent = originalContent.data(using: .utf8)
            note.transcript = originalContent // Store full extracted text in transcript field
            note.timestamp = Date()
            note.lastModified = Date()
            note.transcriptLanguage = viewModel.selectedLanguage.code
            note.sourceType = "pdf"
            note.processingStatus = "completed"
            note.syncStatus = "pending"

            try viewModel.viewContext.save()
        }
    }

    private func saveDocument() {
        Task {
            do {
                try await viewModel.saveNote()
                toastManager.show("Note saved successfully", type: .success)
                dismiss()
            } catch {
                toastManager.show(error.localizedDescription, type: .error)
            }
        }
    }

    private func importFromUrl() {
        guard !pdfUrl.isEmpty else { return }

        // Validate URL
        guard let url = URL(string: pdfUrl), UIApplication.shared.canOpenURL(url) else {
            toastManager.show("Invalid URL", type: .error)
            return
        }

        // Check if URL ends with .pdf
        if !url.absoluteString.lowercased().hasSuffix(".pdf") {
            toastManager.show("URL must point to a PDF file", type: .warning)
            return
        }

        isImportingFromUrl = true

        Task {
            do {
                // Download and process the PDF from URL
                try await viewModel.processUrlPdf(url)

                // Set the selected file to show the preview section
                if let localURL = viewModel.originalFileURL {
                    selectedFile = localURL
                }

                // Calculate document stats with actual PDF page count if available
                #if DEBUG
                print("📄 TextUploadView: PDF page count before stats calculation: \(viewModel.pdfPageCount ?? 0)")
                #endif

                documentStats = DocumentStats.calculate(from: viewModel.textContent, actualPageCount: viewModel.pdfPageCount)

                #if DEBUG
                print("📄 TextUploadView: Document stats page count after calculation: \(documentStats?.pageCount ?? 0)")
                #endif

                // Clear the URL field
                pdfUrl = ""
                isImportingFromUrl = false
            } catch {
                isImportingFromUrl = false
                toastManager.show("Failed to import PDF: \(error.localizedDescription)", type: .error)

                #if DEBUG
                print("📄 TextUploadView: Error importing PDF from URL - \(error)")
                #endif
            }
        }
    }

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

                // Calculate document stats based on the processed content with actual PDF page count if available
                documentStats = DocumentStats.calculate(from: viewModel.textContent, actualPageCount: viewModel.pdfPageCount)
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
