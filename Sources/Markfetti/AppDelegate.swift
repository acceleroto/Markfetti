import AppKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMainMenu()
    }

    // With no file to open (launched from the Dock/Finder), show the Open panel.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }
    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        NSDocumentController.shared.openDocument(nil)
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    @objc func makeDefaultViewer(_ sender: Any?) {
        let types = ["net.daringfireball.markdown", "public.markdown"].compactMap { UTType($0) }
        let group = DispatchGroup()
        var failure: Error?
        for type in types {
            group.enter()
            NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type) { error in
                if let error { failure = error }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let alert = NSAlert()
            if let failure {
                alert.messageText = "Couldn't set the default app"
                alert.informativeText = failure.localizedDescription
            } else {
                alert.messageText = "Markfetti now opens Markdown files"
                alert.informativeText = "Double-click any .md file in Finder to view it here."
            }
            alert.runModal()
        }
    }

    // MARK: - Menus

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()
        let name = "Markfetti"

        // App
        let appMenu = submenu(in: main, title: name)
        appMenu.addItem(withTitle: "About \(name)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        #if !APPSTORE  // App Review doesn't allow apps to change default handlers themselves
        appMenu.addItem(withTitle: "Make Default Markdown Viewer", action: #selector(makeDefaultViewer(_:)), keyEquivalent: "").target = self
        #endif
        appMenu.addItem(.separator())
        let services = NSMenu(title: "Services")
        appMenu.addItem(withTitle: "Services", action: nil, keyEquivalent: "").submenu = services
        NSApp.servicesMenu = services
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(name)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
            .keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // File
        let file = submenu(in: main, title: "File")
        file.addItem(withTitle: "Open…", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
        let recent = NSMenu(title: "Open Recent")
        // AppKit fills this menu because it contains the "Clear Menu" (clearRecentDocuments:) item.
        recent.addItem(withTitle: "Clear Menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
        file.addItem(withTitle: "Open Recent", action: nil, keyEquivalent: "").submenu = recent
        file.addItem(.separator())
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        file.addItem(withTitle: "Reload", action: #selector(ViewerWindowController.reloadDocument(_:)), keyEquivalent: "r")
        file.addItem(.separator())
        file.addItem(withTitle: "Export as PDF…", action: #selector(ViewerWindowController.exportPDF(_:)), keyEquivalent: "e")
            .keyEquivalentModifierMask = [.command, .shift]
        file.addItem(withTitle: "Page Setup…", action: #selector(NSDocument.runPageLayout(_:)), keyEquivalent: "p")
            .keyEquivalentModifierMask = [.command, .shift]
        file.addItem(withTitle: "Print…", action: #selector(ViewerWindowController.printDocument(_:)), keyEquivalent: "p")

        // Edit
        let edit = submenu(in: main, title: "Edit")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        let find = NSMenu(title: "Find")
        edit.addItem(withTitle: "Find", action: nil, keyEquivalent: "").submenu = find
        find.addItem(withTitle: "Find…", action: #selector(ViewerWindowController.showFind(_:)), keyEquivalent: "f")
        find.addItem(withTitle: "Find Next", action: #selector(ViewerWindowController.findNext(_:)), keyEquivalent: "g")
        find.addItem(withTitle: "Find Previous", action: #selector(ViewerWindowController.findPrevious(_:)), keyEquivalent: "g")
            .keyEquivalentModifierMask = [.command, .shift]
        find.addItem(withTitle: "Use Selection for Find", action: #selector(ViewerWindowController.useSelectionForFind(_:)), keyEquivalent: "e")

        // View
        let view = submenu(in: main, title: "View")
        view.addItem(withTitle: "Show Outline", action: #selector(ViewerWindowController.toggleOutline(_:)), keyEquivalent: "s")
            .keyEquivalentModifierMask = [.command, .control]
        view.addItem(withTitle: "Show Source", action: #selector(ViewerWindowController.toggleSource(_:)), keyEquivalent: "u")
            .keyEquivalentModifierMask = [.command, .option]
        view.addItem(.separator())
        view.addItem(withTitle: "Actual Size", action: #selector(ViewerWindowController.actualSize(_:)), keyEquivalent: "0")
        view.addItem(withTitle: "Zoom In", action: #selector(ViewerWindowController.zoomIn(_:)), keyEquivalent: "=")
        let zoomInAlt = view.addItem(withTitle: "Zoom In", action: #selector(ViewerWindowController.zoomIn(_:)), keyEquivalent: "+")
        zoomInAlt.isHidden = true
        zoomInAlt.allowsKeyEquivalentWhenHidden = true
        view.addItem(withTitle: "Zoom Out", action: #selector(ViewerWindowController.zoomOut(_:)), keyEquivalent: "-")
        view.addItem(.separator())
        view.addItem(withTitle: "Show Toolbar", action: #selector(NSWindow.toggleToolbarShown(_:)), keyEquivalent: "t")
            .keyEquivalentModifierMask = [.command, .option]
        view.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
            .keyEquivalentModifierMask = [.command, .control]

        // Window
        let window = submenu(in: main, title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(.separator())
        window.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = window

        let help = submenu(in: main, title: "Help")
        NSApp.helpMenu = help

        return main
    }

    private func submenu(in main: NSMenu, title: String) -> NSMenu {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        item.submenu = menu
        main.addItem(item)
        return menu
    }
}
