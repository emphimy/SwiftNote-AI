import Foundation
import SwiftSoup

// MARK: - Web Scraping Error
enum WebScrapingError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case parsingError(Error)
    case emptyContent
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid or malformed URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .parsingError(let error):
            return "Error parsing content: \(error.localizedDescription)"
        case .emptyContent:
            return "No content found on the page"
        }
    }
}

// MARK: - Web Content Scraper Service
actor WebContentScraperService {
    // MARK: - Properties
    private let urlSession: URLSession
    
    // MARK: - Initialization
    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
        
        #if DEBUG
        print("🌐 WebContentScraperService: Initializing")
        #endif
    }
    
    // MARK: - Scraping Methods
    /// Scrapes content from a URL and returns the extracted text
    func scrapeContent(from urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            #if DEBUG
            print("🌐 WebContentScraperService: Invalid URL string: \(urlString)")
            #endif
            throw WebScrapingError.invalidURL
        }
        
        #if DEBUG
        print("🌐 WebContentScraperService: Starting to scrape content from: \(url)")
        #endif
        
        do {
            // Fetch HTML content
            let (data, response) = try await urlSession.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                #if DEBUG
                print("🌐 WebContentScraperService: Invalid response: \(String(describing: response))")
                #endif
                throw WebScrapingError.networkError(URLError(.badServerResponse))
            }
            
            // Convert data to string
            guard let htmlString = String(data: data, encoding: .utf8) else {
                #if DEBUG
                print("🌐 WebContentScraperService: Unable to convert data to string")
                #endif
                throw WebScrapingError.parsingError(NSError(domain: "WebScraping", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to decode HTML content"]))
            }
            
            // Parse HTML with SwiftSoup
            return try extractContent(from: htmlString, url: url)
        } catch let error as WebScrapingError {
            throw error
        } catch {
            #if DEBUG
            print("🌐 WebContentScraperService: Error scraping content - \(error)")
            #endif
            throw WebScrapingError.networkError(error)
        }
    }
    
    // MARK: - Private Methods
    /// Extracts relevant content from HTML using SwiftSoup
    private func extractContent(from htmlString: String, url: URL) throws -> String {
        do {
            let document = try SwiftSoup.parse(htmlString)
            
            // Extract page title
            let pageTitle = try document.title()
            
            // Extract metadata
            let metaDescription = try document.select("meta[name=description]").first()?.attr("content") ?? ""
            
            // Remove unwanted elements that typically don't contain main content
            try document.select("nav, header, footer, aside, script, style, noscript, svg, form, iframe, .ads, .comments, .sidebar").remove()
            
            // Extract main content - try different strategies
            var mainContent = ""
            
            // Strategy 1: Look for main content containers
            let mainElements = try document.select("main, article, .content, .post, .entry, #content, #main, #post")
            if !mainElements.isEmpty() {
                mainContent = try mainElements.text()
            }
            
            // Strategy 2: If no main content found, look for paragraphs
            if mainContent.isEmpty {
                let paragraphs = try document.select("p")
                let paragraphTexts = try paragraphs.map { try $0.text() }
                mainContent = paragraphTexts.joined(separator: "\n\n")
            }
            
            // Strategy 3: If still no content, get body text
            if mainContent.isEmpty {
                mainContent = try document.body()?.text() ?? ""
            }
            
            // If still no content, throw error
            if mainContent.isEmpty {
                #if DEBUG
                print("🌐 WebContentScraperService: No content found on page")
                #endif
                throw WebScrapingError.emptyContent
            }
            
            // Combine all extracted information
            let extractedContent = """
            # \(pageTitle)
            
            URL: \(url.absoluteString)
            
            \(metaDescription.isEmpty ? "" : "## Description\n\(metaDescription)\n\n")
            
            ## Content
            
            \(mainContent)
            """
            
            #if DEBUG
            print("🌐 WebContentScraperService: Successfully extracted content (\(extractedContent.count) characters)")
            #endif
            
            return extractedContent
        } catch let error as WebScrapingError {
            throw error
        } catch {
            #if DEBUG
            print("🌐 WebContentScraperService: Error parsing HTML - \(error)")
            #endif
            throw WebScrapingError.parsingError(error)
        }
    }
}
