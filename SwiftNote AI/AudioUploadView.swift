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
    case transcriptionFailed(String)
    case noteGenerationFailed(String)

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
        case .transcriptionFailed(let error):
            return "Failed to transcribe audio: \(error)"
        case .noteGenerationFailed(let error):
            return "Failed to generate note: \(error)"
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
    // Removed saveLocally property
    @Published private(set) var loadingState: LoadingState = .idle
    // Removed recordedFiles and showingRecordedFilesPicker
    @Published var transcript = ""
    @Published var transcriptSegments: [TranscriptSegment] = []

    // MARK: - Private Properties
    private let viewContext: NSManagedObjectContext
    private let maxFileSize: Int64 = 100_000_000 // 100MB
    private let maxDuration: TimeInterval = 7200 // 2 hours
    private var originalFileURL: URL?
    private let transcriptionService = AudioTranscriptionService.shared
    private let noteGenerationService = NoteGenerationService()

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

            // Create a local copy of the file in the app's documents directory
            let localURL = try createLocalCopy(of: url)

            await MainActor.run {
                self.stats = AudioStats(
                    duration: duration,
                    fileSize: Int64(fileSize),
                    format: format,
                    sampleRate: sampleRate
                )
                self.selectedFileName = url.lastPathComponent
                self.originalFileURL = localURL // Use the local URL instead of the original
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

    // MARK: - File Management
    private func createLocalCopy(of url: URL) throws -> URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

        // Create a UUID for this file
        let fileUUID = UUID()

        // Preserve the original file extension instead of forcing .m4a
        let originalExtension = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
        let destinationURL = documentsDirectory.appendingPathComponent("\(fileUUID.uuidString).\(originalExtension)")

        #if DEBUG
        print("🎵 AudioUploadVM: Creating local copy at \(destinationURL.path)")
        print("🎵 AudioUploadVM: Original filename was: \(url.lastPathComponent)")
        print("🎵 AudioUploadVM: Preserving original extension: \(originalExtension)")
        #endif

        try FileManager.default.copyItem(at: url, to: destinationURL)
        return destinationURL
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

    // MARK: - Generate Title
    func generateTitle() async throws -> String {
        guard !transcript.isEmpty else {
            throw AudioUploadError.transcriptionFailed("Empty transcript")
        }

        loadingState = .loading(message: "Generating title...")

        do {
            let title = try await noteGenerationService.generateTitle(from: transcript)

            #if DEBUG
            print("🎵 AudioUploadVM: Generated title: \(title)")
            #endif

            return title
        } catch {
            #if DEBUG
            print("🎵 AudioUploadVM: Failed to generate title - \(error)")
            #endif
            throw error
        }
    }

    // MARK: - Save Note
    func saveNote(title: String? = nil) async throws {
        guard let audioURL = originalFileURL else {
            throw AudioUploadError.invalidFormat
        }

        loadingState = .loading(message: "Processing audio file...")

        // Transcribe the audio file with timestamps
        loadingState = .loading(message: "Transcribing audio...")
        let transcription: String
        do {
            let result = try await transcriptionService.transcribeAudioWithTimestamps(fileURL: audioURL)
            transcription = result.text
            transcriptSegments = result.segments
            transcript = transcription

            #if DEBUG
            print("🎵 AudioUploadVM: Successfully transcribed audio with \(transcription.count) characters and \(transcriptSegments.count) segments")
            #endif
        } catch {
            #if DEBUG
            print("🎵 AudioUploadVM: Transcription failed - \(error)")
            #endif
            loadingState = .error(message: "Transcription failed: \(error.localizedDescription)")
            throw AudioUploadError.transcriptionFailed(error.localizedDescription)
        }

        // Generate a note from the transcription
        loadingState = .loading(message: "Generating note content...")
        let noteContent: String
        do {
            noteContent = try await noteGenerationService.generateNote(from: transcript)

            #if DEBUG
            print("🎵 AudioUploadVM: Successfully generated note content with \(noteContent.count) characters")
            #endif
        } catch {
            #if DEBUG
            print("🎵 AudioUploadVM: Note generation failed - \(error)")
            #endif
            throw AudioUploadError.noteGenerationFailed(error.localizedDescription)
        }

        // Generate title if not provided
        let noteTitle: String
        if let title = title, !title.isEmpty {
            noteTitle = title
        } else {
            noteTitle = try await generateTitle()
        }

        // Save to Core Data
        loadingState = .loading(message: "Saving note...")
        try await viewContext.perform { [weak self] in
            guard let self = self else { return }

            let note = NSEntityDescription.insertNewObject(forEntityName: "Note", into: self.viewContext)

            // Set required attributes
            let noteId = UUID()
            note.setValue(noteId, forKey: "id")
            note.setValue(noteTitle, forKey: "title")
            note.setValue(Date(), forKey: "timestamp")
            note.setValue(Date(), forKey: "lastModified")
            note.setValue("audio", forKey: "sourceType")
            note.setValue("completed", forKey: "processingStatus")

            // Set audio-specific attributes
            if let stats = self.stats {
                note.setValue(stats.duration, forKey: "duration")
            }

            // Store the transcription and generated note content
            note.setValue(transcription, forKey: "transcript")
            note.setValue(noteContent.data(using: .utf8), forKey: "aiGeneratedContent")
            note.setValue(transcription.data(using: .utf8), forKey: "originalContent")

            // Skip storing transcript segments for now to avoid crashes
            // We'll implement this properly after examining the Core Data model
            #if DEBUG
            print("🎵 AudioUploadVM: Skipping transcript segments storage to avoid crashes")
            #endif

            // Save the audio file
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            // Preserve the original file extension
            let originalExtension = audioURL.pathExtension
            let fileName = "\(noteId).\(originalExtension)"
            let destinationURL = documentsPath.appendingPathComponent(fileName)

            #if DEBUG
            print("🎵 AudioUploadVM: Saving final audio file with extension: \(originalExtension)")
            #endif

            do {
                // Check if file already exists at destination and remove it
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }

                try FileManager.default.copyItem(at: audioURL, to: destinationURL)

                // Store the file reference as NSURL
                note.setValue(destinationURL, forKey: "sourceURL")

                #if DEBUG
                print("🎵 AudioUploadVM: Audio file copied to \(destinationURL)")
                #endif
            } catch {
                #if DEBUG
                print("🎵 AudioUploadVM: Failed to copy audio file - \(error)")
                #endif
                // Continue saving even if file copy fails
                note.setValue(nil, forKey: "sourceURL")
            }

            try self.viewContext.save()

            #if DEBUG
            print("🎵 AudioUploadVM: Note saved successfully with ID: \(note.value(forKey: "id") ?? "unknown") and title: \(noteTitle)")
            #endif

            loadingState = .success(message: "Audio processed and note created successfully")
        }
    }

    // MARK: - Type Checking
    func canHandle(_ url: URL) -> Bool {
        #if DEBUG
        print("🎵 AudioUploadVM: Checking if can handle file: \(url.lastPathComponent)")
        #endif

        // First try using UTType
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            #if DEBUG
            print("🎵 AudioUploadVM: File content type: \(type.identifier)")
            #endif

            let canHandle = supportedTypes.contains { type.conforms(to: $0) }

            // If UTType check fails, fall back to extension check for common audio formats
            if !canHandle {
                let ext = url.pathExtension.lowercased()
                if ["mp3", "wav", "m4a"].contains(ext) {
                    #if DEBUG
                    print("🎵 AudioUploadVM: UTType check failed but extension \(ext) is supported")
                    #endif
                    return true
                }
            }

            return canHandle
        } else {
            // If UTType check fails completely, check the extension
            let ext = url.pathExtension.lowercased()
            let isSupported = ["mp3", "wav", "m4a"].contains(ext)

            #if DEBUG
            print("🎵 AudioUploadVM: UTType check failed, falling back to extension check: \(ext) - Supported: \(isSupported)")
            #endif

            return isSupported
        }
    }

    // Removed loadRecordedFiles method

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
                    headerSection

                    if viewModel.selectedFileName == nil {
                        fileSelectionSection
                    } else {
                        audioPreviewSection
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
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: viewModel.supportedTypes,
                allowsMultipleSelection: false
            ) { result in
                handleSelectedFile(result)
            }

        }
    }

    // MARK: - View Components

    private var headerSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue.gradient)
                .scaleEffect(1.0)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: UUID())

            Text("Import Audio")
                .font(Theme.Typography.h2)
                .foregroundColor(Theme.Colors.text)

            Text("Upload your audio files for transcription and note-taking")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.top, Theme.Spacing.xl)
    }

    private var fileSelectionSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            Button(action: { showingFilePicker = true }) {
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue.gradient)

                    Text("Select Audio File")
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
                ForEach(["MP3", "WAV", "M4A"], id: \.self) { format in
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

    private var audioPreviewSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            audioFileInfo

            audioDetails

            importButton
        }
    }

    private var audioFileInfo: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(viewModel.selectedFileName ?? "Untitled")
                        .font(Theme.Typography.h3)
                        .foregroundColor(Theme.Colors.text)

                    if let stats = viewModel.stats {
                        Text("\(stats.formattedDuration) • \(ByteCountFormatter.string(fromByteCount: stats.fileSize, countStyle: .file))")
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

    private var audioDetails: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if let stats = viewModel.stats {
                AudioDetailRow(label: "Format", value: stats.format)
                AudioDetailRow(label: "Sample Rate", value: "\(Int(stats.sampleRate))Hz")
            }
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

    // Removed localStorageToggle

    private var importButton: some View {
        Button(action: { saveAudio() }) {
            if case .loading(let message) = viewModel.loadingState {
                HStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.8)

                    Text(message ?? "Processing...")
                        .font(Theme.Typography.body)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .frame(minWidth: 200)
            } else {
                Text("Import Audio")
                    .font(Theme.Typography.body)
                    .fontWeight(.semibold)
            }
        }
        .buttonStyle(LoadingButtonStyle(isLoading: viewModel.loadingState.isLoading))
        .disabled(viewModel.loadingState.isLoading || viewModel.selectedFileName == nil)
    }

    // Removed recordedFilesPickerView and related methods

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
        Task {
            do {
                try await viewModel.saveNote()
                toastManager.show("Audio imported and transcribed successfully", type: .success)
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

// MARK: - Loading Button Style
struct LoadingButtonStyle: ButtonStyle {
    var isLoading: Bool
    var backgroundColor: Color = Theme.Colors.primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius)
                    .fill(isLoading ? backgroundColor.opacity(0.7) : backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
            .foregroundColor(.white)
            .scaleEffect(configuration.isPressed && !isLoading ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.2), value: isLoading)
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
