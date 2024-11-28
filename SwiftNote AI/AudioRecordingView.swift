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
        
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        let fileName = "recording_\(Date().timeIntervalSince1970).m4a"
        recordingURL = tempDir.appendingPathComponent(fileName)
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: recordingURL!, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            
            if audioRecorder?.record() == true {
                isRecording = true
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
    
    func stopRecording() {
        #if DEBUG
        print("🎙️ AudioRecordingViewModel: Stopping recording")
        #endif
        
        audioRecorder?.stop()
        isRecording = false
        stopTimers()
        showingSaveDialog = true
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
                    let level = self.audioRecorder?.averagePower(forChannel: 0) ?? -160
                    let normalizedLevel = pow(10, level / 20)
                    self.audioLevel = CGFloat(normalizedLevel)
                }
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
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

// MARK: - Audio Recording View
struct AudioRecordingView: View {
    @StateObject private var viewModel: AudioRecordingViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.toastManager) private var toastManager
    @State private var noteTitle: String = ""
    
    init(context: NSManagedObjectContext) {
        _viewModel = StateObject(wrappedValue: AudioRecordingViewModel(context: context))
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Theme.Colors.background
                    .ignoresSafeArea()
                
                VStack(spacing: Theme.Spacing.xl) {
                    // Waveform Visualization
                    EnhancedWaveformView(
                        audioLevel: viewModel.audioLevel,
                        configuration: WaveformConfiguration(
                            primaryColor: viewModel.isRecording ? Theme.Colors.error : Theme.Colors.primary,
                            secondaryColor: (viewModel.isRecording ? Theme.Colors.error : Theme.Colors.primary).opacity(0.3),
                            backgroundColor: Theme.Colors.background,
                            maxBars: 60,
                            spacing: 2,
                            minBarHeight: 10,
                            maxBarHeight: 100,
                            barWidth: 3,
                            animationDuration: 0.15
                        )
                    )
                        .frame(height: 200)
                        .padding()
                    
                    // Timer Display
                    Text(formatDuration(viewModel.recordingDuration))
                        .font(Theme.Typography.h1)
                        .foregroundColor(viewModel.isRecording ? Theme.Colors.error : Theme.Colors.text)
                    
                    // Recording Controls
                    recordingControls
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Record Audio")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        #if DEBUG
                        print("🎙️ AudioRecordingView: Cancel button tapped")
                        #endif
                        Task {
                            await viewModel.cleanup()
                            dismiss()
                        }
                    }
                }
            }
            .alert("Save Recording", isPresented: $viewModel.showingSaveDialog) {
                TextField("Note Title", text: $noteTitle)
                Button("Cancel", role: .cancel) {
                    Task {
                        await viewModel.cleanup()
                    }
                }
                Button("Save") {
                    saveRecording()
                }
            } message: {
                Text("Enter a title for your recording")
            }
            .overlay {
                if viewModel.isProcessing {
                    LoadingIndicator(message: "Saving recording...")
                }
            }
        }
    }
    
    // MARK: - Recording Controls
    private var recordingControls: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Button(action: {
                #if DEBUG
                print("🎙️ AudioRecordingView: Record button tapped - Current state: \(viewModel.isRecording)")
                #endif
                
                if viewModel.isRecording {
                    viewModel.stopRecording()
                } else {
                    viewModel.startRecording()
                }
            }) {
                Circle()
                    .fill(viewModel.isRecording ? Theme.Colors.error : Theme.Colors.primary)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                    )
                    .shadow(color: (viewModel.isRecording ? Theme.Colors.error : Theme.Colors.primary).opacity(0.3),
                            radius: 8, x: 0, y: 4)
            }
            
            if viewModel.isRecording {
                Text("Tap to stop recording")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
            }
        }
    }
    
    // MARK: - Helper Methods
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    private func saveRecording() {
        guard !noteTitle.isEmpty else {
            toastManager.show("Please enter a title", type: .error)
            return
        }
        
        Task {
            do {
                try await viewModel.saveRecording(title: noteTitle)
                dismiss()
                toastManager.show("Recording saved successfully", type: .success)
            } catch {
                #if DEBUG
                print("🎙️ AudioRecordingView: Failed to save recording - \(error)")
                #endif
                toastManager.show("Failed to save recording: \(error.localizedDescription)", type: .error)
            }
        }
    }
}

// MARK: - Waveform View
struct WaveformView: View {
    let audioLevel: CGFloat
    @State private var waveforms: [CGFloat] = Array(repeating: 0, count: 30)
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<waveforms.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.Colors.primary)
                    .frame(width: 4)
                    .frame(height: 20 + waveforms[index] * 80)
            }
        }
        .onChange(of: audioLevel) { newLevel in
            waveforms.removeFirst()
            waveforms.append(newLevel)
        }
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
