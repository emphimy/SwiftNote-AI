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

// MARK: - Modern Audio Visualizer
struct AudioParticle: Identifiable {
    let id = UUID()
    var position: CGPoint
    var scale: CGFloat
    var opacity: Double
    var angle: Double
}

struct ModernAudioVisualizerView: View {
    let audioLevel: CGFloat
    
    @State private var particles: [AudioParticle] = []
    @State private var phase: Double = 0
    @State private var innerRingScale: CGFloat = 1
    @State private var outerRingScale: CGFloat = 1
    
    private let particleCount = 80
    private let baseRadius: CGFloat = 60
    
    init(audioLevel: CGFloat) {
        self.audioLevel = audioLevel
        _particles = State(initialValue: Self.generateParticles(count: particleCount))
    }
    
    private static func generateParticles(count: Int) -> [AudioParticle] {
        (0..<count).map { i in
            let angle = (2 * .pi * Double(i)) / Double(count)
            return AudioParticle(
                position: .zero,
                scale: CGFloat.random(in: 0.3...1),
                opacity: Double.random(in: 0.3...0.8),
                angle: angle
            )
        }
    }
    
    var body: some View {
        TimelineView(.animation) { timeline in
            ZStack {
                // Background glow
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                Color.blue.opacity(0.3 * (0.5 + audioLevel)),
                                Color.clear
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: 100
                        )
                    )
                    .frame(width: 200, height: 200)
                    .scaleEffect(outerRingScale)
                
                // Particle system
                ForEach(particles) { particle in
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.blue,
                                    Color.purple
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 4, height: 4)
                        .position(particle.position)
                        .scaleEffect(particle.scale)
                        .opacity(particle.opacity)
                }
                
                // Inner ring
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.blue,
                                Color.purple,
                                Color.blue
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 3
                    )
                    .frame(width: baseRadius * 2, height: baseRadius * 2)
                    .scaleEffect(innerRingScale)
                
                // Center dot
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
                    .blur(radius: 2)
                    .opacity(0.5 + audioLevel * 0.5)
            }
            .onChange(of: audioLevel) { _ in
                updateParticles()
                animateRings()
            }
        }
        .frame(width: 200, height: 200)
    }
    
    private func updateParticles() {
        withAnimation(.easeInOut(duration: 0.2)) {
            phase += 0.05
            
            for i in particles.indices {
                let baseAngle = particles[i].angle
                let wobble = sin(phase + baseAngle) * 20 * audioLevel
                let radius = baseRadius + wobble
                
                let x = cos(baseAngle) * radius
                let y = sin(baseAngle) * radius
                
                particles[i].position = CGPoint(x: x + 100, y: y + 100)
                particles[i].opacity = 0.3 + audioLevel * 0.7
                particles[i].scale = 0.3 + audioLevel * 0.7
            }
        }
    }
    
    private func animateRings() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            innerRingScale = 1 + audioLevel * 0.3
            outerRingScale = 1 + audioLevel * 0.2
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
                VStack(spacing: Theme.Spacing.xl) {
                    // Header Section
                    VStack(spacing: Theme.Spacing.md) {
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
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.Colors.text)
                        
                        Text(viewModel.isRecording ? "Recording in progress..." : "Tap the button to start recording")
                            .font(.body)
                            .foregroundColor(Theme.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    // Audio Visualizer
                    ModernAudioVisualizerView(audioLevel: viewModel.audioLevel)
                        .frame(height: 200)
                        .padding()
                    
                    // Recording Controls
                    VStack(spacing: Theme.Spacing.md) {
                        // Timer Display
                        Text(formatDuration(viewModel.recordingDuration))
                            .font(.system(size: 24, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.Colors.text)
                            .padding(.vertical, Theme.Spacing.sm)
                        
                        // Record Button
                        Button(action: {
                            if viewModel.isRecording {
                                viewModel.stopRecording()
                            } else {
                                viewModel.startRecording()
                            }
                        }) {
                            Circle()
                                .fill(viewModel.isRecording ? Theme.Colors.error : Theme.Colors.primary)
                                .frame(width: 72, height: 72)
                                .overlay(
                                    Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                                        .font(.system(size: 30))
                                        .foregroundColor(.white)
                                )
                                .shadow(color: (viewModel.isRecording ? Theme.Colors.error : Theme.Colors.primary).opacity(0.3),
                                       radius: 10, x: 0, y: 5)
                        }
                        .padding(.vertical, Theme.Spacing.md)
                    }
                    .padding()
                    .background(Theme.Colors.secondaryBackground)
                    .cornerRadius(Theme.Layout.cornerRadius)
                    .padding(.horizontal)
                }
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
