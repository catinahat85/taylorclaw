import Foundation
import PDFKit
import AppKit

/// Extracts plain text from supported document formats.
///
/// PDF uses PDFKit, RTF uses NSAttributedString; everything else is read
/// as UTF-8. Callers should check `DocumentKind.isReadable` first and
/// handle `DocumentReaderError.unsupportedKind` gracefully.
enum DocumentReader {
    static func readText(from url: URL) async throws -> String {
        let kind = DocumentKind.from(url: url)
        guard kind.isReadable else {
            throw DocumentReaderError.unsupportedKind(url.pathExtension)
        }
        switch kind {
        case .pdf:
            return try readPDF(url: url)
        case .rtf:
            return try readRTF(url: url)
        default:
            return try readUTF8(url: url)
        }
    }

    // MARK: - Format readers

    private static func readUTF8(url: URL) throws -> String {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            // Fall back to ASCII/Latin-1 for odd files so we don't hard-fail.
            if let data = try? Data(contentsOf: url),
               let s = String(data: data, encoding: .isoLatin1) {
                return s
            }
            throw DocumentReaderError.decodingFailed(url.lastPathComponent)
        }
    }

    private static func readPDF(url: URL) throws -> String {
        guard let pdf = PDFDocument(url: url) else {
            throw DocumentReaderError.pdfOpenFailed(url.lastPathComponent)
        }
        var pieces: [String] = []
        pieces.reserveCapacity(pdf.pageCount)
        for i in 0..<pdf.pageCount {
            if let page = pdf.page(at: i), let text = page.string {
                pieces.append(text)
            }
        }
        return pieces.joined(separator: "\n\n")
    }

    private static func readRTF(url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard let attr = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) else {
            throw DocumentReaderError.decodingFailed(url.lastPathComponent)
        }
        return attr.string
    }
}

enum DocumentReaderError: Error, Sendable, Equatable, CustomStringConvertible {
    case unsupportedKind(String)
    case pdfOpenFailed(String)
    case decodingFailed(String)

    var description: String {
        switch self {
        case .unsupportedKind(let ext): "Unsupported file type: .\(ext)"
        case .pdfOpenFailed(let name):  "Could not open PDF: \(name)"
        case .decodingFailed(let name): "Could not decode: \(name)"
        }
    }
}
