import AppKit

/// In the App Store (sandboxed) build, Markfetti may only read the document the user opened.
/// To show its relative images, the user grants access to an enclosing folder once; that grant
/// is kept as a security-scoped bookmark.
enum FolderAccess {
    static var isSandboxed: Bool { ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil }

    private static let defaultsKey = "folderAccessBookmarks"
    private static var active: [String: URL] = [:]   // path → URL with access started

    private static func covers(_ folder: String, _ file: String) -> Bool {
        folder == "/" || file.hasPrefix(folder + "/")
    }

    /// The broadest granted folder that contains `file` (access is started and kept for the session).
    static func grantedFolder(containing file: URL) -> URL? {
        let path = file.standardizedFileURL.path
        var store = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Data] ?? [:]
        for (folder, data) in store where active[folder] == nil && covers(folder, path) {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                     relativeTo: nil, bookmarkDataIsStale: &stale) else {
                store[folder] = nil
                continue
            }
            guard url.startAccessingSecurityScopedResource() else { continue }
            active[folder] = url
            if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope,
                                                        includingResourceValuesForKeys: nil, relativeTo: nil) {
                store[folder] = fresh
            }
        }
        UserDefaults.standard.set(store, forKey: defaultsKey)
        return active.filter { covers($0.key, path) }.min { $0.key.count < $1.key.count }?.value
    }

    /// Asks the user (as a sheet) for a folder that contains `file`, and remembers it.
    static func requestAccess(for file: URL, in window: NSWindow, completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = file.deletingLastPathComponent()
        panel.prompt = "Allow Access"
        panel.message = "Choose the folder that holds this document's images (for example its repository), "
            + "so Markfetti can show them."
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url?.standardizedFileURL else { return completion(nil) }
            guard covers(url.path, file.standardizedFileURL.path) else {
                let alert = NSAlert()
                alert.messageText = "That folder doesn't contain this document."
                alert.informativeText = "Choose the document's folder or one of the folders above it."
                alert.beginSheetModal(for: window) { _ in completion(nil) }
                return
            }
            if let data = try? url.bookmarkData(options: .withSecurityScope,
                                                includingResourceValuesForKeys: nil, relativeTo: nil) {
                var store = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Data] ?? [:]
                store[url.path] = data
                UserDefaults.standard.set(store, forKey: defaultsKey)
            }
            if url.startAccessingSecurityScopedResource() { active[url.path] = url }
            completion(url)
        }
    }
}
