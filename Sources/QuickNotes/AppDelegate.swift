import AppKit
import QuickNotesCore
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var controller: NotesController?
    private var statusItem: NSStatusItem?
    private var lockDescriptor: Int32 = -1
    private var handledRequestIDs: [String] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = nil
        do {
            let directory: URL
            if let override = ProcessInfo.processInfo.environment["QUICK_NOTES_DIRECTORY"] {
                directory = URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
            } else {
                directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                    appropriateFor: nil, create: true).appendingPathComponent("Quick Notes/notes", isDirectory: true)
            }
            let store = try NoteStore(directory: directory)
            lockDescriptor = Darwin.open(directory.appendingPathComponent(".app.lock").path, O_CREAT | O_RDWR, 0o600)
            guard lockDescriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            guard flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0 else {
                AppRequest(arguments: CommandLine.arguments).send()
                NSApp.terminate(nil)
                return
            }
            controller = try NotesController(store: store)
            buildMainMenu()
            buildStatusMenu()
            DistributedNotificationCenter.default().addObserver(self, selector: #selector(handleAppRequest(_:)),
                name: AppRequest.show.notificationName, object: nil)
            DistributedNotificationCenter.default().addObserver(self, selector: #selector(handleAppRequest(_:)),
                name: AppRequest.toggle.notificationName, object: nil)
            controller?.show()
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Quick Notes couldn’t open your notes"
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        controller?.save() == false ? .terminateCancel : .terminateNow
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        if !NSApp.isHidden { controller?.revealPanel() }
    }
    func applicationDidHide(_ notification: Notification) {
        controller?.dismissPanel()
    }
    func applicationWillTerminate(_ notification: Notification) {
        if lockDescriptor >= 0 { Darwin.close(lockDescriptor) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.show()
        return true
    }

    private func buildStatusMenu() {
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Quick Notes")
        image?.isTemplate = true
        status.button?.image = image
        status.button?.toolTip = "Quick Notes"
        let menu = NSMenu()
        add(menu, "Show / Hide Quick Notes", #selector(toggle))
        add(menu, "New Note", #selector(newNote))
        add(menu, "Note History", #selector(history))
        menu.addItem(.separator())
        add(menu, "Open Notes Folder…", #selector(reveal))
        menu.addItem(.separator())
        add(menu, "Quit Quick Notes", #selector(quit), "q")
        status.menu = menu
        statusItem = status
    }

    private func buildMainMenu() {
        let main = NSMenu()
        let app = NSMenu()
        add(app, "About Quick Notes", #selector(about))
        app.addItem(.separator())
        add(app, "Quit Quick Notes", #selector(quit), "q")
        let appItem = NSMenuItem(); appItem.submenu = app; main.addItem(appItem)
        let edit = NSMenu(title: "Edit")
        for (name, action, key) in [("Undo", "undo:", "z"), ("Redo", "redo:", "Z"),
            ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: name, action: Selector(action), keyEquivalent: key)
        }
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit; main.addItem(editItem)
        NSApp.mainMenu = main
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }
    @objc private func handleAppRequest(_ notification: Notification) {
        let id = notification.userInfo?["requestID"] as? String
        if id == nil || !handledRequestIDs.contains(id!) {
            if let id {
                handledRequestIDs.append(id)
                if handledRequestIDs.count > 128 { handledRequestIDs.removeFirst() }
            }
            if notification.name == AppRequest.toggle.notificationName { controller?.toggle() }
            else { controller?.show() }
        }
        if let id {
            DistributedNotificationCenter.default().postNotificationName(AppRequest.acknowledgement,
                object: id, userInfo: nil, deliverImmediately: true)
        }
    }
    @objc func show() { controller?.show() }
    @objc func toggle() { controller?.toggle() }
    @objc func newNote() { controller?.newNote() }
    @objc func history() { controller?.show(); controller?.toggleHistory() }
    @objc func reveal() { controller?.revealNotes() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func about() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Quick Notes", .applicationVersion: "0.1.0",
            .credits: NSAttributedString(string: "A little space for your thoughts.\nPlain Markdown. Saved on your Mac.")
        ])
    }
}
