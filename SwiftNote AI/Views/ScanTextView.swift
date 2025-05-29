import SwiftUI
import VisionKit
import Vision
import UniformTypeIdentifiers
import CoreData

// MARK: - Scan Text Error
enum ScanTextError: LocalizedError {
    case scanningNotAvailable
    case scanningFailed(Error)
    case ocrFailed(Error)
    case noTextFound
    case processingFailed(String)

    var errorDescription: String? {
        switch self {
        case .scanningNotAvailable:
            return "Document scanning is not available on this device"
        case .scanningFailed(let error):
            return "Failed to scan document: \(error.localizedDescription)"
        case .ocrFailed(let error):
            return "Failed to recognize text: \(error.localizedDescription)"
        case .noTextFound:
            return "No text was found in the scanned document"
        case .processingFailed(let message):
            return "Failed to process scan: \(message)"
        }
    }
}

// MARK: - Scan Result
struct ScanPage: Identifiable {
    let id = UUID()
    let image: UIImage
    var recognizedText: String
    var isProcessed: Bool
    var isExpanded: Bool = false // For accordion functionality - closed by default
}

// MARK: - Scan Text View Model
@MainActor
final class ScanTextViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published private(set) var scannedPages: [ScanPage] = []
    @Published private(set) var scanningProgress: Double = 0
    @Published private(set) var loadingState: LoadingState = .idle
    @Published var noteTitle: String = ""
    @Published var aiGeneratedContent: String? = nil
    @Published var isProcessingComplete = false
    @Published var selectedLanguage: Language = Language.supportedLanguages[0] // Default to English

    // MARK: - Private Properties
    private let viewContext: NSManagedObjectContext
    private let noteGenerationService = NoteGenerationService()
    private var recognitionTask: Task<Void, Never>?

    // MARK: - Public Properties
    var combinedText: String = ""

    // MARK: - Initialization
    init(context: NSManagedObjectContext) {
        self.viewContext = context

        #if DEBUG
        print("📝 ScanTextVM: Initializing with context")
        #endif
    }

    // MARK: - Scanning Methods
    func isDocumentScanningAvailable() -> Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func addScannedPage(_ image: UIImage) {
        let page = ScanPage(image: image, recognizedText: "", isProcessed: false)
        scannedPages.append(page)
        processPage(page)

        #if DEBUG
        print("📝 ScanTextVM: Added new scanned page - Total pages: \(scannedPages.count)")
        #endif
    }

    private func processPage(_ page: ScanPage) {
        recognitionTask?.cancel()

        recognitionTask = Task {
            do {
                loadingState = .loading(message: "Processing page \(scannedPages.count)")

                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true

                let handler = VNImageRequestHandler(cgImage: page.image.cgImage!,
                                                  options: [:])
                try handler.perform([request])

                guard let observations = request.results else {
                    throw ScanTextError.noTextFound
                }

                let recognizedText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")

                if let index = scannedPages.firstIndex(where: { $0.id == page.id }) {
                    scannedPages[index].recognizedText = recognizedText
                    scannedPages[index].isProcessed = true
                }

                scanningProgress = Double(scannedPages.filter(\.isProcessed).count) / Double(scannedPages.count)

                if scannedPages.allSatisfy(\.isProcessed) {
                    // All pages are processed, update the combined text
                    updateCombinedText()
                    loadingState = .success(message: "Processing complete")
                }

                #if DEBUG
                print("""
                📝 ScanTextVM: Processed page successfully
                - Page ID: \(page.id)
                - Text Length: \(recognizedText.count)
                - Progress: \(scanningProgress)
                """)
                #endif
            } catch {
                #if DEBUG
                print("📝 ScanTextVM: Error processing page - \(error)")
                #endif
                loadingState = .error(message: error.localizedDescription)
            }
        }
    }

    // MARK: - Text Management
    private func updateCombinedText() {
        combinedText = scannedPages.map(\.recognizedText).joined(separator: "\n\n")
    }

    func updatePageText(pageId: UUID, newText: String) {
        if let index = scannedPages.firstIndex(where: { $0.id == pageId }) {
            scannedPages[index].recognizedText = newText
            updateCombinedText()
        }
    }

    func deletePage(at index: Int) {
        guard index >= 0 && index < scannedPages.count else { return }
        scannedPages.remove(at: index)
        updateCombinedText()
    }

    func togglePageExpansion(at index: Int) {
        guard index >= 0 && index < scannedPages.count else { return }
        scannedPages[index].isExpanded.toggle()
    }

    // MARK: - AI Processing (now handled by unified loading system)

    // MARK: - Save Methods
    func saveNote() async throws {
        guard !scannedPages.isEmpty else {
            throw ScanTextError.noTextFound
        }

        guard !noteTitle.isEmpty else {
            throw ScanTextError.processingFailed("Please enter a title for the note")
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
                note.setValue("text", forKey: "sourceType")
                note.setValue("completed", forKey: "processingStatus")
                note.setValue("pending", forKey: "syncStatus") // Mark for sync

                // Save original content
                let originalContent = self.combinedText
                note.setValue(originalContent.data(using: .utf8), forKey: "originalContent")

                // Save AI-generated content if available
                if let aiContent = self.aiGeneratedContent {
                    note.setValue(aiContent.data(using: .utf8), forKey: "aiGeneratedContent")
                }

                // Store language information
                note.setValue(self.selectedLanguage.code, forKey: "transcriptLanguage")

                // Assign to All Notes folder
                if let allNotesFolder = FolderListViewModel.getAllNotesFolder(context: self.viewContext) {
                    note.setValue(allNotesFolder, forKey: "folder")
                    #if DEBUG
                    print("📝 ScanTextVM: Assigned note to All Notes folder")
                    #endif
                }

                try self.viewContext.save()

                #if DEBUG
                print("📝 ScanTextVM: Note saved successfully")
                #endif
            }

            loadingState = .success(message: "Note saved successfully")
        } catch {
            #if DEBUG
            print("📝 ScanTextVM: Error saving note - \(error)")
            #endif
            loadingState = .error(message: error.localizedDescription)
            throw error
        }
    }

    // MARK: - Reset Processing
    func resetProcessing() {
        loadingState = .idle
        isProcessingComplete = false

        #if DEBUG
        print("📝 ScanTextVM: Reset processing state")
        #endif
    }

    // MARK: - Cleanup
    func cleanup() {
        #if DEBUG
        print("📝 ScanTextVM: Starting cleanup")
        #endif

        recognitionTask?.cancel()
        recognitionTask = nil

        Task { @MainActor in
            scannedPages.removeAll()
            scanningProgress = 0
            loadingState = .idle

            #if DEBUG
            print("📝 ScanTextVM: Cleanup completed")
            #endif
        }
    }

    deinit {
        #if DEBUG
        print("📝 ScanTextVM: Starting deinit")
        #endif

        // Create a separate task that won't retain self
        let task = recognitionTask
        Task {
            task?.cancel()
            #if DEBUG
            print("📝 ScanTextVM: Deinit cleanup completed")
            #endif
        }
    }
}

