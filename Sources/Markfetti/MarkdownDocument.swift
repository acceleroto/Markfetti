import AppKit

/// A read-only Markdown document. NSDocument gives us windows-per-file, tabs,
/// Open Recent, the title-bar proxy icon and Finder "Open With" for free.
@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {
    private(set) var text = ""
    /// Fragment to jump to once the page has rendered (from a link like other.md#section).
    var pendingAnchor: String?

    override class var autosavesInPlace: Bool { false }
    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { true }
    override var isDocumentEdited: Bool { false }  // never asks to save

    override func read(from data: Data, ofType typeName: String) throws {
        text = MarkdownDocument.decode(data)
    }

    override func data(ofType typeName: String) throws -> Data {
        throw CocoaError(.featureUnsupported)
    }

    override func makeWindowControllers() {
        addWindowController(ViewerWindowController())
    }

    private var viewer: ViewerWindowController? {
        windowControllers.first as? ViewerWindowController
    }

    /// Re-reads the file after it changed on disk.
    func reloadFromDisk() {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return }
        text = MarkdownDocument.decode(data)
        fileModificationDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        viewer?.render(keepScroll: true)
    }

    /// Brings the window forward and scrolls to `anchor` (if any).
    func reveal(anchor: String?) {
        showWindows()
        guard let anchor, !anchor.isEmpty else { return }
        if let viewer, viewer.isPageReady { viewer.scroll(toAnchor: anchor) } else { pendingAnchor = anchor }
    }

    static func decode(_ data: Data) -> String {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let s = String(data: data, encoding: .utf16) { return s }
        if var s = String(data: data, encoding: .utf8) {
            if s.hasPrefix("\u{FEFF}") { s.removeFirst() }
            return s
        }
        return String(data: data, encoding: .windowsCP1252) ?? String(decoding: data, as: UTF8.self)
    }
}
