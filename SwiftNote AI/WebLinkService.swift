import Foundation
import SwiftUI
import UniformTypeIdentifiers
import Combine
import SwiftSoup

// MARK: - Web Link Error
enum WebLinkError: LocalizedError {
    case invalidURL
    case unsupportedProvider
    case downloadFailed(Error)
    case processingFailed(String)
    case fileTooLarge(Int64)
    case scrapingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid or malformed URL"
        case .unsupportedProvider:
            return "Unsupported link provider"
        case .downloadFailed(let error):
            return "Failed to download content: \(error.localizedDescription)"
        case .processingFailed(let message):
            return "Failed to process content: \(message)"
        case .fileTooLarge(let size):
            return "File too large (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))"
        case .scrapingFailed(let error):
            return "Failed to scrape web content: \(error.localizedDescription)"
        }
    }
}

// MARK: - Web Link Service
@MainActor
final class WebLinkService {
    // MARK: - Private Properties
    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var loadingState: LoadingState = .idle

    private let maxFileSize: Int64 = 100_000_000 // 100MB
    private var downloadTask: Task<URL, Error>?

    // MARK: - Supported Providers
    private let fileProviders = [
        "dropbox.com",
        "drive.google.com",
        "icloud.com",
        "docs.google.com"
    ]

    // MARK: - Services
    private let scraperService = WebContentScraperService()

    // MARK: - URL Validation
    func validateURL(_ urlString: String) async throws -> URL {
        guard let url = URL(string: urlString) else {
            #if DEBUG
            print("🌐 WebLinkService: Invalid URL string: \(urlString)")
            #endif
            throw WebLinkError.invalidURL
        }

        return url
    }

    // MARK: - Check if URL is a file provider
    func isFileProvider(_ urlString: String) async -> Bool {
        guard let url = URL(string: urlString),
              let host = url.host?.lowercased() else {
            return false
        }

        return fileProviders.contains(where: { host.contains($0) })
    }

    // MARK: - Content Processing
    func processContent(from urlString: String, progress: @escaping (Double) -> Void) async throws -> (URL?, String?) {
        let url = try await validateURL(urlString)

        // Check if this is a file provider URL or a regular web page
        if await isFileProvider(urlString) {
            // Handle as file download
            return (try await downloadFile(from: url, progress: progress), nil)
        } else {
            // Handle as web page scraping
            let scrapedContent = try await scrapeWebContent(from: urlString)
            return (nil, scrapedContent)
        }
    }

    // MARK: - File Download
    private func downloadFile(from url: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        #if DEBUG
        print("🌐 WebLinkService: Starting file download from: \(url)")
        #endif

        let (tempURL, response) = try await URLSession.shared.download(from: url, progress: progress)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            #if DEBUG
            print("🌐 WebLinkService: Invalid response: \(String(describing: response))")
            #endif
            throw WebLinkError.downloadFailed(URLError(.badServerResponse))
        }

        let fileSize = try tempURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard fileSize <= maxFileSize else {
            #if DEBUG
            print("🌐 WebLinkService: File too large: \(fileSize) bytes")
            #endif
            throw WebLinkError.fileTooLarge(Int64(fileSize))
        }

        // Move to app's temporary directory
        let fileName = url.lastPathComponent
        let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: destinationURL)
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)

        #if DEBUG
        print("🌐 WebLinkService: Successfully downloaded file to: \(destinationURL)")
        #endif

        return destinationURL
    }

    // MARK: - Web Content Scraping
    private func scrapeWebContent(from urlString: String) async throws -> String {
        #if DEBUG
        print("🌐 WebLinkService: Starting web content scraping from: \(urlString)")
        #endif

        do {
            let content = try await scraperService.scrapeContent(from: urlString)

            #if DEBUG
            print("🌐 WebLinkService: Successfully scraped content (\(content.count) characters)")
            #endif

            return content
        } catch {
            #if DEBUG
            print("🌐 WebLinkService: Error scraping content - \(error)")
            #endif
            throw WebLinkError.scrapingFailed(error)
        }
    }

    // MARK: - Cleanup
    func cleanup() {
        #if DEBUG
        print("🌐 WebLinkService: Starting cleanup")
        #endif

        downloadTask?.cancel()
        downloadTask = nil
    }

    deinit {
        #if DEBUG
        print("🌐 WebLinkService: Deinitializing")
        #endif

        // Create a task that won't capture self
        let task = downloadTask
        Task { @MainActor in
            task?.cancel()
            #if DEBUG
            print("🌐 WebLinkService: Cleanup completed")
            #endif
        }
    }
}

// MARK: - URLSession Extension
private extension URLSession {
    func download(from url: URL, progress: @escaping (Double) -> Void) async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = self.downloadTask(with: url) { location, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let location = location, let response = response else {
                    continuation.resume(throwing: WebLinkError.downloadFailed(URLError(.badServerResponse)))
                    return
                }

                continuation.resume(returning: (location, response))
            }

            if let expectedBytes = task.response?.expectedContentLength,
               expectedBytes != NSURLSessionTransferSizeUnknown {
                let observation = task.progress.observe(\.fractionCompleted) { observedProgress, _ in
                    progress(observedProgress.fractionCompleted)
                }
                // Store observation to prevent deallocation
                task.setValue(observation, forKey: "progressObservation")
            }

            task.resume()
        }
    }
}
