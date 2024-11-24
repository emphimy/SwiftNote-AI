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
}

// MARK: - Scan Text View Model
@MainActor
final class ScanTextViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published private(set) var scannedPages: [ScanPage] = []
    @Published private(set) var scanningProgress: Double = 0
    @Published private(set) var loadingState: LoadingState = .idle
    @Published var noteTitle: String = ""
    
    // MARK: - Private Properties
    private let viewContext: NSManagedObjectContext
    private var recognitionTask: Task<Void, Never>?
    
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
                note.setValue(self.noteTitle, forKey: "title")
                note.setValue(Date(), forKey: "timestamp")
                note.setValue("text", forKey: "sourceType")
                note.setValue(self.scannedPages.map(\.recognizedText).joined(separator: "\n\n"),
                            forKey: "content")
                
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
    @State private var showingSaveDialog = false
    
    init(context: NSManagedObjectContext) {
        self._viewModel = StateObject(wrappedValue: ScanTextViewModel(context: context))
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    if viewModel.scannedPages.isEmpty {
                        scanButton
                    } else {
                        scannedContent
                    }
                }
                .padding()
            }
            .navigationTitle("Scan Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        #if DEBUG
                        print("📝 ScanTextView: Cancel button tapped")
                        #endif
                        
                        // First cleanup
                        viewModel.cleanup()
                        
                        // Then dismiss
                        Task { @MainActor in
                            dismiss()
                            #if DEBUG
                            print("📝 ScanTextView: View dismissed after cleanup")
                            #endif
                        }
                    }
                }
                
                if !viewModel.scannedPages.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") {
                            #if DEBUG
                            print("📝 ScanTextView: Save button tapped")
                            #endif
                            showingSaveDialog = true
                        }
                    }
                }
            }
            .sheet(isPresented: $isShowingScanner) {
                DocumentScannerView { result in
                    switch result {
                    case .success(let images):
                        #if DEBUG
                        print("📝 ScanTextView: Successfully scanned \(images.count) pages")
                        #endif
                        images.forEach { viewModel.addScannedPage($0) }
                    case .failure(let error):
                        #if DEBUG
                        print("📝 ScanTextView: Scanning failed - \(error)")
                        #endif
                        toastManager.show(error.localizedDescription, type: .error)
                    }
                    isShowingScanner = false
                }
            }
            .alert("Save Note", isPresented: $showingSaveDialog) {
                TextField("Note Title", text: $viewModel.noteTitle)
                Button("Cancel", role: .cancel) { }
                Button("Save") { saveNote() }
            }
            .onChange(of: viewModel.loadingState) { state in
                if case .error(let message) = state {
                    toastManager.show(message, type: .error)
                }
            }
        }
    }
    
    // MARK: - View Components
    private var scanButton: some View {
        Button(action: {
            #if DEBUG
            print("📝 ScanTextView: Scan button tapped")
            #endif
            if viewModel.isDocumentScanningAvailable() {
                isShowingScanner = true
            } else {
                toastManager.show("Document scanning is not available on this device", type: .error)
            }
        }) {
            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 48))
                    .foregroundColor(Theme.Colors.primary)
                
                Text("Scan Document")
                    .font(Theme.Typography.body)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.xl)
            .background(Theme.Colors.secondaryBackground)
            .cornerRadius(Theme.Layout.cornerRadius)
        }
    }
    
    private var scannedContent: some View {
        VStack(spacing: Theme.Spacing.lg) {
            // Progress Indicator
            if viewModel.scanningProgress < 1.0 {
                VStack(spacing: Theme.Spacing.sm) {
                    ProgressView(value: viewModel.scanningProgress)
                        .tint(Theme.Colors.primary)
                    
                    Text("Processing \(Int(viewModel.scanningProgress * 100))%")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
            }
            
            // Scanned Pages
            ForEach(viewModel.scannedPages) { page in
                ScannedPageView(page: page)
            }
            
            // Add More Button
            Button(action: {
                #if DEBUG
                print("📝 ScanTextView: Add more pages button tapped")
                #endif
                isShowingScanner = true
            }) {
                Label("Add More Pages", systemImage: "plus.circle.fill")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }
    
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

// MARK: - Document Scanner View
struct DocumentScannerView: UIViewControllerRepresentable {
    let completion: (Result<[UIImage], Error>) -> Void
    
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
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
        VStack(spacing: Theme.Spacing.sm) {
            Image(uiImage: page.image)
                .resizable()
                .scaledToFit()
                .frame(height: 200)
                .cornerRadius(Theme.Layout.cornerRadius)
            
            if !page.recognizedText.isEmpty {
                Text(page.recognizedText)
                    .font(Theme.Typography.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Theme.Colors.secondaryBackground)
                    .cornerRadius(Theme.Layout.cornerRadius)
            }
        }
    }
}
