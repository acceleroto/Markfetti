import Foundation

/// Shared by the app and its Quick Look extensions (compiled into each by build.sh).
enum MarkdownText {
    /// Decodes a Markdown file: UTF-16 with BOM, UTF-8 (BOM stripped), else Windows-1252.
    static func decode(_ data: Data) -> String {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let s = String(data: data, encoding: .utf16) { return s }
        if var s = String(data: data, encoding: .utf8) {
            if s.hasPrefix("\u{FEFF}") { s.removeFirst() }
            return s
        }
        return String(data: data, encoding: .windowsCP1252) ?? String(decoding: data, as: UTF8.self)
    }

    /// The object passed to `window.markfetti.render(payload)` in render.js.
    static func payload(for fileURL: URL, text: String, root: URL, mode: String = "app") -> [String: Any] {
        let dir = fileURL.deletingLastPathComponent()
        return [
            "markdown": text,
            "baseURL": SchemeHandler.docURL(for: dir, isDirectory: true).absoluteString,
            "rootURL": SchemeHandler.docURL(for: root, isDirectory: true).absoluteString,
            "path": fileURL.path,
            "title": fileURL.lastPathComponent,
            "mode": mode,
        ]
    }
}
