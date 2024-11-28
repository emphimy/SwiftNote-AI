import Foundation
import PDFKit
import SwiftUI

// MARK: - PDF Export Error
enum PDFExportError: LocalizedError {
    case failedToCreatePDF
    case failedToSavePDF
    case invalidContent
    
    var errorDescription: String? {
        switch self {
        case .failedToCreatePDF: return "Failed to create PDF document"
        case .failedToSavePDF: return "Failed to save PDF file"
        case .invalidContent: return "Invalid note content"
        }
    }
}

// MARK: - PDF Export Service
final class PDFExportService {
    // MARK: - PDF Generation
    func exportNote(_ note: NoteCardConfiguration) async throws -> URL {
        #if DEBUG
        print("📄 PDFExport: Starting PDF export for note: \(note.title)")
        #endif
        
        // Create PDF document
        let pdfMetaData = [
            kCGPDFContextCreator: "SwiftNote AI",
            kCGPDFContextAuthor: "SwiftNote User",
            kCGPDFContextTitle: note.title
        ]
        
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]
        
        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8) // A4 size
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        
        // Generate temporary file URL
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        
        do {
            try renderer.writePDF(to: fileURL) { context in
                context.beginPage()
                
                // Draw content
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 24, weight: .bold)
                ]
                
                let titleString = note.title as NSString
                titleString.draw(at: CGPoint(x: 50, y: 50), withAttributes: attributes)
                
                // Draw date
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .medium
                let dateString = dateFormatter.string(from: note.date) as NSString
                let dateAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12)
                ]
                dateString.draw(at: CGPoint(x: 50, y: 80), withAttributes: dateAttributes)
                
                // Draw content
                let contentAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12)
                ]
                let contentString = note.preview as NSString
                let contentRect = CGRect(x: 50, y: 120, width: pageRect.width - 100, height: pageRect.height - 140)
                contentString.draw(in: contentRect, withAttributes: contentAttributes)
                
                // Draw tags
                if !note.tags.isEmpty {
                    let tagsString = "Tags: " + note.tags.joined(separator: ", ")
                    let tagsAttributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 10, weight: .medium)
                    ]
                    (tagsString as NSString).draw(at: CGPoint(x: 50, y: pageRect.height - 50), withAttributes: tagsAttributes)
                }
            }
            
            #if DEBUG
            print("📄 PDFExport: Successfully created PDF at: \(fileURL)")
            #endif
            
            return fileURL
        } catch {
            #if DEBUG
            print("📄 PDFExport: Failed to create PDF - \(error)")
            #endif
            throw PDFExportError.failedToCreatePDF
        }
    }
    
    // MARK: - Save to Files
    func savePDF(_ url: URL, withName name: String) async throws -> URL {
        #if DEBUG
        print("📄 PDFExport: Saving PDF with name: \(name)")
        #endif
        
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destinationURL = documentsURL.appendingPathComponent(name).appendingPathExtension("pdf")
        
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
                
                #if DEBUG
                print("📄 PDFExport: Removed existing PDF file")
                #endif
            }
            
            try FileManager.default.copyItem(at: url, to: destinationURL)
            
            #if DEBUG
            print("📄 PDFExport: Successfully saved PDF to: \(destinationURL)")
            #endif
            
            return destinationURL
        } catch {
            #if DEBUG
            print("📄 PDFExport: Failed to save PDF - \(error)")
            #endif
            throw PDFExportError.failedToSavePDF
        }
    }
}
