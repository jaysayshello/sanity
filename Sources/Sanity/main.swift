import AppKit
import SwiftUI
import Combine

extension Notification.Name {
    static let centerWidget = Notification.Name("CenterWidget")
    static let saveWidgetLocation = Notification.Name("SaveWidgetLocation")
    static let openEditor = Notification.Name("OpenEditor")
    static let openNewEditor = Notification.Name("OpenNewEditor")
}

/// Draws the connector between a card and the centered editor window as an
/// orthogonal (right-angle) elbow, with an arrowhead at each end whose tip just
/// touches the card (`from`) and the editor (`to`).
final class LineOverlayView: NSView {
    /// Bottom-center of the source card (arrow points up into it).
    var from: NSPoint = .zero
    /// Top-center of the editor (arrow points down into it).
    var to: NSPoint = .zero

    private let arrowLength: CGFloat = 11
    private let arrowHalfWidth: CGFloat = 7

    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.controlAccentColor
        accent.withAlphaComponent(0.95).setStroke()
        accent.withAlphaComponent(0.95).setFill()

        // Right-angle route: down from the card, across, then down to the editor.
        // Start/end just inside the arrowheads so the tips sit at the targets.
        let start = NSPoint(x: from.x, y: from.y - arrowLength)
        let end = NSPoint(x: to.x, y: to.y + arrowLength)
        let midY = (start.y + end.y) / 2

        let path = NSBezierPath()
        path.lineWidth = 3
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: start)
        path.line(to: NSPoint(x: start.x, y: midY))
        path.line(to: NSPoint(x: end.x, y: midY))
        path.line(to: end)
        path.stroke()

        drawArrow(tip: from, pointingUp: true)   // into the card
        drawArrow(tip: to, pointingUp: false)    // into the editor
    }

    private func drawArrow(tip: NSPoint, pointingUp: Bool) {
        let baseY = tip.y + (pointingUp ? -arrowLength : arrowLength)
        let tri = NSBezierPath()
        tri.move(to: tip)
        tri.line(to: NSPoint(x: tip.x - arrowHalfWidth, y: baseY))
        tri.line(to: NSPoint(x: tip.x + arrowHalfWidth, y: baseY))
        tri.close()
        tri.fill()
    }
}

