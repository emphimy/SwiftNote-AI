import SwiftUI
import AVFoundation
import CoreData
import Combine

enum RecordingError: LocalizedError {
    case audioSessionSetupFailed(Error)
    case recordingStartFailed(Error)
    case invalidRecordingState

    var errorDescription: String? {
        switch self {
        case .audioSessionSetupFailed(let error):
            return "Failed to set up audio session: \(error.localizedDescription)"
        case .recordingStartFailed(let error):
            return "Failed to start recording: \(error.localizedDescription)"
        case .invalidRecordingState:
            return "Invalid recording state"
        }
    }
}

private actor AudioRecordingCleanup {
    func cleanup(url: URL?) {
        #if DEBUG
        print("🎙️ AudioRecordingCleanup: Cleaning up temporary files")
        #endif

        if let url = url {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - Audio Recording View Model
@MainActor
final class AudioRecordingViewModel: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioLevel: CGFloat = 0
    @Published var errorMessage: String?
    @Published var isProcessing = false
    @Published var recordingState: RecordingState = .initial
    @Published var loadingState: LoadingState = .idle
    @Published var shouldNavigateToNote = false
    @Published var generatedNote: NoteCardConfiguration?

    // MARK: - Loading State Enum
    enum LoadingState: Equatable {
        case idle
        case loading(message: String)
        case error(message: String)

        var isLoading: Bool {
            if case .loading = self {
                return true
            }
            return false
        }

        var message: String? {
            switch self {
            case .loading(let message):
                return message
            case .error(let message):
                return message
            case .idle:
                return nil
            }
        }
    }

    // MARK: - Recording State Enum
    enum RecordingState {
        case initial
        case recording
        case paused
        case finished
    }

    // MARK: - Properties
    private var audioRecorder: AVAudioRecorder?
    private var recordingTimer: Task<Void, Never>?
    private var audioLevelTimer: Task<Void, Never>?
    private var recordingURL: URL?
    private let maxDuration: TimeInterval = 7200 // 2 hours
    let viewContext: NSManagedObjectContext
    private let cleanupManager = AudioCleanupManager.shared
    private let transcriptionService = AudioTranscriptionService.shared
    private let noteGenerationService = NoteGenerationService()
    private var isCleanedUp = false

    // MARK: - Initialization
    init(context: NSManagedObjectContext) {
        self.viewContext = context
        super.init()

        #if DEBUG
        print("🎙️ AudioRecordingViewModel: Initializing")
        #endif

        setupAudioSession()
    }

    // MARK: - Audio Session Setup
    private func setupAudioSession() {
        #if DEBUG
        print("🎙️ AudioRecordingViewModel: Setting up audio session")
        #endif

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
        } catch {
            #if DEBUG
            print("🎙️ AudioRecordingViewModel: Failed to set up audio session - \(error)")
            #endif
            errorMessage = "Failed to set up audio recording: \(error.localizedDescription)"
        }
    }

    // MARK: - Recording Controls
    func startRecording() {
        #if DEBUG
        print("🎙️ AudioRecordingViewModel: Starting recording")
        #endif

        // If we're resuming a paused recording, just resume
        if recordingState == .paused && audioRecorder != nil {
            #if DEBUG
            print("🎙️ AudioRecordingViewModel: Resuming existing recording")
            #endif

            audioRecorder?.record()
            isRecording = true
            recordingState = .recording
            startTimers()
            return
        }

        // Otherwise, start a new recording
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        let fileName = "recording_\(Date().timeIntervalSince1970).m4a"
        recordingURL = tempDir.appendingPathComponent(fileName)

        do {
            audioRecorder = try AVAudioRecorder(url: recordingURL!, settings: createRecordingSettings())
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true

            if audioRecorder?.record() == true {
                isRecording = true
                recordingState = .recording
                startTimers()

                #if DEBUG
                print("🎙️ AudioRecordingViewModel: Recording started successfully")
                #endif
            }
        } catch {
            #if DEBUG
            print("🎙️ AudioRecordingViewModel: Failed to start recording - \(error)")
            #endif
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    private func createRecordingSettings() -> [String: Any] {
        return [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
    }

    func pauseRecording() {
        #if DEBUG
        print("🎙️ AudioRecordingViewModel: Pausing recording")
        #endif

        audioRecorder?.pause()
        isRecording = false
        recordingState = .paused
        stopTimers()
    }

    func stopRecording() {
        #if DEBUG
        print("🎙️ AudioRecordingViewModel: Stopping recording")
        #endif

        audioRecorder?.stop()
        isRecording = false
        recordingState = .finished
        stopTimers()
    }

    func deleteRecording() {
        #if DEBUG
        print("🎙️ AudioRecordingViewModel: Deleting recording")
        #endif

        Task {
            await performCleanup()
            recordingDuration = 0
            recordingState = .initial
        }
    }

    func generateNote() {
        #if DEBUG
        print("🎙️ AudioRecordingViewModel: Generating note from recording")
        #endif

        guard let recordingURL = recordingURL else {
            errorMessage = "No recording available"
            return
        }

        Task {
            do {
                // Update loading state
                loadingState = .loading(message: "Processing audio file...")

                // Transcribe the audio file
                loadingState = .loading(message: "Transcribing audio...")
                let result = try await transcriptionService.transcribeAudioWithTimestamps(fileURL: recordingURL)
                let transcript = result.text

                #if DEBUG
                print("🎙️ AudioRecordingViewModel: Successfully transcribed audio with \(transcript.count) characters")
                #endif

                // Generate note content from transcript
                loadingState = .loading(message: "Generating note content...")
                let noteContent = try await noteGenerationService.generateNote(from: transcript)

                #if DEBUG
                print("🎙️ AudioRecordingViewModel: Successfully generated note content with \(noteContent.count) characters")
                #endif

                // Generate title from transcript
                loadingState = .loading(message: "Generating title...")
                let title = try await noteGenerationService.generateTitle(from: transcript)

                // Save to Core Data
                loadingState = .loading(message: "Saving note...")
                try await saveNoteToDatabase(title: title, content: noteContent, transcript: transcript)

                // Reset loading state
                loadingState = .idle

                // Cleanup
                await cleanup()

            } catch {
                #if DEBUG
                print("🎙️ AudioRecordingViewModel: Failed to generate note - \(error)")
                #endif

                loadingState = .error(message: error.localizedDescription)
                errorMessage = "Failed to generate note: \(error.localizedDescription)"
            }
        }
    }

    private func saveNoteToDatabase(title: String, content: String, transcript: String) async throws {
        try await viewContext.perform { [weak self] in
            guard let self = self else { return }

            // Create new note
            let note = NSEntityDescription.insertNewObject(forEntityName: "Note", into: self.viewContext)

            // Set required attributes
            let noteId = UUID()
            note.setValue(noteId, forKey: "id")
            note.setValue(title, forKey: "title")
            note.setValue(Date(), forKey: "timestamp")
            note.setValue(Date(), forKey: "lastModified")
            note.setValue("recording", forKey: "sourceType")
            note.setValue("completed", forKey: "processingStatus")

            // Store the transcription and generated note content
            note.setValue(transcript, forKey: "transcript")
            note.setValue(content.data(using: .utf8), forKey: "aiGeneratedContent")
            note.setValue(transcript.data(using: .utf8), forKey: "originalContent")

            // Save audio file to documents directory
            guard let recordingURL = self.recordingURL else {
                throw RecordingError.invalidRecordingState
            }

            let fileManager = FileManager.default
            let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileName = "\(noteId).m4a"
            let destinationURL = documentsPath.appendingPathComponent(fileName)

            do {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.copyItem(at: recordingURL, to: destinationURL)

                // Store the file reference
                note.setValue(destinationURL, forKey: "sourceURL")

                // Add duration if available
                note.setValue(self.recordingDuration, forKey: "duration")

                // Assign to All Notes folder
                if let allNotesFolder = FolderListViewModel.getAllNotesFolder(context: self.viewContext) {
                    note.setValue(allNotesFolder, forKey: "folder")
                    #if DEBUG
                    print("🎤 AudioRecordingViewModel: Assigned note to All Notes folder")
                    #endif
                }

                try self.viewContext.save()

                #if DEBUG
                print("🎙️ AudioRecordingViewModel: Successfully saved note to database")
                #endif

                // Create a NoteCardConfiguration for navigation
                let timestamp = Date()

                // Since we're already on the MainActor, we can directly set these properties
                self.generatedNote = NoteCardConfiguration(
                    id: noteId,
                    title: title,
                    date: timestamp,
                    preview: content,
                    sourceType: .recording,
                    isFavorite: false,
                    tags: [],
                    metadata: [
                        "rawTranscript": transcript,
                        "aiGeneratedContent": content
                    ],
                    sourceURL: destinationURL
                )

                // Set flag to trigger navigation
                self.shouldNavigateToNote = true

                #if DEBUG
                print("🎙️ AudioRecordingViewModel: Set up navigation to generated note")
                #endif
            } catch {
                #if DEBUG
                print("🎙️ AudioRecordingViewModel: Failed to save note - \(error)")
                #endif
                throw error
            }
        }
    }

    // MARK: - Save Recording (Legacy method, kept for compatibility)
    func saveRecording(title: String) async throws {
        #if DEBUG
        print("🎙️ AudioRecordingViewModel: Saving recording with title: \(title)")
        #endif

        guard let recordingURL = recordingURL else {
            throw RecordingError.invalidRecordingState
        }

        // Save to Core Data
        try await viewContext.perform { [weak self] in
            guard let self = self else { return }

            // Create new note
            let note = NSEntityDescription.insertNewObject(forEntityName: "Note", into: self.viewContext)

            // Set required attributes
            let noteId = UUID()
            note.setValue(noteId, forKey: "id")
            note.setValue(title, forKey: "title")
            note.setValue(Date(), forKey: "timestamp")
            note.setValue(Date(), forKey: "lastModified")
            note.setValue("recording", forKey: "sourceType")
            note.setValue("completed", forKey: "processingStatus")

            // Set a simple content for non-transcribed recordings
            let simpleContent = "Audio recording"
            note.setValue(simpleContent.data(using: .utf8), forKey: "originalContent")

            // Save audio file to documents directory
            let fileManager = FileManager.default
            let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileName = "\(noteId).m4a"
            let destinationURL = documentsDirectory.appendingPathComponent(fileName)

            do {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.copyItem(at: recordingURL, to: destinationURL)

                // Store the file reference
                note.setValue(destinationURL, forKey: "sourceURL")

                // Add duration if available
                note.setValue(self.recordingDuration, forKey: "duration")

                // Assign to All Notes folder
                if let allNotesFolder = FolderListViewModel.getAllNotesFolder(context: self.viewContext) {
                    note.setValue(allNotesFolder, forKey: "folder")
                    #if DEBUG
                    print("🎤 AudioRecordingViewModel: Assigned note to All Notes folder")
                    #endif
                }

                try self.viewContext.save()

                #if DEBUG
                print("🎙️ AudioRecordingViewModel: Successfully saved recording to \(destinationURL.path)")
                #endif
            } catch {
                #if DEBUG
                print("🎙️ AudioRecordingViewModel: Failed to save recording - \(error)")
                #endif
                throw error
            }
        }
    }

    // MARK: - Timer Management
    private func startTimers() {
        recordingTimer = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                await MainActor.run {
                    self.recordingDuration = self.audioRecorder?.currentTime ?? 0

                    if self.recordingDuration >= self.maxDuration {
                        self.stopRecording()
                    }
                }
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
        }

        audioLevelTimer = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                await MainActor.run {
                    self.audioRecorder?.updateMeters()
                    // Get average power and convert to a more responsive level
                    let level = self.audioRecorder?.averagePower(forChannel: 0) ?? -160

                    // Apply a more aggressive normalization to make visualization more responsive
                    // Using a different formula that gives better visual response at lower sound levels
                    let normalizedLevel = max(0, min(1, (level + 50) / 50))
                    self.audioLevel = CGFloat(normalizedLevel)
                }
                try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 second - faster updates
            }
        }
    }

    private func stopTimers() {
        recordingTimer?.cancel()
        recordingTimer = nil
        audioLevelTimer?.cancel()
        audioLevelTimer = nil
    }

    private func performCleanup() async {
        guard !isCleanedUp else { return }
        isCleanedUp = true

        #if DEBUG
        print("🎙️ AudioRecordingViewModel: Initiating safe cleanup")
        #endif

        // Cancel timers on main actor
        recordingTimer?.cancel()
        recordingTimer = nil
        audioLevelTimer?.cancel()
        audioLevelTimer = nil

        // Cleanup recording session
        audioRecorder?.stop()
        audioRecorder = nil

        // Handle file cleanup on background
        if let url = recordingURL {
            await cleanupManager.cleanup(url: url)
        }
    }

    // MARK: - Cleanup
    func cleanup() async {
        await performCleanup()
    }

    deinit {
        #if DEBUG
        print("🎙️ AudioRecordingViewModel: Starting deinit")
        #endif

        // Create a new Task for cleanup that won't retain self
        let urlToCleanup = recordingURL
        Task.detached { [cleanupManager] in
            if let url = urlToCleanup {
                await cleanupManager.cleanup(url: url)
            }

            #if DEBUG
            print("🎙️ AudioRecordingViewModel: Completed deinit cleanup")
            #endif
        }
    }
}

// MARK: - AVAudioRecorderDelegate
extension AudioRecordingViewModel: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            #if DEBUG
            print("🎙️ AudioRecordingViewModel: Recording finished - Success: \(flag)")
            #endif

            if !flag {
                errorMessage = "Recording failed to complete properly"
            }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            #if DEBUG
            print("🎙️ AudioRecordingViewModel: Recording error occurred - \(String(describing: error))")
            #endif

            errorMessage = "Recording error: \(error?.localizedDescription ?? "Unknown error")"
        }
    }
}

