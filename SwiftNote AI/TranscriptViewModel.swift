import Foundation
import Combine
import AVFoundation

enum TranscriptLoadingState {
    case idle
    case loading(String)
    case success(String)
    case error(String)
}

// MARK: - Transcript View Model
@MainActor
final class TranscriptViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published private(set) var segments: [TranscriptSegment] = []
    @Published private(set) var loadingState: TranscriptLoadingState = .idle
    @Published private(set) var searchResults: [TranscriptSearchResult] = []
    @Published var currentTime: TimeInterval = 0 {
        didSet {
            updateHighlightedSegment()
            #if DEBUG
            print("📝 TranscriptVM: Current time updated to \(currentTime)")
            #endif
        }
    }
    @Published var searchText: String = "" {
        didSet {
            performSearch()
        }
    }
    @Published var editingSegment: TranscriptSegment?
    
    // MARK: - Private Properties
    private let transcriptionService: TranscriptionServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    private var isEditingEnabled = false
    
    // MARK: - Initialization
    init(transcriptionService: TranscriptionServiceProtocol = LiveTranscriptionService()) {
        self.transcriptionService = transcriptionService
        
        #if DEBUG
        print("📝 TranscriptVM: Initializing with service: \(String(describing: type(of: transcriptionService)))")
        #endif
        
        setupSearchDebounce()
    }
    
    // MARK: - Search Setup
    private func setupSearchDebounce() {
        $searchText
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.performSearch()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Transcript Generation
    func generateTranscript(for url: URL) async {
        if case .loading = loadingState {
            #if DEBUG
            print("📝 TranscriptVM: Already generating transcript")
            #endif
            return
        }
        
        // Update loading state - Remove message: label
        loadingState = .loading("Generating transcript...")
        
        do {
            #if DEBUG
            print("📝 TranscriptVM: Starting transcript generation for \(url)")
            #endif
            
            let newSegments = try await transcriptionService.transcribe(audioURL: url)
            await MainActor.run {
                self.segments = newSegments
                // Update success state - Remove message: label
                self.loadingState = .success("Transcript generated successfully")
            }
            
            #if DEBUG
            print("📝 TranscriptVM: Generated \(newSegments.count) segments")
            #endif
        } catch {
            #if DEBUG
            print("📝 TranscriptVM: Error generating transcript - \(error)")
            #endif
            
            await MainActor.run {
                // Update error state - Remove message: label
                self.loadingState = .error(error.localizedDescription)
            }
        }
    }
    
    // MARK: - Search
    private func performSearch() {
        guard !searchText.isEmpty else {
            searchResults = []
            return
        }
        
        #if DEBUG
        print("📝 TranscriptVM: Performing search for: \(searchText)")
        #endif
        
        searchResults = transcriptionService.searchTranscript(segments, query: searchText)
        
        #if DEBUG
        print("📝 TranscriptVM: Found \(searchResults.count) matches")
        #endif
    }
    
    // MARK: - Export
    func exportTranscript(format: TranscriptExportFormat) throws -> Data {
        #if DEBUG
        print("📝 TranscriptVM: Exporting transcript in format: \(format)")
        #endif
        
        do {
            let data = try transcriptionService.exportTranscript(segments, format: format)
            #if DEBUG
            print("📝 TranscriptVM: Successfully exported transcript")
            #endif
            return data
        } catch {
            #if DEBUG
            print("📝 TranscriptVM: Export failed - \(error)")
            #endif
            throw error
        }
    }
    
    // MARK: - Editing
    func startEditing(_ segment: TranscriptSegment) {
        #if DEBUG
        print("📝 TranscriptVM: Starting edit for segment: \(segment.id)")
        #endif
        editingSegment = segment
    }
    
    func updateSegment(_ segment: TranscriptSegment, newText: String) {
        do {
            #if DEBUG
            print("📝 TranscriptVM: Updating segment text: \(segment.text) -> \(newText)")
            #endif
            
            let updatedSegment = try transcriptionService.updateSegment(segment, newText: newText)
            if let index = segments.firstIndex(where: { $0.id == segment.id }) {
                segments[index] = updatedSegment
            }
            editingSegment = nil
        } catch {
            #if DEBUG
            print("📝 TranscriptVM: Error updating segment - \(error)")
            #endif
        }
    }
    
    func cancelEditing() {
        #if DEBUG
        print("📝 TranscriptVM: Canceling segment edit")
        #endif
        editingSegment = nil
    }
    
    // MARK: - Navigation
    func seekToSegment(_ segment: TranscriptSegment) -> TimeInterval {
        #if DEBUG
        print("📝 TranscriptVM: Seeking to segment at \(segment.startTime)")
        #endif
        return segment.startTime
    }
    
    // MARK: - Private Methods
    private func updateHighlightedSegment() {
        for (index, segment) in segments.enumerated() {
            let shouldHighlight = currentTime >= segment.startTime && currentTime <= segment.endTime
            if segment.isHighlighted != shouldHighlight {
                segments[index].isHighlighted = shouldHighlight
            }
        }
    }
    
    // MARK: - Cleanup
    deinit {
        #if DEBUG
        print("📝 TranscriptVM: Deinitializing")
        #endif
        cancellables.forEach { $0.cancel() }
    }
}

// MARK: - Helper Extensions
extension TranscriptViewModel {
    var hasSearchResults: Bool {
        !searchResults.isEmpty
    }
    
    var isSearching: Bool {
        !searchText.isEmpty
    }
    
    var displaySegments: [TranscriptSegment] {
        isSearching ? searchResults.map(\.segment) : segments
    }
}
