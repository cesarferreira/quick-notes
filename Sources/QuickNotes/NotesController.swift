import AppKit
import QuickNotesCore

final class NotesController: NSObject, NSWindowDelegate, NSTextViewDelegate, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    let panel: NotesPanel
    let store: NoteStore
    let motion: NoteMotion
    let editor = MarkdownTextView(frame: .zero)
    private(set) var current = Note()
    private var persistedBody: String?
    private var notes: [Note] = []
    private var visibleNotes: [Note] = []
    private var swipeNoteIDs: [String]?
    private var swipeDraft: Note?
    private var dirty = false
    private var saveTimer: Timer?
    private var historyOpen = false
    private var pinned = UserDefaults.standard.object(forKey: "keepOnTop") as? Bool ?? true
    private var menuOpen = false
    private var dismissing = false
    private var presentationGeneration = 0
    private var firstShow = true
    private let content = NoteSurface()
    private let titleLabel = label("Untitled note", size: 13, weight: .medium, color: .white.withAlphaComponent(0.35))
    private let counter = label("0 characters", size: 12, weight: .medium, color: .white.withAlphaComponent(0.30))
    private let saveStatus = label("", size: 10, color: .tertiaryLabelColor)
    private let notice = label("", size: 11, color: .systemOrange)
    private let editorScroll = NotesScrollView()
    private let historyView = NSView()
    let search = NSSearchField()
    let table = HistoryTable()
    private let emptyHistory = label("No notes yet. Create your first one with ⌘N.", size: 13, color: .secondaryLabelColor)
    private var pinButton: IconButton!
    private var historyButton: IconButton!

    init(store: NoteStore, motion: NoteMotion = NoteMotion()) throws {
        self.store = store
        self.motion = motion
        editor.motion = motion
        notes = try store.load()
        if let id = UserDefaults.standard.string(forKey: "lastNote"), let note = notes.first(where: { $0.id == id }) {
            current = note
            persistedBody = note.body
        } else if let note = notes.first {
            current = note
            persistedBody = note.body
        }
        panel = NotesPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 310),
            styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        configureWindow()
        buildContent()
        loadEditor()
    }

    private func configureWindow() {
        panel.title = "Quick Notes"
        panel.identifier = NSUserInterfaceItemIdentifier("QuickNotesPanel")
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 400, height: 260)
        panel.maxSize = NSSize(width: 1000, height: 1000)
        panel.setFrameAutosaveName("QuickNotesPanel")
        panel.delegate = self
        panel.shortcut = { [weak self] key, modifiers in self?.handleShortcut(key, modifiers: modifiers) ?? false }
        content.wantsLayer = true
        content.layer?.cornerRadius = 26
        content.layer?.cornerCurve = .continuous
        content.layer?.masksToBounds = true
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: panel.frame.size))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.isEmphasized = true
        effect.maskImage = roundedMaterialMask(radius: 26)
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 26
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 0.5
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        content.frame = effect.bounds
        content.autoresizingMask = [.width, .height]
        effect.addSubview(content)
        panel.contentView = effect
        // The borderless window frame must share the glass silhouette; rounding
        // only its content leaves a rectangular compositor surface and shadow.
        if let frame = panel.contentView?.superview {
            frame.wantsLayer = true
            frame.layer?.backgroundColor = nil
            frame.layer?.cornerRadius = 26
            frame.layer?.cornerCurve = .continuous
            frame.layer?.masksToBounds = true
        }
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.invalidateShadow()
    }

    private func buildContent() {
        let drag = DragArea()
        drag.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(drag)
        let close = IconButton(symbol: "xmark", label: "Hide · Esc", target: self, action: #selector(hide), motion: motion)
        close.contentTintColor = .tertiaryLabelColor
        content.addSubview(close)
        titleLabel.alignment = .center
        content.addSubview(titleLabel)
        historyButton = IconButton(symbol: "clock.arrow.circlepath", label: "Note history · ⌘H", target: self, action: #selector(toggleHistory), motion: motion)
        let new = IconButton(symbol: "plus", label: "New note · ⌘N", target: self, action: #selector(newNote), motion: motion)
        let toolbar = NSStackView(views: [historyButton, new])
        toolbar.spacing = 2
        toolbar.orientation = .horizontal
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.wantsLayer = true
        toolbar.layer?.cornerRadius = 15
        toolbar.layer?.borderWidth = 0.5
        toolbar.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
        toolbar.edgeInsets = NSEdgeInsets(top: 1, left: 3, bottom: 1, right: 3)
        content.addSubview(toolbar)
        editor.configure()
        editor.delegate = self
        editor.fontSize = CGFloat(UserDefaults.standard.double(forKey: "fontSize").nonzero ?? 14)
        editor.onDismiss = { [weak self] in self?.hide() }
        editorScroll.translatesAutoresizingMaskIntoConstraints = false
        editorScroll.drawsBackground = false
        editorScroll.borderType = .noBorder
        editorScroll.hasVerticalScroller = true
        editorScroll.scrollerStyle = .overlay
        editorScroll.documentView = editor
        editorScroll.onNavigate = { [weak self] direction in _ = self?.navigateHistory(direction) }
        content.addSubview(editorScroll)
        notice.maximumNumberOfLines = 2
        notice.lineBreakMode = .byWordWrapping
        content.addSubview(notice)
        counter.alignment = .center
        content.addSubview(counter)
        content.addSubview(saveStatus)
        pinButton = IconButton(symbol: "pin", label: "Keep on top", target: self, action: #selector(togglePin), motion: motion)
        updatePinButton()
        content.addSubview(pinButton)
        let format = IconButton(symbol: "textformat", label: "Formatting and options", target: self, action: #selector(showFormat), motion: motion)
        content.addSubview(format)
        buildHistory()
        NSLayoutConstraint.activate([
            drag.topAnchor.constraint(equalTo: content.topAnchor), drag.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            drag.trailingAnchor.constraint(equalTo: content.trailingAnchor), drag.heightAnchor.constraint(equalToConstant: 48),
            close.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12), close.topAnchor.constraint(equalTo: content.topAnchor, constant: 11),
            toolbar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12), toolbar.centerYAnchor.constraint(equalTo: close.centerYAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: close.centerYAnchor), titleLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: close.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: toolbar.leadingAnchor, constant: -10),
            editorScroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 52),
            editorScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 17),
            editorScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -17),
            editorScroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -58),
            notice.leadingAnchor.constraint(equalTo: editorScroll.leadingAnchor, constant: 6), notice.trailingAnchor.constraint(equalTo: editorScroll.trailingAnchor),
            notice.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -40),
            counter.centerXAnchor.constraint(equalTo: content.centerXAnchor), counter.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
            pinButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16), pinButton.centerYAnchor.constraint(equalTo: counter.centerYAnchor),
            saveStatus.leadingAnchor.constraint(equalTo: pinButton.trailingAnchor, constant: 3), saveStatus.centerYAnchor.constraint(equalTo: counter.centerYAnchor),
            saveStatus.widthAnchor.constraint(lessThanOrEqualToConstant: 70),
            format.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16), format.centerYAnchor.constraint(equalTo: counter.centerYAnchor)
        ])
    }

    private func buildHistory() {
        historyView.translatesAutoresizingMaskIntoConstraints = false
        historyView.isHidden = true
        content.addSubview(historyView)
        search.translatesAutoresizingMaskIntoConstraints = false
        search.placeholderString = "Search your notes…"
        search.font = .systemFont(ofSize: 13)
        search.focusRingType = .none
        search.delegate = self
        search.sendsSearchStringImmediately = true
        search.setAccessibilityLabel("Search notes")
        historyView.addSubview(search)
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("notes"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 65
        table.intercellSpacing = NSSize(width: 0, height: 3)
        table.backgroundColor = .clear
        table.style = .plain
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(openSelectedNote)
        table.onOpen = { [weak self] in self?.openSelectedNote() }
        table.onDismiss = { [weak self] in self?.toggleHistory() }
        table.setAccessibilityLabel("Note history")
        scroll.documentView = table
        historyView.addSubview(scroll)
        historyView.addSubview(emptyHistory)
        emptyHistory.alignment = .center
        NSLayoutConstraint.activate([
            historyView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22),
            historyView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
            historyView.topAnchor.constraint(equalTo: content.topAnchor, constant: 58),
            historyView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -50),
            search.topAnchor.constraint(equalTo: historyView.topAnchor), search.leadingAnchor.constraint(equalTo: historyView.leadingAnchor),
            search.trailingAnchor.constraint(equalTo: historyView.trailingAnchor), search.heightAnchor.constraint(equalToConstant: 28),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 12), scroll.leadingAnchor.constraint(equalTo: historyView.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: historyView.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: historyView.bottomAnchor),
            emptyHistory.centerXAnchor.constraint(equalTo: historyView.centerXAnchor), emptyHistory.centerYAnchor.constraint(equalTo: scroll.centerYAnchor)
        ])
    }

    func show() {
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        revealPanel()
    }

    func revealPanel() {
        let opening = !panel.isVisible || dismissing
        if opening {
            presentationGeneration += 1
            dismissing = false
        }
        if !panel.isVisible {
            refreshFromDisk()
            position()
            panel.alphaValue = motion.isEnabled ? 0 : 1
        }
        focusEditor()
        if opening { motion.reveal(panel) }
    }

    func focusEditor() {
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(historyOpen ? search : editor)
    }
    func toggle() { panel.isVisible && !dismissing ? hide() : show() }

    @objc func hide() {
        _ = dismissPanel {
            if !NSApp.isHidden && NSApp.isActive && NSApp.keyWindow == nil { NSApp.hide(nil) }
        }
    }

    @discardableResult func dismissPanel(completion: (() -> Void)? = nil) -> Bool {
        guard !dismissing else { return true }
        guard save() else { return false }
        guard panel.isVisible else { completion?(); return true }
        dismissing = true
        presentationGeneration += 1
        let generation = presentationGeneration
        panel.resignKey()
        motion.dismiss(panel) { [weak self] in
            guard let self, self.presentationGeneration == generation, self.dismissing else { return }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
            self.dismissing = false
            completion?()
        }
        return true
    }

    func windowDidResignKey(_ notification: Notification) {
        if !pinned && !menuOpen && !dismissing { hide() }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { hide(); return false }

    private func position() {
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame.insetBy(dx: 16, dy: 16)
        if firstShow || !screen.frame.contains(NSPoint(x: panel.frame.midX, y: panel.frame.midY)) {
            let remembered = UserDefaults.standard.string(forKey: "NSWindow Frame QuickNotesPanel") != nil
            if !remembered || !screen.frame.contains(NSPoint(x: panel.frame.midX, y: panel.frame.midY)) {
                panel.setFrameOrigin(NSPoint(x: visible.midX - panel.frame.width / 2, y: visible.minY + visible.height * 0.69 - panel.frame.height / 2))
            }
        }
        firstShow = false
        panel.setFrameOrigin(NSPoint(x: min(max(panel.frame.minX, visible.minX), max(visible.minX, visible.maxX - panel.frame.width)),
            y: min(max(panel.frame.minY, visible.minY), max(visible.minY, visible.maxY - panel.frame.height))))
    }

    private func loadEditor() {
        editor.string = current.body
        editor.undoManager?.removeAllActions()
        editor.restyle()
        editor.setSelectedRange(NSRange(location: (current.body as NSString).length, length: 0))
        editor.scrollToBeginningOfDocument(nil)
        dirty = false
        notice.stringValue = ""
        updateLabels()
    }

    private func updateLabels() {
        titleLabel.stringValue = historyOpen ? "Your notes" : current.title
        panel.title = historyOpen ? "Quick Notes — History" : current.title
        counter.stringValue = historyOpen ? "\(visibleNotes.count) \(visibleNotes.count == 1 ? "note" : "notes")" : "\(current.body.count) characters"
        saveStatus.stringValue = dirty ? "Saving…" : (persistedBody == nil ? "" : "Saved")
        saveStatus.textColor = .tertiaryLabelColor
    }

    func textDidChange(_ notification: Notification) {
        guard notification.object as? NSTextView === editor else { return }
        editor.restyle()
        current.body = editor.string
        dirty = true
        updateLabels()
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in _ = self?.save() }
    }

    @discardableResult func save() -> Bool {
        saveTimer?.invalidate()
        guard dirty else { return true }
        if current.body.isEmpty && persistedBody == nil { dirty = false; updateLabels(); return true }
        do {
            do { try store.save(current, expectedBody: persistedBody) }
            catch NoteStoreError.conflict {
                let copy = Note(body: current.body)
                try store.save(copy, expectedBody: nil)
                if let index = swipeNoteIDs?.firstIndex(of: current.id) {
                    swipeNoteIDs?[index] = copy.id
                }
                if swipeDraft?.id == current.id { swipeDraft = nil }
                current = copy
                notice.stringValue = NoteStoreError.conflict.localizedDescription
            }
            persistedBody = current.body
            current.modified = Date()
            dirty = false
            UserDefaults.standard.set(current.id, forKey: "lastNote")
            updateLabels()
            return true
        } catch {
            notice.stringValue = "Couldn’t save: \(error.localizedDescription)"
            saveStatus.stringValue = "Unsaved"
            saveStatus.textColor = .systemOrange
            return false
        }
    }

    private func refreshFromDisk() {
        guard save() else { return }
        do {
            notes = try store.load()
            resetSwipeHistory()
            if let note = notes.first(where: { $0.id == current.id }), note.body != current.body {
                current = note
                persistedBody = note.body
                loadEditor()
            }
            if historyOpen { filterHistory() }
        } catch { notice.stringValue = error.localizedDescription }
    }

    @discardableResult func navigateHistory(_ direction: NoteHistoryDirection) -> Bool {
        guard !historyOpen else { return false }
        guard save() else { return false }
        do {
            let saved = try store.load()
            var order = swipeNoteIDs ?? saved.map(\.id)
            if !order.contains(current.id) { order.insert(current.id, at: 0) }
            if persistedBody == nil { swipeDraft = current }
            swipeNoteIDs = order
            guard let index = order.firstIndex(of: current.id) else { return false }
            let step = direction == .older ? 1 : -1
            var destination = index + step
            while order.indices.contains(destination) {
                let id = order[destination]
                let stored = saved.first(where: { $0.id == id })
                if let note = stored ?? (swipeDraft?.id == id ? swipeDraft : nil) {
                    motion.transition(in: editorScroll, direction: direction)
                    current = note
                    persistedBody = stored?.body
                    if stored != nil { UserDefaults.standard.set(note.id, forKey: "lastNote") }
                    loadEditor()
                    panel.makeFirstResponder(editor)
                    return true
                }
                destination += step
            }
        } catch { notice.stringValue = error.localizedDescription }
        return false
    }

    private func resetSwipeHistory() {
        swipeNoteIDs = nil
        swipeDraft = nil
    }

    @objc func newNote() {
        guard save() else { return }
        motion.transition(in: content)
        resetSwipeHistory()
        current = Note()
        persistedBody = nil
        historyOpen = false
        historyView.isHidden = true
        editorScroll.isHidden = false
        historyButton.contentTintColor = .secondaryLabelColor
        loadEditor()
        show()
    }

    @objc func toggleHistory() {
        guard save() else { return }
        motion.transition(in: content)
        historyOpen.toggle()
        historyView.isHidden = !historyOpen
        editorScroll.isHidden = historyOpen
        historyButton.contentTintColor = historyOpen ? .controlAccentColor : .secondaryLabelColor
        if historyOpen {
            resetSwipeHistory()
            do { notes = try store.load() } catch { notice.stringValue = error.localizedDescription }
            search.stringValue = ""
            filterHistory()
            panel.makeFirstResponder(search)
        } else { panel.makeFirstResponder(editor) }
        updateLabels()
    }

    private func filterHistory() {
        visibleNotes = store.search(notes, query: search.stringValue)
        table.reloadData()
        emptyHistory.isHidden = !visibleNotes.isEmpty
        emptyHistory.stringValue = notes.isEmpty ? "No notes yet. Create your first one with ⌘N." : "No matching notes."
        if !visibleNotes.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        updateLabels()
    }
    func controlTextDidChange(_ obj: Notification) { filterHistory() }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) { openSelectedNote(); return true }
        if commandSelector == #selector(NSResponder.moveDown(_:)) { panel.makeFirstResponder(table); return true }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { toggleHistory(); return true }
        return false
    }
    func numberOfRows(in tableView: NSTableView) -> Int { visibleNotes.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard visibleNotes.indices.contains(row) else { return nil }
        let note = visibleNotes[row]
        let cell = NSTableCellView()
        let title = label(note.title, size: 13, weight: .semibold)
        let preview = label(note.preview.isEmpty ? "Empty note" : note.preview, size: 11, color: .secondaryLabelColor)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let date = label(formatter.localizedString(for: note.modified, relativeTo: Date()), size: 10, color: .tertiaryLabelColor)
        cell.addSubview(title); cell.addSubview(preview); cell.addSubview(date)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10), title.topAnchor.constraint(equalTo: cell.topAnchor, constant: 9),
            title.trailingAnchor.constraint(lessThanOrEqualTo: date.leadingAnchor, constant: -12),
            date.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10), date.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            preview.leadingAnchor.constraint(equalTo: title.leadingAnchor), preview.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 5),
            preview.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10)
        ])
        date.setContentCompressionResistancePriority(.required, for: .horizontal)
        return cell
    }

    @objc func openSelectedNote() {
        guard visibleNotes.indices.contains(table.selectedRow), save() else { return }
        motion.transition(in: content)
        resetSwipeHistory()
        current = visibleNotes[table.selectedRow]
        persistedBody = current.body
        UserDefaults.standard.set(current.id, forKey: "lastNote")
        historyOpen = false
        historyView.isHidden = true
        editorScroll.isHidden = false
        historyButton.contentTintColor = .secondaryLabelColor
        loadEditor()
        panel.makeFirstResponder(editor)
    }

    @objc func togglePin() {
        pinned.toggle()
        UserDefaults.standard.set(pinned, forKey: "keepOnTop")
        updatePinButton()
    }

    private func updatePinButton() {
        pinButton.image = NSImage(systemSymbolName: pinned ? "pin.fill" : "pin", accessibilityDescription: "Keep on top")
        pinButton.contentTintColor = pinned ? .controlAccentColor : .secondaryLabelColor
        pinButton.toolTip = pinned ? "Unpin · dismiss when focus leaves" : "Keep on top"
        pinButton.setAccessibilityValue(pinned ? "On" : "Off")
    }
    @objc func toggleSource() { editor.sourceMode.toggle(); panel.makeFirstResponder(editor) }
    @objc func revealNotes() { NSWorkspace.shared.open(store.directory) }
    @objc func copyNote() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(current.body, forType: .string)
    }
    @objc func bold() { editor.wrapSelection("**"); panel.makeFirstResponder(editor) }
    @objc func italic() { editor.wrapSelection("*"); panel.makeFirstResponder(editor) }
    @objc func code() { editor.wrapSelection("`"); panel.makeFirstResponder(editor) }
    @objc func task() { editor.insertTask(); panel.makeFirstResponder(editor) }
    @objc func increaseFont() { changeFont(by: 1) }
    @objc func decreaseFont() { changeFont(by: -1) }
    private func changeFont(by amount: CGFloat) {
        editor.fontSize = min(24, max(12, editor.fontSize + amount))
        UserDefaults.standard.set(Double(editor.fontSize), forKey: "fontSize")
    }
    @objc func trashNote() {
        guard save(), persistedBody != nil else { return }
        do {
            try FileManager.default.trashItem(at: store.url(for: current), resultingItemURL: nil)
            resetSwipeHistory()
            current = Note()
            persistedBody = nil
            loadEditor()
        } catch { notice.stringValue = error.localizedDescription }
    }

    @objc func showFormat(_ sender: NSButton) {
        let menu = NSMenu()
        func item(_ title: String, _ action: Selector, _ key: String = "") {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
        }
        item("Bold", #selector(bold), "b")
        item("Italic", #selector(italic), "i")
        item("Inline code", #selector(code))
        item("Checklist", #selector(task))
        menu.addItem(.separator())
        item(editor.sourceMode ? "Show formatted note" : "Show Markdown source", #selector(toggleSource))
        item("Larger text", #selector(increaseFont))
        item("Smaller text", #selector(decreaseFont))
        menu.addItem(.separator())
        item("Copy Markdown", #selector(copyNote))
        item("Open notes folder", #selector(revealNotes))
        item("Move note to Trash", #selector(trashNote))
        menuOpen = true
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
        menuOpen = false
    }

    private func handleShortcut(_ key: String, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard modifiers.contains(.command) else { return false }
        let shift = modifiers.contains(.shift)
        switch key {
        case "n" where !shift: newNote()
        case "h" where !shift: toggleHistory()
        case "w": hide()
        case "s": _ = save()
        case "m" where shift: toggleSource()
        case "c" where shift: copyNote()
        case "b" where !historyOpen: bold()
        case "i" where !historyOpen: italic()
        case "l" where shift && !historyOpen: task()
        case "+", "=": increaseFont()
        case "-": decreaseFont()
        case "q": NSApp.terminate(nil)
        default: return false
        }
        return true
    }
}

private extension Double {
    var nonzero: Double? { self == 0 ? nil : self }
}
