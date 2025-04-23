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
    private var combinedText: String = ""

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

    // MARK: - AI Processing
    func processWithAI() async {
        guard !combinedText.isEmpty else {
            loadingState = .error(message: "No text was found in the scanned document")
            return
        }
        do {
            loadingState = .loading(message: "Generating note with AI...")

            // Generate note content
            let processedContent = try await noteGenerationService.generateNote(from: combinedText, detectedLanguage: selectedLanguage.code)

            // Generate title
            let generatedTitle = try await noteGenerationService.generateTitle(from: combinedText, detectedLanguage: selectedLanguage.code)

            await MainActor.run {
                self.aiGeneratedContent = processedContent
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
            print("📝 ScanTextVM: AI processing completed successfully")
            print("📝 ScanTextVM: Generated title: \(generatedTitle)")
            #endif
        } catch let error as URLError where error.code == .timedOut {
            #if DEBUG
            print("📝 ScanTextVM: API timeout error - \(error)")
            #endif
            loadingState = .error(message: "The request timed out. Please try again or check your internet connection.")
        } catch let error as NoteGenerationError {
            #if DEBUG
            print("📝 ScanTextVM: Note generation error - \(error)")
            #endif
            loadingState = .error(message: "Error generating note: \(error.localizedDescription)")
        } catch {
            #if DEBUG
            print("📝 ScanTextVM: Error processing with AI - \(error)")
            #endif
            loadingState = .error(message: "Error processing with AI: \(error.localizedDescription)")
        }
    }

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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.toastManager) private var toastManager
    @State private var isShowingScanner = false
    @FocusState private var isTextFieldFocused: Bool
    @State private var showingSaveDialog = false

    init(context: NSManagedObjectContext) {
        self._viewModel = StateObject(wrappedValue: ScanTextViewModel(context: context))
    }

    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                ScrollView {
                    // Add padding at the top to make room for the floating buttons
                    Spacer()
                        .frame(height: viewModel.scannedPages.isEmpty ? 0 : 120)
                    VStack(spacing: Theme.Spacing.xl) {
                        // Header Section
                        VStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "viewfinder.circle.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Theme.Colors.primary, Theme.Colors.primary.opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .padding(.top, Theme.Spacing.xl)

                            Text("Scan Document")
                                .font(Theme.Typography.h2)
                                .foregroundColor(Theme.Colors.text)

                            Text("Scan physical documents and convert them to digital notes")
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        // Content Section
                        VStack(spacing: Theme.Spacing.lg) {
                            if viewModel.scannedPages.isEmpty {
                                Button(action: { isShowingScanner = true }) {
                                    VStack(spacing: Theme.Spacing.md) {
                                        Image(systemName: "doc.viewfinder")
                                            .font(.system(size: 40))
                                        Text("Tap to Scan")
                                            .font(.headline)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(Theme.Spacing.xl)
                                    .background(Theme.Colors.secondaryBackground)
                                    .foregroundColor(Theme.Colors.primary)
                                    .cornerRadius(Theme.Layout.cornerRadius)
                                }
                            } else {
                                // Processing Status
                                if viewModel.isProcessingComplete {
                                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                        Text("Note Title: \(viewModel.noteTitle)")
                                            .font(.headline)
                                            .foregroundColor(Theme.Colors.text)
                                            .padding(.bottom, Theme.Spacing.sm)

                                        Text("Note has been processed and saved automatically.")
                                            .font(.subheadline)
                                            .foregroundColor(Theme.Colors.secondaryText)
                                    }
                                    .padding()
                                    .background(Theme.Colors.secondaryBackground)
                                    .cornerRadius(Theme.Layout.cornerRadius)
                                }

                                // Scanned Pages with Accordion
                                ForEach(viewModel.scannedPages.indices, id: \.self) { index in
                                    let page = viewModel.scannedPages[index]
                                    VStack(spacing: Theme.Spacing.md) {
                                        // Accordion Header
                                        Button(action: {
                                            viewModel.togglePageExpansion(at: index)
                                        }) {
                                            HStack {
                                                Text("Page \(index + 1)")
                                                    .font(.headline)
                                                    .foregroundColor(Theme.Colors.text)

                                                Spacer()

                                                // Preview of text content
                                                if !page.isExpanded && !page.recognizedText.isEmpty {
                                                    Text(page.recognizedText.prefix(30) + (page.recognizedText.count > 30 ? "..." : ""))
                                                        .font(.caption)
                                                        .foregroundColor(Theme.Colors.secondaryText)
                                                        .lineLimit(1)
                                                }

                                                // Expand/collapse icon
                                                Image(systemName: page.isExpanded ? "chevron.up" : "chevron.down")
                                                    .foregroundColor(Theme.Colors.primary)

                                                // Delete button
                                                Button(action: {
                                                    viewModel.deletePage(at: index)
                                                }) {
                                                    Image(systemName: "trash")
                                                        .foregroundColor(.red)
                                                }
                                                .padding(.leading, 8)
                                            }
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .background(Theme.Colors.secondaryBackground.opacity(0.5))
                                        .cornerRadius(Theme.Layout.cornerRadius)

                                        if page.isExpanded {
                                            VStack(spacing: Theme.Spacing.md) {
                                                Image(uiImage: page.image)
                                                    .resizable()
                                                    .scaledToFit()
                                                    .cornerRadius(Theme.Layout.cornerRadius)

                                                if !page.recognizedText.isEmpty {
                                                    TextEditor(text: Binding(
                                                        get: { page.recognizedText },
                                                        set: { viewModel.updatePageText(pageId: page.id, newText: $0) }
                                                    ))
                                                    .focused($isTextFieldFocused)
                                                    .font(.body)
                                                    .foregroundColor(Theme.Colors.text)
                                                    .frame(minHeight: 100)
                                                    .padding()
                                                    .background(Theme.Colors.secondaryBackground)
                                                    .cornerRadius(Theme.Layout.cornerRadius)
                                                }
                                            }
                                            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                                        }
                                    }
                                    .padding(.bottom, page.isExpanded ? 8 : 2)
                                    .animation(.easeInOut(duration: 0.3), value: page.isExpanded)
                                }

                                // Small spacer at the bottom
                                Spacer()
                                    .frame(height: 15)
                            }
                        }
                        .padding()
                    }
                    .padding(.bottom, 80) // Add padding at the bottom for the floating buttons
                    .onTapGesture {
                        // Dismiss keyboard when tapping outside of a text field
                        isTextFieldFocused = false
                    }

                    // Floating Action Buttons - positioned at the top
                    if !viewModel.scannedPages.isEmpty && !viewModel.isProcessingComplete {
                        VStack(spacing: Theme.Spacing.md) {
                            // Language Picker Section
                            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                Text("Language")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.secondaryText)

                                LanguagePicker(selectedLanguage: $viewModel.selectedLanguage)
                                    .padding(.vertical, Theme.Spacing.sm)
                            }
                            .padding(.horizontal)
                            .padding(.bottom, Theme.Spacing.sm)

                            // Generate Note Button
                            Button(action: {
                                isTextFieldFocused = false // Dismiss keyboard
                                Task {
                                    await viewModel.processWithAI()
                                }
                            }) {
                                HStack {
                                    Image(systemName: "wand.and.stars")
                                    Text("Generate Note with AI")
                                }
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    LinearGradient(
                                        colors: [Theme.Colors.primary, Theme.Colors.primary.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(Theme.Layout.cornerRadius)
                            }

                            // Scan More Button
                            Button(action: {
                                isTextFieldFocused = false // Dismiss keyboard
                                isShowingScanner = true
                            }) {
                                HStack {
                                    Image(systemName: "doc.viewfinder")
                                    Text("Scan More")
                                }
                                .font(.headline)
                                .foregroundColor(Theme.Colors.primary)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius)
                                        .stroke(Theme.Colors.primary, lineWidth: 2)
                                )
                                .cornerRadius(Theme.Layout.cornerRadius)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, Theme.Spacing.md)
                        .background(
                            Rectangle()
                                .fill(Color.white.opacity(0.95))
                                .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 3)
                        )
                        .zIndex(100)
                        .ignoresSafeArea(.keyboard)
                    }

                    // Done Button when processing is complete
                    if viewModel.isProcessingComplete {
                        Button(action: { dismiss() }) {
                            Text("Done")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    LinearGradient(
                                        colors: [Theme.Colors.primary, Theme.Colors.primary.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(Theme.Layout.cornerRadius)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, Theme.Spacing.md)
                        .background(
                            Rectangle()
                                .fill(Color.white.opacity(0.95))
                                .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 3)
                        )
                        .zIndex(100)
                        .ignoresSafeArea(.keyboard)
                    }

                    if case .loading(let message) = viewModel.loadingState {
                        VStack(spacing: Theme.Spacing.md) {
                            ProgressView()
                                .scaleEffect(1.2)
                            if let message = message {
                                Text(message)
                                    .font(.subheadline)
                                    .foregroundColor(Theme.Colors.secondaryText)
                            }
                            if message?.contains("Generating") == true {
                                // Show AI processing animation
                                HStack(spacing: 4) {
                                    ForEach(0..<3) { index in
                                        Circle()
                                            .fill(Theme.Colors.primary)
                                            .frame(width: 8, height: 8)
                                            .opacity(0.5)
                                            .animation(
                                                Animation.easeInOut(duration: 0.5)
                                                    .repeatForever()
                                                    .delay(0.2 * Double(index)),
                                                value: UUID() // Force animation to run continuously
                                            )
                                    }
                                }
                            } else if viewModel.scanningProgress > 0 {
                                ProgressView(value: viewModel.scanningProgress)
                                    .progressViewStyle(.linear)
                                    .padding(.horizontal)
                            }
                        }
                        .padding()
                        .background(Theme.Colors.secondaryBackground.opacity(0.9))
                        .cornerRadius(Theme.Layout.cornerRadius)
                        .padding()
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
            .onChange(of: viewModel.loadingState) { state in
                if case .error(let message) = state {
                    toastManager.show(message, type: .error)
                } else if case .success = state, viewModel.isProcessingComplete {
                    toastManager.show("Note created successfully", type: .success)
                }
            }
            .onChange(of: viewModel.isProcessingComplete) { isComplete in
                if isComplete {
                    // Automatically dismiss the view after a delay when processing is complete
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        dismiss()
                    }
                }
            }
        }

        // Note is now saved automatically after AI processing
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
