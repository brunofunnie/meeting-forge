import Foundation
import Ink
import WebKit
import AppKit

public enum ExportError: Error {
    case pdfFailed(String)
}

public enum MinutesExporter {
    public static func html(markdown: String, title: String) -> String {
        let body = MarkdownParser().html(from: markdown)
        let safeTitle = title
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>\(safeTitle)</title>
        <style>
        body { font-family: -apple-system, "Helvetica Neue", sans-serif; max-width: 46rem;
               margin: 2rem auto; padding: 0 1rem; line-height: 1.55; color: #1d1d1f; }
        h1, h2, h3 { line-height: 1.25; }
        h2 { border-bottom: 1px solid #d2d2d7; padding-bottom: .3rem; margin-top: 2rem; }
        li { margin: .25rem 0; }
        code { background: #f5f5f7; padding: .1rem .3rem; border-radius: 4px; }
        @media print { body { margin: 0 auto; font-size: 11pt; } }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    @MainActor
    public static func pdf(markdown: String, title: String) async throws -> Data {
        let htmlDocument = html(markdown: markdown, title: title)
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 794, height: 1123)) // A4 @ 96dpi
        let navigator = NavigationWaiter()
        webView.navigationDelegate = navigator
        webView.loadHTMLString(htmlDocument, baseURL: nil)
        try await navigator.waitUntilLoaded()
        do {
            let config = WKPDFConfiguration()
            return try await webView.pdf(configuration: config)
        } catch {
            throw ExportError.pdfFailed(String(describing: error))
        }
    }

    @MainActor
    public static func copyToClipboard(markdown: String, richText: Bool) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if richText {
            let htmlDocument = html(markdown: markdown, title: "Minutes")
            if let data = htmlDocument.data(using: .utf8),
               let attributed = NSAttributedString(
                   html: data, options: [.characterEncoding: String.Encoding.utf8.rawValue],
                   documentAttributes: nil),
               let rtf = attributed.rtf(from: NSRange(location: 0, length: attributed.length)) {
                pasteboard.setData(rtf, forType: .rtf)
            }
        }
        pasteboard.setString(markdown, forType: .string)
    }
}

@MainActor
private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func waitUntilLoaded() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: ExportError.pdfFailed(String(describing: error)))
        continuation = nil
    }
}
