import AppKit
import QuickLookThumbnailing
import WebKit

/// Finder icons and thumbnails: a snapshot of the top of the rendered page.
@objc(ThumbnailProvider)
final class ThumbnailProvider: QLThumbnailProvider {
    /// US Letter–shaped page, rendered at a typical window width.
    private static let pageSize = NSSize(width: 820, height: 1061)
    private static var active = Set<ThumbnailJob>()

    override func provideThumbnail(for request: QLFileThumbnailRequest,
                                   _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let url = request.fileURL
        let maxSize = request.maximumSize
        DispatchQueue.main.async {
            let job = ThumbnailJob(pageSize: Self.pageSize)
            Self.active.insert(job)
            job.run(url) { image in
                Self.active.remove(job)
                guard let image else { return handler(nil, CocoaError(.fileReadUnknown)) }
                let page = Self.pageSize
                let scale = min(maxSize.width / page.width, maxSize.height / page.height)
                let size = NSSize(width: (page.width * scale).rounded(), height: (page.height * scale).rounded())
                let reply = QLThumbnailReply(contextSize: size) {
                    NSColor.white.setFill()
                    NSRect(origin: .zero, size: size).fill()
                    image.draw(in: NSRect(origin: .zero, size: size))
                    return true
                }
                reply.extensionBadge = "MD"
                handler(reply, nil)
            }
        }
    }
}

/// Renders off screen in a borderless window (snapshots of window-less web views can come back blank).
final class ThumbnailJob: NSObject {
    private let window: NSWindow
    private let renderer: MarkdownWebRenderer

    init(pageSize: NSSize) {
        let frame = NSRect(origin: .zero, size: pageSize)
        renderer = MarkdownWebRenderer(frame: frame)
        renderer.webView.appearance = NSAppearance(named: .aqua)
        window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = renderer.webView
        super.init()
    }

    func run(_ url: URL, completion: @escaping (NSImage?) -> Void) {
        renderer.render(url, mode: "thumbnail", waitForImages: true, timeout: 10) { [weak self] error in
            guard let self, error == nil else { return completion(nil) }
            let config = WKSnapshotConfiguration()
            config.rect = self.renderer.webView.bounds
            config.afterScreenUpdates = true
            self.renderer.webView.takeSnapshot(with: config) { image, _ in
                completion(image)
                self.window.contentView = nil
            }
        }
    }
}
