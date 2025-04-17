import SwiftUI
import AVFoundation
import Combine

// MARK: - Compact Audio Player View
struct CompactAudioPlayerView: View {
    @StateObject private var viewModel = AudioPlayerViewModel()
    @State private var isExpanded = false
    @Environment(\.dismiss) private var dismiss

    let audioURL: URL

    init(audioURL: URL) {
        self.audioURL = audioURL

        #if DEBUG
        print("🎵 CompactAudioPlayer: Initializing with URL: \(audioURL)")
        #endif
    }

    // Ensure we clean up when this view is removed from the hierarchy
    private func cleanupResources() {
        #if DEBUG
        print("🎵 CompactAudioPlayer: Cleaning up resources")
        #endif

        viewModel.pause()
        viewModel.cleanup()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Player UI
            VStack(spacing: 8) {
                // Progress Bar
                HStack(spacing: 8) {
                    Text(formatTime(viewModel.currentTime))
                        .font(.caption)
                        .foregroundColor(Color(UIColor.label))
                        .monospacedDigit()

                    ZStack(alignment: .leading) {
                        // Background track
                        Rectangle()
                            .fill(Color(UIColor.systemGray5))
                            .frame(height: 4)
                            .cornerRadius(2)

                        // Progress track
                        Rectangle()
                            .fill(Color.blue)
                            .frame(width: progressWidth, height: 4)
                            .cornerRadius(2)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let percentage = min(max(0, value.location.x / UIScreen.main.bounds.width * 1.5), 1)
                                viewModel.seek(to: percentage * viewModel.duration)
                            }
                    )

                    Text(formatTime(viewModel.duration))
                        .font(.caption)
                        .foregroundColor(Color(UIColor.label))
                        .monospacedDigit()
                }

                // Controls
                HStack(spacing: 24) {
                    // Skip back 10 seconds
                    Button {
                        viewModel.seek(to: max(0, viewModel.currentTime - 10))
                    } label: {
                        Image(systemName: "gobackward.10")
                            .font(.title3)
                            .foregroundColor(Color(UIColor.systemBackground))
                            .frame(width: 40, height: 40)
                            .background(Color(UIColor.systemGray4))
                            .clipShape(Circle())
                    }

                    // Play/Pause
                    Button {
                        if viewModel.isPlaying {
                            viewModel.pause()
                        } else {
                            viewModel.play()
                        }
                    } label: {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .foregroundColor(Color(UIColor.systemBackground))
                            .frame(width: 50, height: 50)
                            .background(Color.blue)
                            .clipShape(Circle())
                    }

                    // Skip forward 10 seconds
                    Button {
                        viewModel.seek(to: min(viewModel.duration, viewModel.currentTime + 10))
                    } label: {
                        Image(systemName: "goforward.10")
                            .font(.title3)
                            .foregroundColor(Color(UIColor.systemBackground))
                            .frame(width: 40, height: 40)
                            .background(Color(UIColor.systemGray4))
                            .clipShape(Circle())
                    }

                    // Playback speed
                    Button {
                        // Cycle through playback rates: 1x -> 1.5x -> 2x -> 0.5x -> 0.75x -> 1x
                        switch viewModel.playbackRate {
                        case 1.0: viewModel.playbackRate = 1.5
                        case 1.5: viewModel.playbackRate = 2.0
                        case 2.0: viewModel.playbackRate = 0.5
                        case 0.5: viewModel.playbackRate = 0.75
                        case 0.75: viewModel.playbackRate = 1.0
                        default: viewModel.playbackRate = 1.0
                        }
                    } label: {
                        Text("\(String(format: "%.1fx", viewModel.playbackRate))")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(Color(UIColor.systemBackground))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(UIColor.systemGray4))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal)
            .background(Color(UIColor.systemGray6))
            .cornerRadius(12)
        }
        .task {
            do {
                try await viewModel.loadAudio(from: audioURL)
            } catch {
                #if DEBUG
                print("🎵 CompactAudioPlayer: Failed to load audio - \(error)")
                #endif

                // Try to find the file by UUID in the filename
                if let uuid = extractUUID(from: audioURL.lastPathComponent) {
                    #if DEBUG
                    print("🎵 CompactAudioPlayer: Extracted UUID: \(uuid)")
                    #endif

                    let fileManager = FileManager.default
                    let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]

                    // Try multiple possible filename formats
                    let possibleFilenames = getPossibleFilenames(from: uuid, originalFilename: audioURL.lastPathComponent)

                    #if DEBUG
                    print("🎵 CompactAudioPlayer: Trying multiple possible filenames: \(possibleFilenames)")
                    #endif

                    // Try each possible filename
                    for filename in possibleFilenames {
                        let newURL = documentsPath.appendingPathComponent(filename)

                        #if DEBUG
                        print("🎵 CompactAudioPlayer: Trying path: \(newURL.path)")
                        print("🎵 CompactAudioPlayer: File exists: \(fileManager.fileExists(atPath: newURL.path))")
                        #endif

                        if fileManager.fileExists(atPath: newURL.path) {
                            do {
                                try await viewModel.loadAudio(from: newURL)
                                // If we successfully loaded the audio, break out of the loop
                                break
                            } catch {
                                #if DEBUG
                                print("🎵 CompactAudioPlayer: Failed to load audio with path \(newURL.path) - \(error)")
                                #endif
                                // Continue trying other filenames
                            }
                        }
                    }
                }
            }
        }
        .onDisappear {
            #if DEBUG
            print("🎵 CompactAudioPlayer: View disappearing, cleaning up resources")
            #endif
            cleanupResources()
        }
    }

    // Calculate progress width based on current time and duration
    private var progressWidth: CGFloat {
        guard viewModel.duration > 0 else { return 0 }
        let percentage = viewModel.currentTime / viewModel.duration
        // Adjust for the width of the time labels
        return (UIScreen.main.bounds.width - 120) * CGFloat(percentage)
    }

    // Format time as MM:SS
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

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

#if DEBUG
struct CompactAudioPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            CompactAudioPlayerView(audioURL: URL(string: "file:///tmp/sample.m4a")!)
                .padding()

            Spacer()
        }
        .background(Color(.systemBackground))
        .previewLayout(.sizeThatFits)
    }
}
#endif
