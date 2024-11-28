import AVFoundation
import Combine
import SwiftUI

// MARK: - Audio Player Error
enum AudioPlayerError: LocalizedError {
    case fileNotFound
    case invalidFileFormat
    case playbackFailed(Error)
    case recordingAccessDenied
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound: return "Audio file not found"
        case .invalidFileFormat: return "Invalid audio file format"
        case .playbackFailed(let error): return "Playback failed: \(error.localizedDescription)"
        case .recordingAccessDenied: return "Microphone access denied"
        }
    }
}

// MARK: - Audio Player View Model
@MainActor
final class AudioPlayerViewModel: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var isPlaying = false
    @Published var playbackRate: Float = 1.0 {
        didSet {
            audioPlayer?.rate = playbackRate
            #if DEBUG
            print("🎵 AudioPlayer: Playback rate changed to \(playbackRate)")
            #endif
        }
    }
    @Published private(set) var loadingState: LoadingState = .idle
    
    // MARK: - Private Properties
    private var audioPlayer: AVPlayer?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var timeObserverClosure: ((CMTime) -> Void)?
    
    // MARK: - Initialization
    override init() {
        // Initialize properties before super.init()
        super.init()
        
        // Avoid capturing self in async context during initialization
        Task.detached { [weak self] in
            await self?.setupAudioSession()
        }
        
        #if DEBUG
        print("🎵 AudioPlayer: Initializing audio player")
        #endif
    }
    
    // MARK: - Audio Setup
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            #if DEBUG
            print("🎵 AudioPlayer: Audio session setup successful")
            #endif
        } catch {
            #if DEBUG
            print("🎵 AudioPlayer: Failed to setup audio session - \(error)")
            #endif
        }
    }
    
    // MARK: - Audio Loading
    func loadAudio(from url: URL) async throws {
        #if DEBUG
        print("🎵 AudioPlayer: Loading audio from \(url)")
        #endif
        
        loadingState = .loading(message: "Loading audio...")
        
        do {
            // Verify file exists
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw AudioPlayerError.fileNotFound
            }
            
            // Create asset and validate
            let asset = AVAsset(url: url)
            let isPlayable = try await asset.load(.isPlayable)
            guard isPlayable else {
                throw AudioPlayerError.invalidFileFormat
            }
            
            // Create player item and observe status
            let playerItem = AVPlayerItem(asset: asset)
            
            await MainActor.run {
                audioPlayer = AVPlayer(playerItem: playerItem)
                // Set up time observer
                setupTimeObserver()
            }
            
            // Get duration
            let duration = try await playerItem.asset.load(.duration)
            await MainActor.run {
                self.duration = duration.seconds
                self.loadingState = .idle
            }
                        
            #if DEBUG
            print("🎵 AudioPlayer: Audio loaded successfully - Duration: \(duration.seconds)s")
            #endif
        } catch {
            #if DEBUG
            print("🎵 AudioPlayer: Failed to load audio - \(error)")
            #endif
            loadingState = .error(message: error.localizedDescription)
            throw error
        }
    }
    
    // MARK: - Playback Controls
    func play() {
        #if DEBUG
        print("🎵 AudioPlayer: Play requested")
        #endif
        
        audioPlayer?.play()
        isPlaying = true
    }
    
    func pause() {
        #if DEBUG
        print("🎵 AudioPlayer: Pause requested")
        #endif
        
        audioPlayer?.pause()
        isPlaying = false
    }
    
    func seek(to time: TimeInterval) {
        #if DEBUG
        print("🎵 AudioPlayer: Seeking to \(time)")
        #endif
        
        audioPlayer?.seek(to: CMTime(seconds: time, preferredTimescale: 1000))
    }
    
    // MARK: - Time Observer
    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.1, preferredTimescale: 1000)
        
        weak var weakSelf = self
        
        timeObserver = audioPlayer?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            Task { @MainActor in

                guard let self = weakSelf else { return }
                self.currentTime = time.seconds
            }
        }
        
        #if DEBUG
        print("🎵 AudioPlayer: Time observer setup")
        #endif
    }
    
    deinit {
        // Using weak capture to avoid retain cycle
        let timeObserver = self.timeObserver
        let player = self.audioPlayer
        
        Task.detached { [weak self] in
            await self?.cleanupResources(timeObserver: timeObserver, player: player)
        }
        
        #if DEBUG
        print("🎵 AudioPlayer: Deinit started")
        #endif
    }
    
    // MARK: - Cleanup
    private func cleanupResources(timeObserver: Any?, player: AVPlayer?) async {
        #if DEBUG
        print("🎵 AudioPlayer: Starting cleanup in detached task")
        #endif
        
        await MainActor.run {
            if let timeObserver = timeObserver {
                player?.removeTimeObserver(timeObserver)
            }
            
            #if DEBUG
            print("🎵 AudioPlayer: Cleanup completed")
            #endif
        }
    }
}
