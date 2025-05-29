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
    @Published var scrapedContent: String?
    @Published var aiProcessedContent: String?
    @Published var isProcessingComplete = false
    @Published private(set) var loadingState: LoadingState = .idle
    @Published var selectedLanguage: Language = Language.supportedLanguages[0] // Default to English

    // MARK: - Private Properties
    private let viewContext: NSManagedObjectContext
    private let webLinkService = WebLinkService()
    private let noteGenerationService = NoteGenerationService()
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
            loadingState = .loading(message: "Processing content...")

            // Process content - either download file or scrape web content
            let (fileURL, content) = try await webLinkService.processContent(from: urlInput) { progress in
                Task { @MainActor in
                    self.downloadProgress = progress
                    self.loadingState = .loading(message: "Downloading... \(Int(progress * 100))%")
                }
            }

            // Handle file download case
            if let fileURL = fileURL {
                await MainActor.run {
                    self.downloadedFileURL = fileURL
                    self.cleanupURL = fileURL
                    self.loadingState = .loading(message: "Generating title...")
                }

                #if DEBUG
                print("🌐 WebLinkImportVM: File download completed successfully")
                #endif

                // Generate a title for the file
                let fileName = fileURL.lastPathComponent
                self.noteTitle = fileName

                // Automatically save without user interaction
                try await saveNote()

                await MainActor.run {
                    self.loadingState = .success(message: "File processed successfully")
                }

                // Only mark as complete if everything succeeded
                await MainActor.run {
                    self.isProcessingComplete = true
                }

                return
            }

            // Handle web content scraping case
            if let scrapedContent = content {
                await MainActor.run {
                    self.scrapedContent = scrapedContent
                    self.loadingState = .loading(message: "Generating note with AI...")
                }

                #if DEBUG
                print("🌐 WebLinkImportVM: Web content scraped successfully (\(scrapedContent.count) characters)")
                #endif

                // Process with GPT API
                await processWithAI(content: scrapedContent)
            }
        } catch {
            #if DEBUG
            print("🌐 WebLinkImportVM: Error processing URL - \(error)")
            #endif
            loadingState = .error(message: error.localizedDescription)
        }
    }

    // MARK: - Unified Loading System Integration
    func processURLWithProgress(
        updateProgress: @escaping (NoteGenerationProgressModel.GenerationStep, Double) -> Void,
        onComplete: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) async {
        guard !urlInput.isEmpty else {
            onError("Please enter a URL")
            return
        }

        do {
            // Step 1: Processing (downloading/scraping content)
            await MainActor.run { updateProgress(.processing(progress: 0.0), 0.0) }

            let (fileURL, content) = try await webLinkService.processContent(from: urlInput) { progress in
                Task { @MainActor in
                    self.downloadProgress = progress
                    updateProgress(.processing(progress: progress * 0.5), progress * 0.5) // Use 50% for download
                }
            }

            await MainActor.run { updateProgress(.processing(progress: 0.5), 0.5) }

            // Handle file download case
            if let fileURL = fileURL {
                await MainActor.run {
                    self.downloadedFileURL = fileURL
                    self.cleanupURL = fileURL
                }

                #if DEBUG
                print("🌐 WebLinkImportVM: File download completed successfully")
                #endif

                // Generate a title for the file
                let fileName = fileURL.lastPathComponent
                self.noteTitle = fileName

                await MainActor.run { updateProgress(.processing(progress: 1.0), 1.0) }

                // Step 2: Skip generating for file downloads (no AI processing needed)
                await MainActor.run { updateProgress(.generating(progress: 1.0), 1.0) }

                // Step 3: Saving
                await MainActor.run { updateProgress(.saving(progress: 0.0), 0.0) }

                try await saveNoteToDatabase()

                await MainActor.run { updateProgress(.saving(progress: 1.0), 1.0) }

                #if DEBUG
                print("🌐 WebLinkImportVM: File processing completed successfully")
                #endif

                await MainActor.run { onComplete() }
                return
            }

            // Handle web content scraping case
            if let scrapedContent = content {
                await MainActor.run {
                    self.scrapedContent = scrapedContent
                    updateProgress(.processing(progress: 1.0), 1.0)
                }

                #if DEBUG
                print("🌐 WebLinkImportVM: Web content scraped successfully (\(scrapedContent.count) characters)")
                #endif

                // Step 2: Generating note with AI
                await MainActor.run { updateProgress(.generating(progress: 0.0), 0.0) }

                let processedContent = try await noteGenerationService.generateNote(from: scrapedContent, detectedLanguage: selectedLanguage.code)

                await MainActor.run { updateProgress(.generating(progress: 0.5), 0.5) }

                let generatedTitle = try await noteGenerationService.generateTitle(from: scrapedContent, detectedLanguage: selectedLanguage.code)

                await MainActor.run {
                    self.aiProcessedContent = processedContent
                    self.noteTitle = generatedTitle
                    updateProgress(.generating(progress: 1.0), 1.0)
                }

                // Step 3: Saving
                await MainActor.run { updateProgress(.saving(progress: 0.0), 0.0) }

                try await saveNoteToDatabase()

                await MainActor.run { updateProgress(.saving(progress: 1.0), 1.0) }

                #if DEBUG
                print("🌐 WebLinkImportVM: AI processing completed successfully")
                print("🌐 WebLinkImportVM: Generated title: \(generatedTitle)")
                #endif

                await MainActor.run { onComplete() }
            }
        } catch {
            #if DEBUG
            print("🌐 WebLinkImportVM: Error processing URL - \(error)")
            #endif
            await MainActor.run { onError(error.localizedDescription) }
        }
    }

    private func saveNoteToDatabase() async throws {
        guard !noteTitle.isEmpty else {
            throw WebLinkError.processingFailed("Please enter a title")
        }

        try await viewContext.perform { [weak self] in
            guard let self = self else { return }

            let note = NSEntityDescription.insertNewObject(forEntityName: "Note", into: self.viewContext)
            note.setValue(UUID(), forKey: "id")
            note.setValue(self.noteTitle, forKey: "title")
            note.setValue(Date(), forKey: "timestamp")
            note.setValue(Date(), forKey: "lastModified")
            note.setValue("web", forKey: "sourceType")
            note.setValue("pending", forKey: "syncStatus")
            if let url = URL(string: self.urlInput) {
                note.setValue(url, forKey: "sourceURL")
            }
            note.setValue("completed", forKey: "processingStatus")

            // Save content based on what we have
            if let fileURL = self.downloadedFileURL {
                // File download case
                let content = try Data(contentsOf: fileURL)
                note.setValue(content, forKey: "originalContent")
            } else if let scrapedContent = self.scrapedContent {
                // Web scraping case
                note.setValue(scrapedContent.data(using: .utf8), forKey: "originalContent")

                // If we have AI-processed content, save that too
                if let aiContent = self.aiProcessedContent {
                    note.setValue(aiContent.data(using: .utf8), forKey: "aiGeneratedContent")
                }

                // Store language information
                note.setValue(self.selectedLanguage.code, forKey: "transcriptLanguage")
            } else {
                throw WebLinkError.processingFailed("No content available")
            }

            // Assign to All Notes folder
            if let allNotesFolder = FolderListViewModel.getAllNotesFolder(context: self.viewContext) {
                note.setValue(allNotesFolder, forKey: "folder")
                #if DEBUG
                print("🌐 WebLinkImportVM: Assigned note to All Notes folder")
                #endif
            }

            try self.viewContext.save()

            #if DEBUG
            print("🌐 WebLinkImportVM: Note saved successfully")
            #endif
        }
    }

    // MARK: - AI Processing
    private func processWithAI(content: String) async {
        do {
            // Generate note content
            let processedContent = try await noteGenerationService.generateNote(from: content, detectedLanguage: selectedLanguage.code)

            // Generate title
            let generatedTitle = try await noteGenerationService.generateTitle(from: content, detectedLanguage: selectedLanguage.code)

            await MainActor.run {
                self.aiProcessedContent = processedContent
                self.noteTitle = generatedTitle
                self.loadingState = .success(message: "Content processed successfully")
            }

            // Automatically save the note without user interaction
            try await saveNote()

            // Only mark as complete if everything succeeded
            await MainActor.run {
                self.isProcessingComplete = true
            }

            #if DEBUG
            print("🌐 WebLinkImportVM: AI processing completed successfully")
            print("🌐 WebLinkImportVM: Generated title: \(generatedTitle)")
            #endif
        } catch {
            #if DEBUG
            print("🌐 WebLinkImportVM: Error processing with AI - \(error)")
            #endif
            loadingState = .error(message: "Error processing with AI: \(error.localizedDescription)")
        }
    }

    // MARK: - Save Methods
    func saveNote() async throws {
        guard !noteTitle.isEmpty else {
            throw WebLinkError.processingFailed("Please enter a title")
        }

        loadingState = .loading(message: "Saving note...")

        do {
            try await viewContext.perform { [weak self] in
                guard let self = self else { return }

                let note = NSEntityDescription.insertNewObject(forEntityName: "Note", into: self.viewContext)
                note.setValue(UUID(), forKey: "id")  // Set a UUID for the id property
                note.setValue(self.noteTitle, forKey: "title")
                note.setValue(Date(), forKey: "timestamp")
                note.setValue(Date(), forKey: "lastModified")
                note.setValue("web", forKey: "sourceType")
                note.setValue("pending", forKey: "syncStatus") // Mark for sync
                if let url = URL(string: self.urlInput) {
                    note.setValue(url, forKey: "sourceURL")
                }
                note.setValue("completed", forKey: "processingStatus")

                // Save content based on what we have
                if let fileURL = self.downloadedFileURL {
                    // File download case
                    let content = try Data(contentsOf: fileURL)
                    note.setValue(content, forKey: "originalContent")
                } else if let scrapedContent = self.scrapedContent {
                    // Web scraping case
                    note.setValue(scrapedContent.data(using: .utf8), forKey: "originalContent")

                    // If we have AI-processed content, save that too
                    if let aiContent = self.aiProcessedContent {
                        note.setValue(aiContent.data(using: .utf8), forKey: "aiGeneratedContent")
                    }

                    // Store language information
                    note.setValue(self.selectedLanguage.code, forKey: "transcriptLanguage")
                } else {
                    throw WebLinkError.processingFailed("No content available")
                }

                // Assign to All Notes folder
                if let allNotesFolder = FolderListViewModel.getAllNotesFolder(context: self.viewContext) {
                    note.setValue(allNotesFolder, forKey: "folder")
                    #if DEBUG
                    print("🌐 WebLinkImportVM: Assigned note to All Notes folder")
                    #endif
                }

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
    @StateObject private var loadingCoordinator = NoteGenerationCoordinator()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.toastManager) private var toastManager
    @FocusState private var isURLFieldFocused: Bool
    @State private var showSupportedLinks = false

    init(context: NSManagedObjectContext) {
        self._viewModel = StateObject(wrappedValue: WebLinkImportViewModel(context: context))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    // Header Section
                    NoteCreationHeader(
                        icon: "link.circle.fill",
                        title: "Import Web Content",
                        subtitle: "Paste any URL to import web content or files from supported providers"
                    )

                    // URL Input Section
                    VStack(spacing: Theme.Spacing.md) {
                        // Language Picker Section
                        StandardLanguagePicker(selectedLanguage: $viewModel.selectedLanguage)
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

                        PrimaryActionButton(
                            title: "Import Content",
                            icon: "arrow.right.circle.fill",
                            isEnabled: !viewModel.urlInput.isEmpty,
                            isLoading: false,
                            action: {
                                processWebContent()
                            }
                        )
                    }
                    .padding(.horizontal)
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
            .noteGenerationLoading(coordinator: loadingCoordinator)
        }
    }

    private func processWebContent() {
        // Start the unified loading experience
        loadingCoordinator.startGeneration(
            type: .webLink,
            onComplete: {
                dismiss()
                toastManager.show("Web content imported successfully", type: .success)
            },
            onCancel: {
                // Reset any processing state if needed
                viewModel.cleanup()
            }
        )

        // Start the actual processing
        Task {
            await viewModel.processURLWithProgress(
                updateProgress: loadingCoordinator.updateProgress,
                onComplete: loadingCoordinator.completeGeneration,
                onError: loadingCoordinator.setError
            )
        }
    }
}
