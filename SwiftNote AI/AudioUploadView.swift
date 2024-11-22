import SwiftUI
import CoreData
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Audio Upload Error
enum AudioUploadError: LocalizedError {
    case fileTooBig(Int64)
    case invalidFormat
    case readError(Error)
    case unsupportedFileType(String)
    case durationTooLong(TimeInterval)
    
    var errorDescription: String? {
        switch self {
        case .fileTooBig(let size):
            return "File too large (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))"
        case .invalidFormat:
            return "Invalid audio format"
        case .readError(let error):
            return "Failed to read file: \(error.localizedDescription)"
        case .unsupportedFileType(let ext):
            return "Unsupported file type: \(ext)"
        case .durationTooLong(let duration):
            return "Audio duration too long (\(Int(duration))s). Maximum 2 hours allowed."
        }
    }
}

// MARK: - Audio Upload Stats
struct AudioStats {
    let duration: TimeInterval
    let fileSize: Int64
    let format: String
    let sampleRate: Double
    
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Audio Upload ViewModel
@MainActor
final class AudioUploadViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var stats: AudioStats?
    @Published var selectedFileName: String?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var saveLocally = false
    @Published private(set) var loadingState: LoadingState = .idle
    
    // MARK: - Private Properties
    private let viewContext: NSManagedObjectContext
    private let maxFileSize: Int64 = 100_000_000 // 100MB
    private let maxDuration: TimeInterval = 7200 // 2 hours
    private var originalFileURL: URL?
    
    let supportedTypes: [UTType] = {
        var types = [UTType.audio, UTType.mp3, UTType.wav]
        if let m4aType = UTType("public.m4a-audio") {
            types.append(m4aType)
        }
        #if DEBUG
        print("🎵 AudioUploadVM: Initialized supported types: \(types)")
        #endif
        return types
    }()
    
    init(context: NSManagedObjectContext) {
        self.viewContext = context
        
        #if DEBUG
        print("🎵 AudioUploadVM: Initializing")
        #endif
        
        guard context.persistentStoreCoordinator != nil else {
            fatalError("AudioUploadVM: Invalid Core Data context")
        }
    }
    
    // MARK: - File Processing
    func processSelectedFile(_ url: URL) async throws {
        loadingState = .loading(message: "Processing audio file...")
        
        do {
            guard url.startAccessingSecurityScopedResource() else {
                throw AudioUploadError.invalidFormat
            }
            
            defer {
                url.stopAccessingSecurityScopedResource()
            }
            
            let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            
            if fileSize > maxFileSize {
                throw AudioUploadError.fileTooBig(Int64(fileSize))
            }
            
            let asset = AVAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            
            if duration > maxDuration {
                throw AudioUploadError.durationTooLong(duration)
            }
            
            let format = try await getAudioFormat(from: asset)
            let sampleRate = try await getSampleRate(from: asset)
            
            await MainActor.run {
                self.stats = AudioStats(
                    duration: duration,
                    fileSize: Int64(fileSize),
                    format: format,
                    sampleRate: sampleRate
                )
                self.selectedFileName = url.lastPathComponent
                self.originalFileURL = url
                self.loadingState = .success(message: "Audio file processed successfully")
            }
            
            #if DEBUG
            print("""
            🎵 AudioUploadVM: File processed successfully
            - Size: \(fileSize) bytes
            - Duration: \(duration)s
            - Format: \(format)
            - Sample Rate: \(sampleRate)Hz
            """)
            #endif
            
        } catch {
            #if DEBUG
            print("🎵 AudioUploadVM: Error processing file - \(error)")
            #endif
            loadingState = .error(message: error.localizedDescription)
            throw error
        }
    }
    
    // MARK: - Audio Analysis
    private func getAudioFormat(from asset: AVAsset) async throws -> String {
        let tracks = try await asset.load(.tracks)
        guard let audioTrack = tracks.first else {
            throw AudioUploadError.invalidFormat
        }
        
        if let format = try await audioTrack.load(.formatDescriptions).first {
            let formatDescription = CMFormatDescriptionGetMediaSubType(format)
            switch formatDescription {
            case kAudioFormatMPEG4AAC:
                return "AAC"
            case kAudioFormatLinearPCM:
                return "WAV"
            case kAudioFormatMPEGLayer3:
                return "MP3"
            default:
                return "Audio"
            }
        }
        return "Audio"
    }
    
    private func getSampleRate(from asset: AVAsset) async throws -> Double {
        let tracks = try await asset.load(.tracks)
        guard let audioTrack = tracks.first else {
            throw AudioUploadError.invalidFormat
        }
        
        let timeScale = try await audioTrack.load(.naturalTimeScale)
        return Double(timeScale) // Convert Int32 to Double
    }
    
