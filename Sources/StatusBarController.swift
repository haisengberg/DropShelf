import AppKit
import Foundation

final class StatusBarDropView: NSView {
    var onOpenMenu: (() -> Void)?
    var onDragHoverChanged: ((Bool) -> Void)?
    var onFilesDropped: (([URL]) -> Bool)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        onOpenMenu?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onOpenMenu?()
    }

    // MARK: - NSDraggingDestination

    private func extractValidFileURLs(from sender: NSDraggingInfo) -> [URL] {
        let pb = sender.draggingPasteboard
        guard let objects = pb.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else {
            return []
        }
        return objects
            .filter { $0.isFileURL }
            .map { $0.standardizedFileURL }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = extractValidFileURLs(from: sender)
        guard !urls.isEmpty else {
            onDragHoverChanged?(false)
            return []
        }
        onDragHoverChanged?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragHoverChanged?(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onDragHoverChanged?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDragHoverChanged?(false)
        let urls = extractValidFileURLs(from: sender)
        guard !urls.isEmpty else { return false }
        return onFilesDropped?(urls) ?? false
    }
}

final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var dropView: StatusBarDropView?

    private var newShelfItem: NSMenuItem!
    private var showAllItem: NSMenuItem!
    private var closeAllItem: NSMenuItem!
    private var shakeToggleItem: NSMenuItem!
    private var autoCloseToggleItem: NSMenuItem!
    private var modeSystemDefaultItem: NSMenuItem!
    private var modeCopyOnlyItem: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!
    private var quitItem: NSMenuItem!

    override init() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        configureButton()
        configureMenu()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(syncMenuStates),
            name: Preferences.didChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }

        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        let img = NSImage(systemSymbolName: "tray.and.arrow.down.fill", accessibilityDescription: "DropShelf")?
            .withSymbolConfiguration(config)
        img?.isTemplate = true
        button.image = img
        button.imagePosition = .imageOnly
        button.toolTip = "DropShelf — 拖放文件到此图标，或点击打开菜单"

        let overlay = StatusBarDropView(frame: button.bounds)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.onOpenMenu = { [weak self] in
            self?.presentMenu()
        }
        overlay.onDragHoverChanged = { [weak button] hovering in
            button?.highlight(hovering)
        }
        overlay.onFilesDropped = { [weak self] urls in
            guard let self = self else { return false }
            self.handleDropOnStatusIcon(urls: urls)
            return true
        }
        button.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: button.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])
        self.dropView = overlay
    }

    private func configureMenu() {
        menu.delegate = self
        menu.autoenablesItems = false

        newShelfItem = NSMenuItem(
            title: "新建中转架 (⌥⇧D)",
            action: #selector(newShelfClicked),
            keyEquivalent: ""
        )
        newShelfItem.target = self

        showAllItem = NSMenuItem(
            title: "显示全部中转架",
            action: #selector(showAllClicked),
            keyEquivalent: ""
        )
        showAllItem.target = self

        closeAllItem = NSMenuItem(
            title: "关闭全部中转架",
            action: #selector(closeAllClicked),
            keyEquivalent: ""
        )
        closeAllItem.target = self

        shakeToggleItem = NSMenuItem(
            title: "摇晃鼠标呼出",
            action: #selector(toggleShakeClicked),
            keyEquivalent: ""
        )
        shakeToggleItem.target = self

        autoCloseToggleItem = NSMenuItem(
            title: "拖出后自动清空并关闭",
            action: #selector(toggleAutoCloseClicked),
            keyEquivalent: ""
        )
        autoCloseToggleItem.target = self

        modeSystemDefaultItem = NSMenuItem(
            title: "拖出模式：同盘移动 / 跨盘复制（默认）",
            action: #selector(selectSystemDefaultMode),
            keyEquivalent: ""
        )
        modeSystemDefaultItem.target = self

        modeCopyOnlyItem = NSMenuItem(
            title: "拖出模式：仅复制（保留原文件）",
            action: #selector(selectCopyOnlyMode),
            keyEquivalent: ""
        )
        modeCopyOnlyItem.target = self

        launchAtLoginItem = NSMenuItem(
            title: "开机自动启动",
            action: #selector(toggleLaunchAtLoginClicked),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self

        quitItem = NSMenuItem(
            title: "退出 DropShelf",
            action: #selector(quitClicked),
            keyEquivalent: "q"
        )
        quitItem.target = self

        menu.addItem(newShelfItem)
        menu.addItem(showAllItem)
        menu.addItem(closeAllItem)
        menu.addItem(.separator())
        menu.addItem(shakeToggleItem)
        menu.addItem(autoCloseToggleItem)
        menu.addItem(modeSystemDefaultItem)
        menu.addItem(modeCopyOnlyItem)
        menu.addItem(.separator())
        menu.addItem(launchAtLoginItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        syncMenuStates()
    }

    private func presentMenu() {
        syncMenuStates()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        syncMenuStates()
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
    }

    @objc private func syncMenuStates() {
        let count = ShelfManager.shared.shelfCount
        let hasShelves = count > 0

        showAllItem.title = hasShelves ? "显示全部中转架 (\(count))" : "显示全部中转架"
        showAllItem.isEnabled = hasShelves

        closeAllItem.title = hasShelves ? "关闭全部中转架 (\(count))" : "关闭全部中转架"
        closeAllItem.isEnabled = hasShelves

        shakeToggleItem.state = Preferences.shared.shakeToOpenEnabled ? .on : .off
        autoCloseToggleItem.state = Preferences.shared.autoClearAndCloseOnDragOut ? .on : .off

        let mode = Preferences.shared.dragOutMode
        modeSystemDefaultItem.state = (mode == .systemDefault) ? .on : .off
        modeCopyOnlyItem.state = (mode == .copyOnly) ? .on : .off

        launchAtLoginItem.state = LaunchAtLoginManager.shared.isEnabled ? .on : .off
    }

    // MARK: - Menu Actions

    @objc private func newShelfClicked() {
        let anchor = statusBarAnchorPoint()
        ShelfManager.shared.createShelf(
            near: anchor,
            anchorBelowPoint: true,
            initialURLs: [],
            autoDismissIfEmpty: false,
            makeKey: true
        )
    }

    @objc private func showAllClicked() {
        ShelfManager.shared.showAllShelves()
    }

    @objc private func closeAllClicked() {
        ShelfManager.shared.closeAllShelves()
    }

    @objc private func toggleShakeClicked() {
        Preferences.shared.shakeToOpenEnabled.toggle()
    }

    @objc private func toggleAutoCloseClicked() {
        Preferences.shared.autoClearAndCloseOnDragOut.toggle()
    }

    @objc private func selectSystemDefaultMode() {
        Preferences.shared.dragOutMode = .systemDefault
    }

    @objc private func selectCopyOnlyMode() {
        Preferences.shared.dragOutMode = .copyOnly
    }

    @objc private func toggleLaunchAtLoginClicked() {
        let targetState = !LaunchAtLoginManager.shared.isEnabled
        do {
            try LaunchAtLoginManager.shared.setEnabled(targetState)
            syncMenuStates()
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "无法更新开机自动启动设置"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func quitClicked() {
        NSApp.terminate(nil)
    }

    // MARK: - Drop Handling

    private func statusBarAnchorPoint() -> NSPoint {
        if let buttonFrame = statusItem.button?.window?.frame {
            return NSPoint(x: buttonFrame.midX, y: buttonFrame.minY)
        }
        return NSEvent.mouseLocation
    }

    private func handleDropOnStatusIcon(urls: [URL]) {
        let anchor = statusBarAnchorPoint()
        ShelfManager.shared.createShelf(
            near: anchor,
            anchorBelowPoint: true,
            initialURLs: urls,
            autoDismissIfEmpty: false,
            makeKey: false
        )
    }
}
