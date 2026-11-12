import AppKit
import WebKit

/// One window showing one Markdown document in a WKWebView.
final class ViewerWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate,
    WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, NSMenuItemValidation {

    private var webView: WKWebView!
    private var schemeHandler: SchemeHandler!
    private var watcher: FileWatcher?
    private(set) var isPageReady = false
    private var searchField: NSSearchField?

    private var showOutline = UserDefaults.standard.bool(forKey: "showOutline")
    private var showSource = false
    private static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdtxt", "mdtext"]

    private var markdownDocument: MarkdownDocument? { document as? MarkdownDocument }

    // MARK: - Setup

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.minSize = NSSize(width: 420, height: 300)
        window.tabbingIdentifier = "Markfetti"
        window.titlebarSeparatorStyle = .line
        super.init(window: window)
        window.delegate = self
        shouldCascadeWindows = true

        let webRoot = Bundle.main.resourceURL!.appendingPathComponent("web")
        schemeHandler = SchemeHandler(appRoot: webRoot)

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(schemeHandler, forURLScheme: SchemeHandler.scheme)
        config.userContentController.add(WeakScriptHandler(self), name: "markfetti")
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.suppressesIncrementalRendering = true

        webView = WKWebView(frame: window.contentView!.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsMagnification = true
        webView.setValue(false, forKey: "drawsBackground")
        if #available(macOS 13.3, *) { webView.isInspectable = true }
        let zoom = UserDefaults.standard.double(forKey: "pageZoom")
        webView.pageZoom = zoom > 0 ? zoom : 1
        window.contentView = webView

        let toolbar = NSToolbar(identifier: "ViewerToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        webView.load(URLRequest(url: URL(string: "\(SchemeHandler.scheme)://app/index.html")!))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var document: AnyObject? {
        didSet {
            guard let url = markdownDocument?.fileURL else { return }
            schemeHandler.docRoot = SchemeHandler.allowedRoot(for: url)
            watcher = FileWatcher(url: url) { [weak self] in self?.markdownDocument?.reloadFromDisk() }
            render(keepScroll: false)
        }
    }

    func windowWillClose(_ notification: Notification) {
        watcher = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "markfetti")
    }

    // MARK: - Rendering

    func render(keepScroll: Bool) {
        guard isPageReady, let doc = markdownDocument, let url = doc.fileURL else { return }
        let dir = url.deletingLastPathComponent()
        let root = schemeHandler.docRoot ?? dir
        var payload: [String: Any] = [
            "markdown": doc.text,
            "baseURL": SchemeHandler.docURL(for: dir, isDirectory: true).absoluteString,
            "rootURL": SchemeHandler.docURL(for: root, isDirectory: true).absoluteString,
            "path": url.path,
            "title": url.lastPathComponent,
            "keepScroll": keepScroll,
        ]
        if let anchor = doc.pendingAnchor { payload["anchor"] = anchor; doc.pendingAnchor = nil }
        webView.callAsyncJavaScript(
            "await window.markfetti.render(p, { keepScroll: p.keepScroll });"
                + "window.markfetti.setOutline(o); window.markfetti.setSourceMode(s);",
            arguments: ["p": payload, "o": showOutline, "s": showSource],
            in: nil, in: .page) { [weak self] result in
            if case .failure(let error) = result { NSLog("Render failed: \(error)") }
            // Testing hook: MARKFETTI_EXPORT_PDF=/path/out.pdf exports once rendered, then quits.
            if let out = ProcessInfo.processInfo.environment["MARKFETTI_EXPORT_PDF"], self?.didAutoExport == false {
                self?.didAutoExport = true
                self?.quitAfterPrint = true
                self?.runPrint(saveTo: URL(fileURLWithPath: out))
            }
        }
    }

    func scroll(toAnchor anchor: String) {
        webView.callAsyncJavaScript("window.markfetti.scrollToAnchor(a)", arguments: ["a": anchor],
                                    in: nil, in: .page, completionHandler: nil)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        if body["ready"] as? Bool == true {
            isPageReady = true
            render(keepScroll: false)
        } else if let text = body["copy"] as? String {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    // MARK: - Navigation: links, drops

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.cancel) }
        if url.scheme == SchemeHandler.scheme, url.host == "app", action.navigationType != .linkActivated {
            return decisionHandler(.allow)  // the renderer page itself
        }
        decisionHandler(.cancel)
        open(url)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url { open(url) }  // target="_blank"
        return nil
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isPageReady = false
        webView.reload()
    }

    /// Opens a clicked or dropped URL: Markdown files in this app, everything else in its default app.
    private func open(_ url: URL) {
        let fileURL: URL? = url.isFileURL ? url : SchemeHandler.fileURL(fromDoc: url)
        guard let fileURL else {
            if let scheme = url.scheme?.lowercased(), ["http", "https", "mailto", "tel", "ftp"].contains(scheme) {
                NSWorkspace.shared.open(url)
            }
            return
        }
        let fragment = url.fragment
        let path = URL(fileURLWithPath: fileURL.path)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path.path, isDirectory: &isDir) else { NSSound.beep(); return }
        if !isDir.boolValue && Self.markdownExtensions.contains(path.pathExtension.lowercased()) {
            NSDocumentController.shared.openDocument(withContentsOf: path, display: true) { doc, _, error in
                if let error { NSApp.presentError(error); return }
                (doc as? MarkdownDocument)?.reveal(anchor: fragment)
            }
        } else if isDir.boolValue {
            NSWorkspace.shared.activateFileViewerSelecting([path])
        } else {
            NSWorkspace.shared.open(path)
        }
    }

    // MARK: - Menu actions

    @objc func reloadDocument(_ sender: Any?) { markdownDocument?.reloadFromDisk() }

    @objc func toggleOutline(_ sender: Any?) {
        showOutline.toggle()
        UserDefaults.standard.set(showOutline, forKey: "showOutline")
        webView.callAsyncJavaScript("window.markfetti.setOutline(o)", arguments: ["o": showOutline],
                                    in: nil, in: .page, completionHandler: nil)
    }

    @objc func toggleSource(_ sender: Any?) {
        showSource.toggle()
        webView.callAsyncJavaScript("window.markfetti.setSourceMode(s)", arguments: ["s": showSource],
                                    in: nil, in: .page, completionHandler: nil)
    }

    @objc func zoomIn(_ sender: Any?) { setZoom(webView.pageZoom * 1.1) }
    @objc func zoomOut(_ sender: Any?) { setZoom(webView.pageZoom / 1.1) }
    @objc func actualSize(_ sender: Any?) { setZoom(1) }

    private func setZoom(_ z: CGFloat) {
        webView.pageZoom = min(max(z, 0.5), 3)
        UserDefaults.standard.set(Double(webView.pageZoom), forKey: "pageZoom")
    }

    // Find (⌘F, ⌘G, ⇧⌘G, ⌘E)
    @objc func showFind(_ sender: Any?) {
        guard let field = searchField else { return }
        if window?.toolbar?.isVisible == false { window?.toolbar?.isVisible = true }
        window?.makeFirstResponder(field)
        field.selectText(nil)
    }
    @objc func findNext(_ sender: Any?) { find(backwards: false) }
    @objc func findPrevious(_ sender: Any?) { find(backwards: true) }
    @objc func useSelectionForFind(_ sender: Any?) {
        webView.evaluateJavaScript("window.getSelection().toString()") { [weak self] result, _ in
            guard let s = result as? String, !s.isEmpty else { return }
            self?.searchField?.stringValue = s
            NSPasteboard(name: .find).clearContents()
            NSPasteboard(name: .find).setString(s, forType: .string)
        }
    }
    @objc private func searchFieldAction(_ sender: NSSearchField) {
        let backwards = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
        find(backwards: backwards)
    }

    private func find(backwards: Bool) {
        var term = searchField?.stringValue ?? ""
        if term.isEmpty { term = NSPasteboard(name: .find).string(forType: .string) ?? "" }
        guard !term.isEmpty else { showFind(nil); return }
        let config = WKFindConfiguration()
        config.backwards = backwards
        config.wraps = true
        config.caseSensitive = false
        webView.find(term, configuration: config) { result in
            if !result.matchFound { NSSound.beep() }
        }
    }

    // Printing & PDF — always in light mode, like GitHub's printed pages.
    @objc func printDocument(_ sender: Any?) {
        runPrint(saveTo: nil)
    }

    @objc func exportPDF(_ sender: Any?) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        let base = markdownDocument?.fileURL?.deletingPathExtension().lastPathComponent ?? "Document"
        panel.nameFieldStringValue = base + ".pdf"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.runPrint(saveTo: url)
        }
    }

    private func runPrint(saveTo url: URL?) {
        guard let window else { return }
        let previousAppearance = webView.appearance
        webView.appearance = NSAppearance(named: .aqua)
        // Give the page a moment to re-theme (Mermaid diagrams re-render on theme change).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            let info = (self.markdownDocument?.printInfo ?? NSPrintInfo.shared).copy() as! NSPrintInfo
            info.horizontalPagination = .fit
            info.verticalPagination = .automatic
            info.isHorizontallyCentered = false
            info.isVerticallyCentered = false
            info.topMargin = 36; info.bottomMargin = 36; info.leftMargin = 36; info.rightMargin = 36
            if let url {
                info.jobDisposition = .save
                info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
            }
            let op = self.webView.printOperation(with: info)
            op.view?.frame = self.webView.bounds
            op.showsPrintPanel = url == nil
            op.showsProgressPanel = !self.quitAfterPrint
            op.jobTitle = self.markdownDocument?.displayName ?? "Markdown"
            op.runModal(for: window, delegate: self,
                        didRun: #selector(self.printOperationDidRun(_:success:contextInfo:)),
                        contextInfo: nil)
            self.pendingAppearanceRestore = previousAppearance
        }
    }
    private var pendingAppearanceRestore: NSAppearance?
    private var didAutoExport = false
    private var quitAfterPrint = false
    @objc private func printOperationDidRun(_ op: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        webView.appearance = pendingAppearanceRestore
        pendingAppearanceRestore = nil
        if quitAfterPrint { NSApp.terminate(nil) }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleOutline(_:)):
            item.title = showOutline ? "Hide Outline" : "Show Outline"
        case #selector(toggleSource(_:)):
            item.title = showSource ? "Show Rendered" : "Show Source"
        default: break
        }
        return true
    }

    // MARK: - Toolbar

    private let outlineItemID = NSToolbarItem.Identifier("outline")
    private let searchItemID = NSToolbarItem.Identifier("search")

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [outlineItemID, .flexibleSpace, searchItemID]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch id {
        case outlineItemID:
            let item = NSToolbarItem(itemIdentifier: id)
            item.label = "Outline"
            item.toolTip = "Show or hide the outline"
            item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Outline")
            item.isBordered = true
            item.target = self
            item.action = #selector(toggleOutline(_:))
            return item
        case searchItemID:
            let item = NSSearchToolbarItem(itemIdentifier: id)
            item.searchField.placeholderString = "Find"
            item.preferredWidthForSearchField = 220
            item.searchField.sendsWholeSearchString = true
            item.searchField.target = self
            item.searchField.action = #selector(searchFieldAction(_:))
            searchField = item.searchField
            return item
        default:
            return nil
        }
    }
}

/// Avoids the retain cycle WKUserContentController would create with the window controller.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(c, didReceive: message)
    }
}