    // MARK: - Save Note
    func saveNote(title: String) async throws {
        guard let audioURL = originalFileURL else {
            throw AudioUploadError.invalidFormat
        }
        
        try await viewContext.perform { [weak self] in
            guard let self = self else { return }
            
            let note = NSEntityDescription.insertNewObject(forEntityName: "Note", into: self.viewContext)
            note.setValue(title, forKey: "title")
            note.setValue(Date(), forKey: "timestamp")
            note.setValue("audio", forKey: "sourceType")
            
            if self.saveLocally {
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let destinationURL = documentsPath.appendingPathComponent("\(UUID().uuidString).m4a")
                try FileManager.default.copyItem(at: audioURL, to: destinationURL)
            }
            
            try self.viewContext.save()
            
            #if DEBUG
            print("🎵 AudioUploadVM: Note saved successfully")
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
    
    // MARK: - Cleanup
    func cleanup() {
        #if DEBUG
        print("🎵 AudioUploadVM: Starting cleanup")
        #endif
        
        if let url = originalFileURL {
            do {
                try FileManager.default.removeItem(at: url)
                #if DEBUG
                print("🎵 AudioUploadVM: Successfully cleaned up temporary file at \(url)")
                #endif
            } catch {
                #if DEBUG
                print("🎵 AudioUploadVM: Failed to cleanup file - \(error)")
                #endif
            }
        }
    }

    deinit {
        #if DEBUG
        print("🎵 AudioUploadVM: Starting deinit")
        #endif
        
        // Create separate task that won't retain self
        let fileURL = originalFileURL
        Task {
            if let url = fileURL {
                do {
                    try FileManager.default.removeItem(at: url)
                    #if DEBUG
                    print("🎵 AudioUploadVM: Cleanup completed in deinit for file: \(url)")
                    #endif
                } catch {
                    #if DEBUG
                    print("🎵 AudioUploadVM: Failed to cleanup in deinit - \(error)")
                    #endif
                }
            }
        }
    }
}

// MARK: - Audio Upload View
struct AudioUploadView: View {
    @StateObject private var viewModel: AudioUploadViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.toastManager) private var toastManager
    @State private var showingFilePicker = false
    @State private var showingSaveDialog = false
    @State private var noteTitle: String = ""
    
    init(context: NSManagedObjectContext) {
        _viewModel = StateObject(wrappedValue: AudioUploadViewModel(context: context))
        
        #if DEBUG
        print("🎵 AudioUploadView: Initializing with context: \(context)")
        #endif
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    // File Selection Button
                    if viewModel.selectedFileName == nil {
                        Button(action: {
                            #if DEBUG
                            print("🎵 AudioUploadView: Showing file picker")
                            #endif
                            showingFilePicker = true
                        }) {
                            VStack(spacing: Theme.Spacing.md) {
                                Image(systemName: "music.note.list")
                                    .font(.system(size: 48))
                                    .foregroundColor(Theme.Colors.primary)
                                
                                Text("Select Audio File")
                                    .font(Theme.Typography.body)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.xl)
                            .background(Theme.Colors.secondaryBackground)
                            .cornerRadius(Theme.Layout.cornerRadius)
                        }
                    }
                    
                    // Audio Preview
                    if !viewModel.isLoading, let stats = viewModel.stats {
                        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                            // File Info Header
                            HStack {
                                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                                    Text(viewModel.selectedFileName ?? "Untitled")
                                        .font(Theme.Typography.h3)
                                    
                                    Text("\(stats.formattedDuration) • \(ByteCountFormatter.string(fromByteCount: stats.fileSize, countStyle: .file))")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.secondaryText)
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    #if DEBUG
                                    print("🎵 AudioUploadView: Showing file picker for new file")
                                    #endif
                                    showingFilePicker = true
                                }) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .foregroundColor(Theme.Colors.primary)
                                }
                            }
                            
                            // Audio Details
                            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                AudioDetailRow(label: "Format", value: stats.format)
                                AudioDetailRow(label: "Sample Rate", value: "\(Int(stats.sampleRate))Hz")
                            }
                            .padding()
                            .background(Theme.Colors.secondaryBackground)
                            .cornerRadius(Theme.Layout.cornerRadius)
                            
                            // Local Storage Toggle
                            Toggle("Save original file locally", isOn: $viewModel.saveLocally)
                                .padding()
                                .background(Theme.Colors.secondaryBackground)
                                .cornerRadius(Theme.Layout.cornerRadius)
                            
                            // Import Button
                            Button("Import Audio") {
                                #if DEBUG
                                print("🎵 AudioUploadView: Showing save dialog")
                                #endif
                                showingSaveDialog = true
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Upload Audio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        #if DEBUG
                        print("🎵 AudioUploadView: Canceling import")
                        #endif
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: viewModel.supportedTypes,
                allowsMultipleSelection: false
            ) { result in
                handleSelectedFile(result)
            }
            .alert("Save Note", isPresented: $showingSaveDialog) {
                TextField("Note Title", text: $noteTitle)
                Button("Cancel", role: .cancel) { }
                Button("Save") { saveAudio() }
            }
            .overlay {
                if viewModel.isLoading {
                    LoadingIndicator(message: "Processing audio...")
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
                    throw AudioUploadError.unsupportedFileType(url.pathExtension)
                }
            } catch {
                toastManager.show(error.localizedDescription, type: .error)
            }
        }
    }
    
    private func saveAudio() {
        guard !noteTitle.isEmpty else {
            toastManager.show("Please enter a title", type: .warning)
            return
        }
        
        Task {
            do {
                try await viewModel.saveNote(title: noteTitle)
                toastManager.show("Audio imported successfully", type: .success)
                dismiss()
            } catch {
                toastManager.show(error.localizedDescription, type: .error)
            }
        }
    }
}

// MARK: - Audio Detail Row
private struct AudioDetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
            
            Spacer()
            
            Text(value)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.text)
        }
    }
}

// MARK: - Preview Provider section
#if DEBUG
struct AudioUploadView_Previews: PreviewProvider {
    static var previewContext: NSManagedObjectContext = {
        let context = PersistenceController.preview.container.viewContext
        #if DEBUG
        print("🎵 AudioUploadView_Previews: Created preview context")
        #endif
        return context
    }()
    
    static var previews: some View {
        NavigationView {
            AudioUploadView(context: previewContext)
                .environmentObject(ThemeManager())
                .modifier(ToastContainer())
        }
        .onAppear {
            #if DEBUG
            print("🎵 AudioUploadView_Previews: Preview appeared")
            #endif
        }
    }
}
#endif
