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
                #if DEBUG
                print("🎵 AudioPlayer: File not found at path: \(url.path)")
                #endif

                // Try to find the file by filename in the documents directory
                let filename = url.lastPathComponent
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

                // First try the simple alternative path
                let alternativeURL = documentsPath.appendingPathComponent(filename)

                #if DEBUG
                print("🎵 AudioPlayer: Trying alternative path: \(alternativeURL.path)")
                print("🎵 AudioPlayer: File exists at alternative path: \(FileManager.default.fileExists(atPath: alternativeURL.path))")
                #endif

                if FileManager.default.fileExists(atPath: alternativeURL.path) {
                    // Use the alternative URL instead
                    return try await loadAudio(from: alternativeURL)
                }

                // If that didn't work, try to extract UUID and try different filename formats
                if let uuid = extractUUID(from: filename) {
                    #if DEBUG
                    print("🎵 AudioPlayer: Extracted UUID: \(uuid)")
                    #endif

                    // Try different filename formats
                    let possibleFilenames = getPossibleFilenames(from: uuid, originalFilename: filename)

                    #if DEBUG
                    print("🎵 AudioPlayer: Trying multiple possible filenames: \(possibleFilenames)")
                    #endif

                    // Try each possible filename
                    for possibleFilename in possibleFilenames {
                        let possibleURL = documentsPath.appendingPathComponent(possibleFilename)

                        #if DEBUG
                        print("🎵 AudioPlayer: Trying path: \(possibleURL.path)")
                        print("🎵 AudioPlayer: File exists: \(FileManager.default.fileExists(atPath: possibleURL.path))")
                        #endif

                        if FileManager.default.fileExists(atPath: possibleURL.path) {
                            // Use this URL instead
                            return try await loadAudio(from: possibleURL)
                        }
                    }
                }

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
        #if DEBUG
        print("🎵 AudioPlayer: Deinit started")
        #endif

        // Capture local copies of resources to clean up
        let timeObserver = self.timeObserver
        let player = self.audioPlayer

        // Create a detached task that won't capture self
        Task.detached {
            // Pause playback
            player?.pause()

            // Remove time observer
            if let timeObserver = timeObserver {
                player?.removeTimeObserver(timeObserver)
            }

            #if DEBUG
            print("🎵 AudioPlayer: Deinit cleanup completed")
            #endif
        }
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

    // Public cleanup method that can be called when the view disappears
    func cleanup() {
        #if DEBUG
        print("🎵 AudioPlayer: Manual cleanup requested")
        #endif

        // Pause playback
        pause()

        // Remove time observer
        if let timeObserver = timeObserver {
            audioPlayer?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        // Reset player
        audioPlayer = nil

        #if DEBUG
        print("🎵 AudioPlayer: Manual cleanup completed")
        #endif
    }

    // MARK: - Helper Methods

    // Extract UUID from filename
    private func extractUUID(from filename: String) -> UUID? {
        // Try to find a UUID pattern in the filename
        let pattern = "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}"
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)

        if let match = regex?.firstMatch(in: filename, options: [], range: NSRange(location: 0, length: filename.count)) {
            let matchRange = match.range
            if let range = Range(matchRange, in: filename) {
                let uuidString = String(filename[range])
                return UUID(uuidString: uuidString)
            }
        }
        return nil
    }

    // Get possible filenames for an audio file based on UUID
    private func getPossibleFilenames(from uuid: UUID, originalFilename: String) -> [String] {
        // For recorded files, the format is just the UUID
        let simpleUUIDFilename = "\(uuid.uuidString).m4a"

        // For imported files, the format is UUID-originalFilename
        let importedFileFormat = "\(uuid.uuidString)-\(originalFilename)"

        // Return all possible formats
        return [simpleUUIDFilename, importedFileFormat, originalFilename]
    }
}
