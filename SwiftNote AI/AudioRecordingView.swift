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
    @Published var showingSaveDialog = false
    @Published var recordingState: RecordingState = .initial
    
    // MARK: - Recording State Enum
    enum RecordingState {
        case initial
        case recording
        case paused
        case finished
    }
    
    // MARK: - Private Properties
    private var audioRecorder: AVAudioRecorder?
    private var recordingTimer: Task<Void, Never>?
    private var audioLevelTimer: Task<Void, Never>?
    private var recordingURL: URL?
    private let maxDuration: TimeInterval = 7200 // 2 hours
    private let viewContext: NSManagedObjectContext
    private let cleanupManager = AudioCleanupManager.shared
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
        
        // Use a default title based on date and time
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, yyyy h:mm a"
        let defaultTitle = "Recording \(dateFormatter.string(from: Date()))"
        
        Task {
            do {
                try await saveRecording(title: defaultTitle)
            } catch {
                errorMessage = "Failed to generate note: \(error.localizedDescription)"
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
    
    // MARK: - Save Recording
    func saveRecording(title: String) async throws {
        #if DEBUG
        print("🎙️ AudioRecordingViewModel: Saving recording with title: \(title)")
        #endif
        
        guard let sourceURL = recordingURL else {
            throw NSError(domain: "AudioRecording", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "Recording file not found"
            ])
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        // Create a new Note entity
        let note = try await viewContext.perform {
            let newNote = NSEntityDescription.insertNewObject(forEntityName: "Note", into: self.viewContext)
            newNote.setValue(title, forKey: "title")
            newNote.setValue(Date(), forKey: "timestamp")
            newNote.setValue("audio", forKey: "sourceType")
            newNote.setValue(self.recordingDuration, forKey: "duration")
            
            // Save to CoreData
            try self.viewContext.save()
            
            #if DEBUG
            print("🎙️ AudioRecordingViewModel: Note saved to CoreData successfully")
            #endif
            
            return newNote
        }
        
        // Move file to permanent storage
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destinationURL = documentsPath.appendingPathComponent("\(note.objectID.uriRepresentation().lastPathComponent).m4a")
        
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
        
        #if DEBUG
        print("🎙️ AudioRecordingViewModel: Audio file moved to permanent storage")
        #endif
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
    @State private var noteTitle: String = ""
    
    init(context: NSManagedObjectContext) {
        self._viewModel = StateObject(wrappedValue: AudioRecordingViewModel(context: context))
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    // Header Section
                    VStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "mic.circle.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(Theme.Colors.primary)
                            .padding(.top, Theme.Spacing.md)
                        
                        Text("Audio Recording")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.Colors.text)
                        
                        Text(getRecordingStateText())
                            .font(.subheadline)
                            .foregroundColor(Theme.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.bottom, Theme.Spacing.sm)
                    
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
            .alert("Save Recording", isPresented: $viewModel.showingSaveDialog) {
                TextField("Recording Title", text: $noteTitle)
                Button("Cancel", role: .cancel) { }
                Button("Save") { saveRecording() }
            }
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
            
            // Save with Custom Title Button
            Button(action: {
                viewModel.stopRecording()
                viewModel.showingSaveDialog = true
            }) {
                HStack {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 18))
                    Text("Save with Custom Title")
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
            
            // Save with Custom Title Button
            Button(action: {
                viewModel.showingSaveDialog = true
            }) {
                HStack {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 18))
                    Text("Save with Custom Title")
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
    
    private func saveRecording() {
        Task {
            do {
                try await viewModel.saveRecording(title: noteTitle)
                dismiss()
                toastManager.show("Recording saved successfully", type: .success)
            } catch {
                toastManager.show(error.localizedDescription, type: .error)
            }
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
