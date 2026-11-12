import AppKit
import WebKit

/// The renderer's web files. Extensions live in Markfetti.app/Contents/PlugIns/X.appex, so they
/// read `web/` from the containing app rather than carrying their own 8 MB copy.
enum ExtensionResources {
    static var webRoot: URL {
        if let dev = ProcessInfo.processInfo.environment["MARKFETTI_WEB_ROOT"] { return URL(fileURLWithPath: dev) }
        let own = Bundle.main.resourceURL!.appendingPathComponent("web")
        if FileManager.default.fileExists(atPath: own.path) { return own }
        return Bundle.main.bundleURL            // …/Contents/PlugIns/X.appex
            .deletingLastPathComponent()        // …/Contents/PlugIns
            .deletingLastPathComponent()        // …/Contents
            .appendingPathComponent("Resources/web")
    }
}

/// Loads index.html, renders one Markdown file into it, and calls back when done
/// (or after a timeout, so Quick Look never waits forever).
final class MarkdownWebRenderer: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    private let schemeHandler = SchemeHandler(appRoot: ExtensionResources.webRoot)
    private var fileURL: URL?
    private var mode = "preview"
    private var waitForImages = false
    private var completion: ((Error?) -> Void)?

    init(frame: NSRect) {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(schemeHandler, forURLScheme: SchemeHandler.scheme)
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.suppressesIncrementalRendering = true
        webView = WKWebView(frame: frame, configuration: config)
        super.init()
        webView.navigationDelegate = self
        // Quick Look hosts this view in another process (and thumbnails render in a window that is
        // never shown), so WebKit can wrongly decide the page is hidden and stop painting it.
        // (Private API, so it's left out of the App Store build.)
        #if !APPSTORE
        let occlusion = NSSelectorFromString("_setWindowOcclusionDetectionEnabled:")
        if let method = class_getInstanceMethod(WKWebView.self, occlusion) {
            typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
            unsafeBitCast(method_getImplementation(method), to: Setter.self)(webView, occlusion, false)
        }
        #endif
    }

    func render(_ url: URL, mode: String, waitForImages: Bool = false, timeout: TimeInterval,
                completion: @escaping (Error?) -> Void) {
        fileURL = url
        self.mode = mode
        self.waitForImages = waitForImages
        self.completion = completion
        schemeHandler.docRoot = SchemeHandler.allowedRoot(for: url)
        webView.load(URLRequest(url: URL(string: "\(SchemeHandler.scheme)://app/index.html")!))
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in self?.finish(nil) }
    }

    private func finish(_ error: Error?) {
        guard let completion else { return }
        self.completion = nil
        completion(error)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = fileURL else { return }
        let text: String
        do { text = MarkdownText.decode(try Data(contentsOf: url)) } catch { return finish(error) }
        let root = schemeHandler.docRoot ?? url.deletingLastPathComponent()
        let payload = MarkdownText.payload(for: url, text: text, root: root, mode: mode)
        let script = "await window.markfetti.render(p, { keepScroll: false });"
            + (waitForImages ? "await window.markfetti.imagesLoaded(3000);" : "")
        webView.callAsyncJavaScript(script, arguments: ["p": payload], in: nil, in: .page) { [weak self] result in
            if case .failure(let error) = result { NSLog("Markfetti render failed: \(error)") }
            self?.finish(nil)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(error)
    }

    /// Only the renderer page itself loads in the view; clicked web links open in the browser.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.cancel) }
        if url.scheme == SchemeHandler.scheme && url.host == "app" { return decisionHandler(.allow) }
        if action.navigationType == .linkActivated, ["http", "https", "mailto"].contains(url.scheme ?? "") {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }
}
