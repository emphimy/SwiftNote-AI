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
            #if DEBUG
            print("📝 TranscriptVM: Metadata keys: \(note.metadata?.keys.joined(separator: ", ") ?? "none")")
            if let metadata = note.metadata {
                for (key, value) in metadata {
                    print("📝 TranscriptVM: Metadata[\(key)] type: \(type(of: value))")
                }
            }
            #endif

            if let rawTranscript = note.metadata?["rawTranscript"] as? String {
                #if DEBUG
                print("📝 TranscriptVM: Found rawTranscript with \(rawTranscript.count) characters")
                print("📝 TranscriptVM: Transcript sample: \(rawTranscript.prefix(100))")
                #endif

                // Process the transcript for better display
                var formattedParagraphs: [String] = []

                // For audio transcripts, we often get a single long paragraph
                // Let's break it up into more readable chunks

                // First, clean up the transcript by trimming whitespace
                let cleanedTranscript = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)

                #if DEBUG
                print("📝 TranscriptVM: Cleaned transcript length: \(cleanedTranscript.count) characters")
                #endif

                // If the transcript is very short, just use it as is
                if cleanedTranscript.count < 500 {
                    formattedParagraphs = [cleanedTranscript]
                } else {
                    // For longer transcripts, try to break it into paragraphs

                    // First try to split by sentences (periods followed by space)
                    let sentences = cleanedTranscript.components(separatedBy: ". ")
                                                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                                    .filter { !$0.isEmpty }

                    #if DEBUG
                    print("📝 TranscriptVM: Split transcript into \(sentences.count) sentences")
                    #endif

                    // If we have multiple sentences, group them into paragraphs
                    if sentences.count > 1 {
                        let sentencesPerParagraph = 3 // Create a paragraph every 3 sentences
                        var currentParagraph = ""
                        var sentenceCount = 0

                        for sentence in sentences {
                            // Add this sentence to the current paragraph
                            if currentParagraph.isEmpty {
                                currentParagraph = sentence
                            } else {
                                currentParagraph += ". " + sentence
                            }

                            sentenceCount += 1

                            // If we've reached the sentence limit, start a new paragraph
                            if sentenceCount >= sentencesPerParagraph {
                                formattedParagraphs.append(currentParagraph + ".")
                                currentParagraph = ""
                                sentenceCount = 0
                            }
                        }

                        // Add the final paragraph if it's not empty
                        if !currentParagraph.isEmpty {
                            formattedParagraphs.append(currentParagraph + ".")
                        }
                    } else {
                        // If we couldn't split by sentences, split by character count
                        let charsPerParagraph = 300 // About 50-60 words per paragraph
                        var startIndex = cleanedTranscript.startIndex

                        while startIndex < cleanedTranscript.endIndex {
                            let endDistance = min(charsPerParagraph, cleanedTranscript.distance(from: startIndex, to: cleanedTranscript.endIndex))
                            var endIndex = cleanedTranscript.index(startIndex, offsetBy: endDistance)

                            // Try to find a space to break at
                            if endIndex < cleanedTranscript.endIndex {
                                let spaceRange = cleanedTranscript[..<endIndex].lastIndex(of: " ")
                                if let spaceIndex = spaceRange {
                                    endIndex = cleanedTranscript.index(after: spaceIndex)
                                }
                            }

                            let paragraph = String(cleanedTranscript[startIndex..<endIndex])
                            formattedParagraphs.append(paragraph)
                            startIndex = endIndex
                        }
                    }
                }

                #if DEBUG
                print("📝 TranscriptVM: Created \(formattedParagraphs.count) formatted paragraphs")
                if !formattedParagraphs.isEmpty {
                    print("📝 TranscriptVM: First paragraph sample: \(formattedParagraphs[0].prefix(50))")
                }
                #endif

                // No need to add a last paragraph here as we've already handled it above

                // Join paragraphs with double newline
                if formattedParagraphs.isEmpty {
                    // If no paragraphs were created, use the raw transcript
                    transcript = rawTranscript

                    #if DEBUG
                    print("📝 TranscriptVM: No paragraphs created, using raw transcript")
                    #endif
                } else {
                    transcript = formattedParagraphs.joined(separator: "\n\n")

                    #if DEBUG
                    if let transcript = transcript {
                        print("📝 TranscriptVM: Final transcript length: \(transcript.count) characters with \(formattedParagraphs.count) paragraphs")
                    }
                    #endif
                }

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