// MARK: - Classic Waveform View
struct ClassicWaveformView: View {
    let audioLevel: CGFloat
    @State private var waveformSamples: [CGFloat] = Array(repeating: 0.05, count: 30)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.03))

                // Classic waveform visualization with vertical bars
                HStack(spacing: 4) {
                    ForEach(0..<waveformSamples.count, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: [Theme.Colors.primary.opacity(0.7), Theme.Colors.primary],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(width: 4)
                            .frame(height: max(3, geometry.size.height * waveformSamples[index]))
                            .animation(.easeOut(duration: 0.15), value: waveformSamples[index])
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, 20)
            }
        }
        .onAppear {
            // Start animation
            startWaveformAnimation()
        }
        .onChange(of: audioLevel) { newLevel in
            // Update waveform when audio level changes
            updateWaveform(with: newLevel)
        }
    }

    private func startWaveformAnimation() {
        // Create animation timer
        let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

        Task {
            for await _ in timer.values {
                if audioLevel < 0.1 {
                    // Idle animation when not recording - create a gentle wave pattern
                    for i in 0..<waveformSamples.count {
                        let position = Double(i) / Double(waveformSamples.count)
                        let centerPosition = abs(position - 0.5) * 2.0 // 0 at center, 1 at edges
                        let baseHeight = 0.1 - (centerPosition * 0.05) // Higher in center

                        withAnimation(.easeInOut(duration: 0.2)) {
                            waveformSamples[i] = baseHeight
                        }
                    }
                }
            }
        }
    }

    private func updateWaveform(with level: CGFloat) {
        if level > 0.05 {
            // Update waveform based on audio level
            for i in 0..<waveformSamples.count {
                // Create a varied pattern based on position
                let position = Double(i) / Double(waveformSamples.count)
                let centerFactor = 1.0 - abs(position - 0.5) * 1.5

                // Amplify the level for better visualization
                let amplifiedLevel = min(0.8, level * 3.0)

                // Add some randomness for natural look
                let randomVariation = Double.random(in: 0.7...1.3)

                // Calculate final height
                let height = amplifiedLevel * CGFloat(centerFactor * randomVariation)

                // Update with animation
                withAnimation(.easeOut(duration: 0.1)) {
                    waveformSamples[i] = max(0.05, height)
                }
            }
        }
    }
}