// MARK: - Scan Text View
struct ScanTextView: View {
    @StateObject private var viewModel: ScanTextViewModel
    @StateObject private var loadingCoordinator = NoteGenerationCoordinator()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.toastManager) private var toastManager
    @State private var isShowingScanner = false
    @FocusState private var isTextFieldFocused: Bool
    @State private var showingSaveDialog = false

    init(context: NSManagedObjectContext) {
        self._viewModel = StateObject(wrappedValue: ScanTextViewModel(context: context))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    headerSection

                    if viewModel.scannedPages.isEmpty {
                        emptyStateSection
                    } else {
                        scannedPagesSection
                        languagePickerSection
                        actionButtonsSection
                    }

                    Spacer()
                }
                .padding()
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
            .gesture(
                TapGesture()
                    .onEnded { _ in
                        isTextFieldFocused = false
                    }
            )
            .sheet(isPresented: $isShowingScanner) {
                DocumentScannerView { result in
                    switch result {
                    case .success(let images):
                        images.forEach { viewModel.addScannedPage($0) }
                    case .failure(let error):
                        toastManager.show(error.localizedDescription, type: .error)
                    }
                    isShowingScanner = false
                }
            }
            .overlay(loadingOverlayView)
            .onChange(of: viewModel.loadingState) { state in
                // Only handle OCR errors, not AI processing errors (handled by unified loading system)
                if case .error(let message) = state, !message.contains("AI") {
                    toastManager.show(message, type: .error)
                }
            }
        }
        .noteGenerationLoading(coordinator: loadingCoordinator)
    }

    // MARK: - View Components
    private var headerSection: some View {
        NoteCreationHeader(
            icon: "viewfinder.circle.fill",
            title: "Scan Document",
            subtitle: "Scan physical documents and convert them to digital notes"
        )
    }

    private var emptyStateSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            Button(action: { isShowingScanner = true }) {
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "doc.viewfinder")
                        .font(.system(size: 40))
                    Text("Tap to Scan")
                        .font(Theme.Typography.h3)
                }
                .frame(maxWidth: .infinity)
                .padding(Theme.Spacing.xl)
                .background(Theme.Colors.secondaryBackground)
                .foregroundColor(Theme.Colors.primary)
                .cornerRadius(Theme.Layout.cornerRadius)
            }

            // Language Picker Section
            StandardLanguagePicker(selectedLanguage: $viewModel.selectedLanguage)
        }
    }

    private var scannedPagesSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Section Header
            HStack {
                Text("Scanned Pages (\(viewModel.scannedPages.count))")
                    .font(Theme.Typography.h3)
                    .foregroundColor(Theme.Colors.text)

                Spacer()

                Button(action: { isShowingScanner = true }) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add More")
                    }
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.primary)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)

            // Scanned Pages List
            ForEach(viewModel.scannedPages.indices, id: \.self) { index in
                ScannedPageCardView(
                    page: viewModel.scannedPages[index],
                    index: index,
                    onToggleExpansion: { viewModel.togglePageExpansion(at: index) },
                    onDelete: { viewModel.deletePage(at: index) },
                    onUpdateText: { newText in
                        viewModel.updatePageText(pageId: viewModel.scannedPages[index].id, newText: newText)
                    }
                )
            }
        }
    }

    private var languagePickerSection: some View {
        StandardLanguagePicker(selectedLanguage: $viewModel.selectedLanguage)
    }

    private var actionButtonsSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            PrimaryActionButton(
                title: "Generate Note with AI",
                icon: "wand.and.stars",
                isEnabled: !viewModel.combinedText.isEmpty,
                isLoading: false,
                action: {
                    isTextFieldFocused = false
                    processScanText()
                }
            )
        }
    }

    private var loadingOverlayView: some View {
        Group {
            // OCR processing progress (only for text recognition, not AI processing)
            if case .loading(let message) = viewModel.loadingState, !(message?.contains("Generating") ?? false) {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()

                    VStack(spacing: Theme.Spacing.md) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(Theme.Colors.primary)

                        if let message = message {
                            Text(message)
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.text)
                                .multilineTextAlignment(.center)
                        }

                        if viewModel.scanningProgress > 0 {
                            ProgressView(value: viewModel.scanningProgress)
                                .progressViewStyle(.linear)
                                .tint(Theme.Colors.primary)
                                .frame(width: 200)
                        }
                    }
                    .padding(Theme.Spacing.xl)
                    .background(Theme.Colors.cardBackground)
                    .cornerRadius(Theme.Layout.cornerRadius)
                    .shadow(radius: 10)
                }
            }
        }
    }

    // MARK: - Helper Methods
    private func processScanText() {
        // Start the unified loading experience
        loadingCoordinator.startGeneration(
            type: .textScan,
            onComplete: {
                dismiss()
                toastManager.show("Note created successfully", type: .success)
            },
            onCancel: {
                // Reset any processing state if needed
                viewModel.resetProcessing()
            }
        )

        // Start the actual processing
        Task {
            await processScanTextWithProgress(
                updateProgress: loadingCoordinator.updateProgress,
                onComplete: loadingCoordinator.completeGeneration,
                onError: loadingCoordinator.setError
            )
        }
    }

    private func processScanTextWithProgress(
        updateProgress: @escaping (NoteGenerationProgressModel.GenerationStep, Double) -> Void,
        onComplete: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) async {
        do {
            // Step 1: Processing (text is already extracted from scanned images)
            await MainActor.run { updateProgress(.processing(progress: 1.0), 1.0) }

            // Step 2: Generating note content
            await MainActor.run { updateProgress(.generating(progress: 0.0), 0.0) }

            let noteGenerationService = NoteGenerationService()

            // Generate AI content with progress tracking
            let aiContent = try await noteGenerationService.generateNoteWithProgress(
                from: viewModel.combinedText,
                detectedLanguage: viewModel.selectedLanguage.code
            ) { progress in
                Task { @MainActor in
                    updateProgress(.generating(progress: progress * 0.7), progress * 0.7) // Use 70% for note generation
                }
            }

            // Generate title with progress tracking
            let title = try await noteGenerationService.generateTitleWithProgress(
                from: viewModel.combinedText,
                detectedLanguage: viewModel.selectedLanguage.code
            ) { progress in
                Task { @MainActor in
                    updateProgress(.generating(progress: 0.7 + (progress * 0.3)), 0.7 + (progress * 0.3)) // Use remaining 30% for title
                }
            }

            await MainActor.run {
                viewModel.aiGeneratedContent = aiContent
                viewModel.noteTitle = title
                updateProgress(.generating(progress: 1.0), 1.0)
            }

            // Step 3: Saving
            await MainActor.run { updateProgress(.saving(progress: 0.0), 0.0) }

            try await viewModel.saveNote()

            await MainActor.run { updateProgress(.saving(progress: 1.0), 1.0) }

            await MainActor.run { onComplete() }

        } catch {
            await MainActor.run { onError(error.localizedDescription) }
        }
    }

    // MARK: - Scanned Page Card View
    struct ScannedPageCardView: View {
        let page: ScanPage
        let index: Int
        let onToggleExpansion: () -> Void
        let onDelete: () -> Void
        let onUpdateText: (String) -> Void

        var body: some View {
            VStack(spacing: 0) {
                // Card Header
                HStack {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text("Page \(index + 1)")
                            .font(Theme.Typography.h3)
                            .foregroundColor(Theme.Colors.text)

                        if !page.recognizedText.isEmpty {
                            Text("\(page.recognizedText.count) characters")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.secondaryText)
                        } else {
                            Text("Processing...")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.secondaryText)
                        }
                    }

                    Spacer()

                    // Preview of text content (when collapsed)
                    if !page.isExpanded && !page.recognizedText.isEmpty {
                        Text(page.recognizedText.prefix(40) + (page.recognizedText.count > 40 ? "..." : ""))
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.secondaryText)
                            .lineLimit(2)
                            .frame(maxWidth: 120)
                    }

                    HStack(spacing: Theme.Spacing.sm) {
                        // Expand/collapse button
                        Button(action: onToggleExpansion) {
                            Image(systemName: page.isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(Theme.Colors.primary)
                        }

                        // Delete button
                        Button(action: onDelete) {
                            Image(systemName: "trash.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.red)
                        }
                    }
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.cardBackground)

                // Expanded Content
                if page.isExpanded {
                    VStack(spacing: Theme.Spacing.md) {
                        Divider()
                            .padding(.horizontal, Theme.Spacing.md)

                        VStack(spacing: Theme.Spacing.md) {
                            // Image Preview
                            Image(uiImage: page.image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 200)
                                .cornerRadius(Theme.Layout.cornerRadius)
                                .shadow(radius: 2)

                            // Text Editor
                            if !page.recognizedText.isEmpty {
                                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                    Text("Recognized Text")
                                        .font(Theme.Typography.caption.weight(.medium))
                                        .foregroundColor(Theme.Colors.secondaryText)

                                    TextEditor(text: Binding(
                                        get: { page.recognizedText },
                                        set: onUpdateText
                                    ))
                                    .font(Theme.Typography.body)
                                    .foregroundColor(Theme.Colors.text)
                                    .frame(minHeight: 120)
                                    .padding(Theme.Spacing.sm)
                                    .background(Theme.Colors.secondaryBackground)
                                    .cornerRadius(Theme.Layout.cornerRadius)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius)
                                            .stroke(Theme.Colors.primary.opacity(0.2), lineWidth: 1)
                                    )
                                }
                            }
                        }
                        .padding(Theme.Spacing.md)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }
            }
            .background(Theme.Colors.cardBackground)
            .cornerRadius(Theme.Layout.cornerRadius)
            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
            .animation(.easeInOut(duration: 0.3), value: page.isExpanded)
        }
    }

    // MARK: - Document Scanner View
    struct DocumentScannerView: UIViewControllerRepresentable {
        let completion: (Result<[UIImage], Error>) -> Void

        func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
            let scanner = VNDocumentCameraViewController()
            scanner.delegate = context.coordinator
            // Note: Auto shutter can't be disabled in VNDocumentCameraViewController
            // We'll rely on manual capture by the user
            return scanner
        }

        func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

        func makeCoordinator() -> Coordinator {
            Coordinator(completion: completion)
        }

        class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
            let completion: (Result<[UIImage], Error>) -> Void

            init(completion: @escaping (Result<[UIImage], Error>) -> Void) {
                self.completion = completion
            }

            func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
