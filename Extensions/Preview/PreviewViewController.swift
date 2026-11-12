import AppKit
import Quartz
import WebKit

/// Quick Look preview (Space bar in Finder, the Finder preview pane, Open panels, Mail…).
@objc(PreviewViewController)
final class PreviewViewController: NSViewController, QLPreviewingController {
    private var renderer: MarkdownWebRenderer!

    override var nibName: NSNib.Name? { nil }

    override func loadView() {
        renderer = MarkdownWebRenderer(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        #if !APPSTORE
        renderer.webView.setValue(false, forKey: "drawsBackground")
        #endif
        renderer.webView.autoresizingMask = [.width, .height]
        view = renderer.webView
        preferredContentSize = NSSize(width: 900, height: 700)
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        _ = view
        renderer.render(url, mode: "preview", timeout: 8, completion: handler)
    }
}
