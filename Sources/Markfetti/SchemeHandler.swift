import Foundation
import UniformTypeIdentifiers
import WebKit

/// Serves `markfetti://app/…` from the bundled renderer and `markfetti://doc/<absolute path>`
/// from disk — but only inside the document's folder (or its enclosing git repository),
/// so relative images like `![](images/x.png)` or `/docs/a.png` work like on GitHub.
final class SchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "markfetti"
    let appRoot: URL
    var docRoot: URL?
    /// Called (on the main thread) when a document file inside `docRoot` can't be read for lack
    /// of permission — in the sandboxed build that means the user hasn't granted its folder yet.
    var onAccessDenied: (() -> Void)?

    init(appRoot: URL) {
        self.appRoot = appRoot.standardizedFileURL.resolvingSymlinksInPath()
    }

    static func docURL(for fileURL: URL, isDirectory: Bool) -> URL {
        var c = URLComponents()
        c.scheme = scheme
        c.host = "doc"
        c.path = fileURL.standardizedFileURL.path + (isDirectory ? "/" : "")
        return c.url!
    }

    static func fileURL(fromDoc url: URL) -> URL? {
        guard url.scheme == scheme, url.host == "doc" else { return nil }
        return URL(fileURLWithPath: url.path)
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        var file: URL?
        switch url.host {
        case "app":
            let f = appRoot.appendingPathComponent(url.path).standardizedFileURL.resolvingSymlinksInPath()
            if Self.contains(appRoot, f) { file = f }
        case "doc":
            let f = URL(fileURLWithPath: url.path).standardizedFileURL.resolvingSymlinksInPath()
            if let root = docRoot, Self.contains(root, f) { file = f }
        default: break
        }
        var data: Data?
        if let file {
            do { data = try Data(contentsOf: file) } catch let error as CocoaError where error.code == .fileReadNoPermission {
                if url.host == "doc" { onAccessDenied?() }
            } catch {}
        }
        guard let file, let data else {
            let r = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: [:])!
            task.didReceive(r); task.didReceive(Data()); task.didFinish()
            return
        }
        let headers = [
            "Content-Type": Self.mimeType(for: file),
            "Content-Length": String(data.count),
            "Cache-Control": "no-cache",
        ]
        task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    private static func contains(_ root: URL, _ child: URL) -> Bool {
        let r = root.path.hasSuffix("/") ? String(root.path.dropLast()) : root.path
        return child.path == r || child.path.hasPrefix(r + "/")
    }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json", "geojson", "topojson": return "application/json"
        case "svg": return "image/svg+xml"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        case "ttf": return "font/ttf"
        case "md", "markdown", "txt": return "text/plain; charset=utf-8"
        default:
            return UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        }
    }

    /// The folder a document may load files from: its git repository root, else its own folder.
    static func allowedRoot(for document: URL) -> URL {
        gitRoot(for: document) ?? document.deletingLastPathComponent().standardizedFileURL
    }

    /// The enclosing git repository (stopping at the home folder), if any.
    static func gitRoot(for document: URL) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        var cur = document.deletingLastPathComponent().standardizedFileURL
        while cur.path != "/" && cur.path != home {
            if FileManager.default.fileExists(atPath: cur.appendingPathComponent(".git").path) { return cur }
            cur = cur.deletingLastPathComponent()
        }
        return nil
    }
}
