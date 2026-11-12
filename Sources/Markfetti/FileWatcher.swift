import Foundation

/// Watches one file and calls `onChange` (debounced) when it's modified —
/// including editors that save by replacing the file (rename/delete + create).
final class FileWatcher {
    private let url: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private var retries = 0

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        start()
    }

    deinit { source?.cancel() }

    private func start() {
        source?.cancel()
        source = nil
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // File temporarily missing (mid atomic save) — try again shortly.
            if retries < 40 {
                retries += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.start() }
            }
            return
        }
        if retries > 0 { retries = 0; changed() }  // it came back: it was replaced
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename, .attrib], queue: .main)
        src.setEventHandler { [weak self, weak src] in
            guard let self, let src else { return }
            let flags = src.data
            if flags.contains(.delete) || flags.contains(.rename) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.start() }
            }
            self.changed()
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    private func changed() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, FileManager.default.fileExists(atPath: self.url.path) else { return }
            self.onChange()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
}