// MARK: - Audio Recording View
struct AudioRecordingView: View {
    @StateObject private var viewModel: AudioRecordingViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.toastManager) private var toastManager

    init(context: NSManagedObjectContext) {
        self._viewModel = StateObject(wrappedValue: AudioRecordingViewModel(context: context))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        // Header Section
                        VStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "mic.circle.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Theme.Colors.primary, Theme.Colors.primary.opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .padding(.top, Theme.Spacing.xl)

                            Text("Audio Recording")
                                .font(Theme.Typography.h2)
                                .foregroundColor(Theme.Colors.text)

                            Text(getRecordingStateText())
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        // Audio Visualizer
                        ClassicWaveformView(audioLevel: viewModel.audioLevel)
                            .frame(height: 180)
                            .padding(.horizontal)

                        // Recording Controls
                        VStack(spacing: Theme.Spacing.md) {
                            // Timer Display
                            HStack(spacing: 4) {
                                Image(systemName: viewModel.isRecording ? "record.circle" : "timer")
                                    .foregroundColor(viewModel.isRecording ? Theme.Colors.error : Theme.Colors.secondaryText)
                                    .font(.system(size: 18))
                                    .opacity(viewModel.isRecording ? 1.0 : 0.7)

                                Text(formatDuration(viewModel.recordingDuration))
                                    .font(.system(size: 24, weight: .medium, design: .monospaced))
                                    .foregroundColor(Theme.Colors.text)
                            }
                            .padding(.vertical, Theme.Spacing.sm)
                            .padding(.horizontal, Theme.Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.black.opacity(0.05))
                            )

                            // Primary Recording Controls
                            if viewModel.recordingState == .initial || viewModel.recordingState == .recording {
                                recordingControlButtons
                            } else if viewModel.recordingState == .paused {
                                pausedRecordingButtons
                            } else if viewModel.recordingState == .finished {
                                finishedRecordingButtons
                            }
                        }
                        .padding()
                        .background(Theme.Colors.secondaryBackground)
                        .cornerRadius(Theme.Layout.cornerRadius)
                        .padding(.horizontal)
                    }
                    .padding(.bottom, Theme.Spacing.xl)
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            Task {
                                await viewModel.cleanup()
                                dismiss()
                            }
                        }
                    }
                }
                .navigationDestination(isPresented: $viewModel.shouldNavigateToNote) {
                    if let note = viewModel.generatedNote {
                        NoteDetailsView(note: note, context: viewModel.viewContext)
                    }
                }

                // Loading Overlay
                if case .loading(let message) = viewModel.loadingState {
                    loadingOverlay(message: message)
                }

                // Error Alert
                if case .error(let message) = viewModel.loadingState {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            // Reset loading state
                            viewModel.loadingState = .idle
                        }

                    VStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(Theme.Colors.error)

                        Text("Error")
                            .font(.headline)
                            .foregroundColor(Theme.Colors.text)

                        Text(message)
                            .font(.body)
                            .foregroundColor(Theme.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button(action: {
                            viewModel.loadingState = .idle
                        }) {
                            Text("Dismiss")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 24)
                                .background(Theme.Colors.primary)
                                .cornerRadius(10)
                        }
                        .padding(.top, Theme.Spacing.sm)
                    }
                    .padding(Theme.Spacing.lg)
                    .background(Theme.Colors.background)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                    .padding(.horizontal, 40)
                }
            }
        }
    }

    @ViewBuilder
    private func loadingOverlay(message: String) -> some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.md) {
                ProgressView()
                    .scaleEffect(1.5)
                    .padding(.bottom, Theme.Spacing.sm)

                Text(message)
                    .font(.headline)
                    .foregroundColor(Theme.Colors.text)
                    .multilineTextAlignment(.center)

                Text("This may take a minute...")
                    .font(.subheadline)
                    .foregroundColor(Theme.Colors.secondaryText)
            }
            .padding(Theme.Spacing.lg)
            .background(Theme.Colors.background)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
            .padding(.horizontal, 40)
        }
    }

    private var recordingControlButtons: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Main Record/Pause Button
            Button(action: {
                if viewModel.isRecording {
                    viewModel.pauseRecording()
                } else {
                    viewModel.startRecording()
                }
            }) {
                ZStack {
                    // Pulsing background for recording state
                    if viewModel.isRecording {
                        Circle()
                            .fill(Theme.Colors.error.opacity(0.3))
                            .frame(width: 88, height: 88)
                            .scaleEffect(viewModel.isRecording ? 1.2 : 1.0)
                            .animation(
                                viewModel.isRecording ?
                                    Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true) :
                                    .default,
                                value: viewModel.isRecording
                            )
                    }

                    Circle()
                        .fill(viewModel.isRecording ? Theme.Colors.error : Theme.Colors.primary)
                        .frame(width: 72, height: 72)
                        .shadow(color: (viewModel.isRecording ? Theme.Colors.error : Theme.Colors.primary).opacity(0.3),
                               radius: 10, x: 0, y: 5)

                    Image(systemName: viewModel.isRecording ? "pause.fill" : "mic.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                }
            }
            .padding(.vertical, Theme.Spacing.md)
        }
    }

    private var pausedRecordingButtons: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Resume Recording Button
            Button(action: {
                viewModel.startRecording()
            }) {
                HStack {
                    Image(systemName: "record.circle")
                        .font(.system(size: 20))
                    Text("Resume Recording")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.vertical, Theme.Spacing.md)
                .padding(.horizontal, Theme.Spacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Theme.Colors.primary)
                        .shadow(color: Theme.Colors.primary.opacity(0.3), radius: 5, x: 0, y: 2)
                )
            }

            // Generate Note Button
            Button(action: {
                viewModel.stopRecording()
                viewModel.generateNote()
            }) {
                HStack {
                    Image(systemName: "note.text.badge.plus")
                        .font(.system(size: 18))
                    Text("Generate Note")
                        .font(.system(size: 16, weight: .medium))
                }
                .foregroundColor(Theme.Colors.primary)
                .padding(.vertical, Theme.Spacing.sm)
                .padding(.horizontal, Theme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.05))
                )
            }

            // Delete Button
            Button(action: {
                viewModel.deleteRecording()
            }) {
                Text("Delete Recording")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Theme.Colors.error)
                    .padding(.vertical, Theme.Spacing.sm)
                    .padding(.horizontal, Theme.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.05))
                    )
            }
        }
    }

    private var finishedRecordingButtons: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Generate Note Button
            Button(action: {
                viewModel.generateNote()
            }) {
                HStack {
                    Image(systemName: "note.text.badge.plus")
                        .font(.system(size: 20))
                    Text("Generate Note")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.vertical, Theme.Spacing.md)
                .padding(.horizontal, Theme.Spacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Theme.Colors.primary)
                        .shadow(color: Theme.Colors.primary.opacity(0.3), radius: 5, x: 0, y: 2)
                )
            }

            // Resume Recording Button
            Button(action: {
                viewModel.startRecording()
            }) {
                HStack {
                    Image(systemName: "record.circle")
                        .font(.system(size: 18))
                    Text("Resume Recording")
                        .font(.system(size: 16, weight: .medium))
                }
                .foregroundColor(Theme.Colors.primary)
                .padding(.vertical, Theme.Spacing.sm)
                .padding(.horizontal, Theme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.05))
                )
            }

            // Delete Recording Button
            Button(action: {
                viewModel.deleteRecording()
            }) {
                Text("Delete Recording")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Theme.Colors.error)
                    .padding(.vertical, Theme.Spacing.sm)
                    .padding(.horizontal, Theme.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.05))
                    )
            }
        }
    }

    private func getRecordingStateText() -> String {
        switch viewModel.recordingState {
        case .initial:
            return "Tap the button to start recording"
        case .recording:
            return "Recording in progress..."
        case .paused:
            return "Recording paused"
        case .finished:
            return "Recording complete"
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

// MARK: - Preview Provider
#if DEBUG
struct AudioRecordingView_Previews: PreviewProvider {
    static var previews: some View {
        AudioRecordingView(context: PersistenceController.preview.container.viewContext)
    }
}
#endif
