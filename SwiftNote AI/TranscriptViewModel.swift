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
    @Published var transcript: String?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var currentTime: TimeInterval = 0 {
        didSet {
            updateHighlightedSegment()
        }
    }
    @Published var searchText: String = "" {
        didSet {
            performSearch()
        }
    }
    
    // MARK: - Private Properties
    private let note: NoteCardConfiguration?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(note: NoteCardConfiguration) {
        self.note = note
        
        #if DEBUG
        print("📝 TranscriptVM: Initializing with note: \(note.title)")
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
    
    // MARK: - Transcript Loading
    func loadTranscript() async {
        guard let note = note else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // For now, we'll use the raw transcript stored in the note's metadata
            if let rawTranscript = note.metadata?["rawTranscript"] as? String {
                let lines = rawTranscript.components(separatedBy: CharacterSet.newlines)
                var currentMinute = -1
                var currentText = ""
                var formattedParagraphs: [String] = []
                
                for line in lines {
                    if line.isEmpty { continue }
                    
                    // Updated regex to handle any number of digits for minutes
                    if let timeRange = line.range(of: "\\[(\\d+):\\d{2}\\]", options: [.regularExpression]) {
                        let timeStr = String(line[timeRange])
                        let text = String(line[line.index(after: timeRange.upperBound)...])
                            .trimmingCharacters(in: CharacterSet.whitespaces)
                        
                        // Extract minute from timestamp
                        if let minuteRange = timeStr.range(of: "\\d+", options: .regularExpression) {
                            if let minute = Int(timeStr[minuteRange]) {
                                if minute != currentMinute {
                                    // Save current paragraph if exists
                                    if !currentText.isEmpty {
                                        formattedParagraphs.append(currentText)
                                        currentText = ""
                                    }
                                    currentMinute = minute
                                }
                                
                                // Add timestamp and text
                                if currentText.isEmpty {
                                    currentText = timeStr + " " + text
                                } else {
                                    currentText += " " + text
                                }
                            }
                        }
                    }
                }
                
                // Add the last paragraph
                if !currentText.isEmpty {
                    formattedParagraphs.append(currentText)
                }
                
                // Join paragraphs with double newline
                transcript = formattedParagraphs.joined(separator: "\n\n")
                
            } else {
                throw NSError(domain: "TranscriptVM", code: 1001, userInfo: [
                    NSLocalizedDescriptionKey: "No transcript found for this note"
                ])
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    // MARK: - Search
    private func performSearch() {
        guard !searchText.isEmpty else {
            searchResults = []
            return
        }
        
        let results = segments.compactMap { segment -> TranscriptSearchResult? in
            guard let range = segment.text.range(of: searchText, options: .caseInsensitive) else {
                return nil
            }
            return TranscriptSearchResult(segment: segment, range: range)
        }
        
        searchResults = results
        
        #if DEBUG
        print("📝 TranscriptVM: Found \(results.count) search results for '\(searchText)'")
        #endif
    }
    
    // MARK: - Segment Highlighting
    private func updateHighlightedSegment() {
        for (index, segment) in segments.enumerated() {
            if currentTime >= segment.startTime && currentTime < segment.endTime {
                #if DEBUG
                print("📝 TranscriptVM: Highlighted segment at index \(index)")
                #endif
                break
            }
        }
    }
}

// MARK: - Helper Extensions
extension TranscriptViewModel {
    var hasSearchResults: Bool {
        !searchResults.isEmpty
    }
    
    var hasSegments: Bool {
        !segments.isEmpty
    }
    
    var isGeneratingTranscript: Bool {
        if case .loading = loadingState {
            return true
        }
        return false
    }
}
