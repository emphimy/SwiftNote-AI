import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Cloud Storage Error
enum CloudStorageError: LocalizedError {
    case invalidURL
    case downloadFailed(Error)
    case unsupportedFileType(String)
    case invalidResponse
    case fileTooBig(Int64)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid cloud storage URL"
        case .downloadFailed(let error):
            return "Failed to download file: \(error.localizedDescription)"
        case .unsupportedFileType(let type):
            return "Unsupported file type: \(type)"
        case .invalidResponse:
            return "Invalid response from server"
        case .fileTooBig(let size):
            return "File too large (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))"
        }
    }
}

// MARK: - Cloud Storage Service
@MainActor
final class CloudStorageService: ObservableObject {
    // MARK: - Published Properties
    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var loadingState: LoadingState = .idle
    
    // MARK: - Private Properties
    private var downloadTask: Task<URL, Error>?
    private let maxFileSize: Int64 = 100_000_000 // 100MB
    
    // MARK: - URL Validation
    func validateAndProcessURL(_ urlString: String) async throws -> URL {
        guard let url = URL(string: urlString) else {
            #if DEBUG
            print("☁️ CloudStorage: Invalid URL string: \(urlString)")
            #endif
            throw CloudStorageError.invalidURL
        }
        
        // Validate URL is from supported providers
        guard isValidCloudStorageURL(url) else {
            #if DEBUG
            print("☁️ CloudStorage: Unsupported cloud storage provider: \(url.host ?? "unknown")")
            #endif
            throw CloudStorageError.invalidURL
        }
        
        return url
    }
    
    // MARK: - Download Methods
    func downloadFile(from urlString: String) async throws -> URL {
        loadingState = .loading(message: "Preparing download...")
        
        do {
            let url = try await validateAndProcessURL(urlString)
            
            #if DEBUG
            print("☁️ CloudStorage: Starting download from \(url)")
            #endif
            
            downloadTask = Task {
                let (tempURL, response) = try await URLSession.shared.download(from: url) { [weak self] progress in
                    Task { @MainActor in
                        self?.downloadProgress = progress
                        self?.loadingState = .loading(message: "Downloading... \(Int(progress * 100))%")
                    }
                }
                
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    #if DEBUG
                    print("☁️ CloudStorage: Invalid response - Status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                    #endif
                    throw CloudStorageError.invalidResponse
                }
                
                let fileSize = try tempURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard fileSize <= maxFileSize else {
                    #if DEBUG
                    print("☁️ CloudStorage: File too large - Size: \(fileSize)")
                    #endif
                    throw CloudStorageError.fileTooBig(Int64(fileSize))
                }
                
                // Move to app's temporary directory
                let fileName = url.lastPathComponent
                let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                try? FileManager.default.removeItem(at: destinationURL)
                try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                
                #if DEBUG
                print("☁️ CloudStorage: File downloaded successfully to \(destinationURL)")
                #endif
                
                return destinationURL
            }
            
            let downloadedURL = try await downloadTask!.value
            loadingState = .success(message: "Download complete")
            return downloadedURL
            
        } catch {
            #if DEBUG
            print("☁️ CloudStorage: Download failed - \(error)")
            #endif
            loadingState = .error(message: error.localizedDescription)
            throw error
        }
    }
    
    // MARK: - URL Validation Helpers
    private func isValidCloudStorageURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.contains("drive.google.com") || 
               host.contains("dropbox.com") ||
               host.contains("docs.google.com")
    }
    
    // MARK: - Cleanup
    func cleanup() {
        #if DEBUG
        print("☁️ CloudStorage: Starting cleanup")
        #endif
        
        downloadTask?.cancel()
        downloadTask = nil
        
        Task { @MainActor in
            downloadProgress = 0
            loadingState = .idle
        }
    }
    
    deinit {
        #if DEBUG
        print("☁️ CloudStorage: Deinitializing")
        #endif
        
        // Create a separate task that won't retain self
        let task = downloadTask
        Task {
            task?.cancel()
            #if DEBUG
            print("☁️ CloudStorage: Deinit cleanup completed")
            #endif
        }
    }
}

// MARK: - URL Session Extension
private extension URLSession {
    func download(from url: URL, progress: @escaping (Double) -> Void) async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = self.downloadTask(with: url) { location, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let location = location, let response = response else {
                    continuation.resume(throwing: CloudStorageError.invalidResponse)
                    return
                }
                
                continuation.resume(returning: (location, response))
            }
            
            // Fix the progress observation
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