#if DEBUG
                print("📝 DocumentScanner: Finished scanning \(scan.pageCount) pages")
#endif

                var images: [UIImage] = []
                for pageIndex in 0..<scan.pageCount {
                    let image = scan.imageOfPage(at: pageIndex)
                    images.append(image)
                }

                controller.dismiss(animated: true) {
                    self.completion(.success(images))
                }
            }

            func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
#if DEBUG
                print("📝 DocumentScanner: Failed with error - \(error)")
#endif

                controller.dismiss(animated: true) {
                    self.completion(.failure(error))
                }
            }

            func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
#if DEBUG
                print("📝 DocumentScanner: Scanning cancelled")
#endif

                controller.dismiss(animated: true) {
                    self.completion(.failure(ScanTextError.scanningFailed(NSError(domain: "DocumentScanner", code: -1, userInfo: [NSLocalizedDescriptionKey: "Scanning cancelled"]))))
                }
            }
        }
    }

    // MARK: - Scanned Page View
    struct ScannedPageView: View {
        let page: ScanPage

        var body: some View {
            VStack(spacing: Theme.Spacing.md) {
                Image(uiImage: page.image)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(Theme.Layout.cornerRadius)

                if !page.recognizedText.isEmpty {
                    Text(page.recognizedText)
                        .font(.body)
                        .foregroundColor(Theme.Colors.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Theme.Colors.secondaryBackground)
                        .cornerRadius(Theme.Layout.cornerRadius)
                }
            }
        }
    }
}