/// A borderless, non-activating panel that floats above normal windows,
/// shows on every Space, and sits at the top-left of the screen.
final class WidgetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that responds to the first click without needing the panel
/// to be activated first, and makes its window key on click so SwiftUI
/// buttons receive the event.
final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        super.mouseDown(with: event)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = TaskStore()
    private var panel: WidgetPanel!
    private var hosting: ClickThroughHostingView<AnyView>!
    private var cancellables: Set<AnyCancellable> = []

    private let topMargin: CGFloat = 8
    private let leftMargin: CGFloat = 16
    /// The saved top-left corner of the widget, so drags persist and resizing
    /// keeps the top edge anchored instead of jumping.
    private var anchorTopLeft: NSPoint?
    private var editorPanel: NSPanel?
    private var lineOverlay: NSPanel?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let content = WidgetView(store: store)
        hosting = ClickThroughHostingView(rootView: AnyView(content))

        panel = WidgetPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 160),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Chromeless: hide the title bar and its buttons but keep a real
        // titled window, which (unlike pure .borderless) can become key so
        // SwiftUI buttons work.
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = !store.locked
        panel.isMovable = !store.locked
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        // Don't hide when the app deactivates, so it stays put across Spaces.
        panel.hidesOnDeactivate = false
        panel.contentView = hosting
        panel.delegate = self

        setupStatusItem()
        setupMainMenu()

        anchorTopLeft = savedTopLeft()
        resizeToFit()
        panel.orderFrontRegardless()
        // Collection behavior only reliably "sticks" once the window is
        // on-screen, so set it after ordering front. Mirror the menu bar:
        // canJoinAllSpaces keeps it resident (not sliding in per Space).
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]

        // Re-fit whenever the content size can change: tasks added/removed,
        // the size slider moved, or done tasks hidden/shown.
        let relayout: (Any) -> Void = { [weak self] _ in self?.resizeToFit() }
        store.$tasks.receive(on: RunLoop.main).sink(receiveValue: relayout).store(in: &cancellables)
        store.$scale.receive(on: RunLoop.main).sink(receiveValue: relayout).store(in: &cancellables)
        store.$hideDone.receive(on: RunLoop.main).sink(receiveValue: relayout).store(in: &cancellables)
        store.$locked.receive(on: RunLoop.main).sink { [weak self] locked in
            self?.panel.isMovableByWindowBackground = !locked
            self?.panel.isMovable = !locked
        }.store(in: &cancellables)

        NotificationCenter.default.addObserver(
            forName: .centerWidget, object: nil, queue: .main
        ) { [weak self] _ in self?.centerAtTop() }
        NotificationCenter.default.addObserver(
            forName: .saveWidgetLocation, object: nil, queue: .main
        ) { [weak self] _ in self?.persistLocation() }
        NotificationCenter.default.addObserver(
            forName: .openEditor, object: nil, queue: .main
        ) { [weak self] note in
            self?.openEditor(taskID: (note.object as? String).flatMap(UUID.init))
        }
        NotificationCenter.default.addObserver(
            forName: .openNewEditor, object: nil, queue: .main
        ) { [weak self] _ in self?.openEditor(taskID: nil) }

        // Re-assert the panel when the active Space changes (belt-and-suspenders;
        // the window is already on every Space via canJoinAllSpaces).
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.panel.orderFrontRegardless() }

        // On wake or a display-geometry change, the window server can nudge the
        // panel off its anchor (into the middle of the screen). Re-apply the
        // saved top position once things settle.
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.repositionAfterWake()
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.repositionAfterWake() }
    }

    private func repositionAfterWake() {
        // Screen geometry can keep settling for a moment after wake, so
        // re-apply a couple of times.
        for delay in [0.3, 1.0, 2.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.resizeToFit()
                self?.panel.orderFrontRegardless()
            }
        }
    }

    private func persistLocation() {
        let frame = panel.frame
        UserDefaults.standard.set(Double(frame.minX), forKey: "winX")
        UserDefaults.standard.set(Double(frame.maxY), forKey: "winTopY")
    }

    // MARK: - Centered editor + connector line

    /// Bottom-center of the card at the given index, in screen coordinates.
    /// Matches the deterministic layout in WidgetView.
    private func cardBottomCenter(index: Int) -> NSPoint {
        let scale = CGFloat(store.scale)
        let cardSize = 116 * scale
        let spacing = 14 * scale
        let f = panel.frame
        let x = f.minX + spacing + CGFloat(index) * (cardSize + spacing) + cardSize / 2
        let y = f.maxY - 12 - cardSize
        return NSPoint(x: x, y: y)
    }

    private func openEditor(taskID: UUID?) {
        closeEditor()
        guard let screen = NSScreen.main else { return }

        let visible = store.hideDone ? store.tasks.filter { !$0.done } : store.tasks
        let index: Int
        if let taskID, let i = visible.firstIndex(where: { $0.id == taskID }) {
            index = i
        } else {
            index = visible.count // the add card
        }
        let source = cardBottomCenter(index: index)

        // Centered editor window.
        let size = NSSize(width: 560, height: 460)
        let vf = screen.visibleFrame
        let origin = NSPoint(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2)
        let editor = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        editor.titleVisibility = .hidden
        editor.titlebarAppearsTransparent = true
        editor.standardWindowButton(.closeButton)?.isHidden = true
        editor.standardWindowButton(.miniaturizeButton)?.isHidden = true
        editor.standardWindowButton(.zoomButton)?.isHidden = true
        editor.isOpaque = false
        editor.backgroundColor = .clear
        editor.hasShadow = false
        editor.isMovableByWindowBackground = true
        editor.level = NSWindow.Level(rawValue: 9)
        editor.collectionBehavior = [.canJoinAllSpaces, .stationary]
        editor.delegate = self
        editor.contentView = ClickThroughHostingView(rootView: AnyView(
            EditorView(store: store, taskID: taskID, onClose: { [weak self] in self?.closeEditor() })
        ))
        editorPanel = editor

        // Full-screen click-through overlay for the connector line.
        let overlay = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = false
        overlay.ignoresMouseEvents = true
        overlay.level = NSWindow.Level(rawValue: 8)
        overlay.collectionBehavior = [.canJoinAllSpaces, .stationary]
        let lineView = LineOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        let o = screen.frame.origin
        lineView.from = NSPoint(x: source.x - o.x, y: source.y - o.y)
        lineView.to = NSPoint(x: origin.x + size.width / 2 - o.x, y: origin.y + size.height - o.y)
        overlay.contentView = lineView
        lineOverlay = overlay

        overlay.orderFrontRegardless()
        editor.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Menu bar status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Sanity")
                ?? NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "Sanity")
            if let image {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "\u{2611}"
            }
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "New Task", action: #selector(menuNewTask), keyEquivalent: "n").target = self
        menu.addItem(withTitle: "Center on Top", action: #selector(menuCenter), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Open tasks.md", action: #selector(menuOpenFile), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Sanity", action: #selector(menuQuit), keyEquivalent: "q").target = self
        item.menu = menu
        statusItem = item
    }

    /// A main menu is required for standard edit shortcuts (Cmd-C/V/X/A/Z) to
    /// reach text fields; without it an accessory app can't route them.
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Sanity", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func menuNewTask() { openEditor(taskID: nil) }
    @objc private func menuCenter() { centerAtTop() }
    @objc private func menuOpenFile() { store.openInEditor() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    private func closeEditor() {
        // Clear references first so orderOut's resignKey doesn't re-enter.
        let editor = editorPanel
        let overlay = lineOverlay
        editorPanel = nil
        lineOverlay = nil
        editor?.orderOut(nil)
        overlay?.orderOut(nil)
    }

    /// Center the widget horizontally, pinned to the top of the screen.
    private func centerAtTop() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = contentSize()
        let x = visible.minX + (visible.width - size.width) / 2
        let topY = visible.maxY - topMargin
        anchorTopLeft = NSPoint(x: x, y: topY)
        resizeToFit()
        persistLocation()
    }

    /// Deterministic content size, matching the SwiftUI layout in WidgetView.
    /// Computing it directly (rather than reading the hosting view's
    /// fittingSize mid-relayout) avoids the resize race that caused flicker.
    private func contentSize() -> NSSize {
        let scale = CGFloat(store.scale)
        let cardSize = 116 * scale
        let spacing = 14 * scale
        let toolbarWidth = 22 * scale
        let verticalPadding: CGFloat = 12

        let visibleCount = store.hideDone ? store.tasks.filter { !$0.done }.count : store.tasks.count
        let items = visibleCount + 1 /* add card */ + 1 /* toolbar */
        let childWidths = CGFloat(visibleCount + 1) * cardSize + toolbarWidth
        let width = 2 * spacing + childWidths + spacing * CGFloat(items - 1)
        let height = cardSize + 2 * verticalPadding
        return NSSize(width: max(width, 140), height: max(height, 140))
    }

    private func resizeToFit() {
        guard let screen = NSScreen.main else { return }
        let size = contentSize()

        let visible = screen.visibleFrame
        let topLeft = anchorTopLeft ?? NSPoint(
            x: visible.minX + leftMargin,
            y: visible.maxY - topMargin
        )
        anchorTopLeft = topLeft
        // NSWindow origin is bottom-left; keep the top edge fixed.
        let frame = NSRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height)
        // Skip no-op updates so slider drags don't trigger redundant redraws.
        if frame.equalTo(panel.frame) { return }
        panel.setFrame(frame, display: true, animate: false)
    }

    // MARK: - Position persistence

    func windowDidMove(_ notification: Notification) {
        guard (notification.object as? NSWindow) === panel else { return }
        let frame = panel.frame
        anchorTopLeft = NSPoint(x: frame.minX, y: frame.maxY)
        persistLocation()
    }

    func windowDidResignKey(_ notification: Notification) {
        // Clicking away from the editor should dismiss it and its connector line.
        if (notification.object as? NSWindow) === editorPanel {
            closeEditor()
        }
    }

    private func savedTopLeft() -> NSPoint? {
        let d = UserDefaults.standard
        guard d.object(forKey: "winX") != nil, d.object(forKey: "winTopY") != nil else { return nil }
        return NSPoint(x: d.double(forKey: "winX"), y: d.double(forKey: "winTopY"))
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
