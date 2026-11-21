import AppKit
import Quartz

final class ShelfPanel: NSPanel {
    let shelfID: UUID
    weak var shelfController: ShelfViewController?

    init(shelfID: UUID = UUID(), contentRect: NSRect) {
        self.shelfID = shelfID
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true

        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .utilityWindow
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let controller = shelfController, controller.handleKeyEvent(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if let controller = shelfController, controller.handleKeyEvent(event) {
            return
        }
        super.keyDown(with: event)
    }

    // MARK: - Quick Look Panel Control

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        return shelfController?.hasItems ?? false
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        guard let controller = shelfController else { return }
        panel.dataSource = controller
        panel.delegate = controller
        controller.configurePreviewPanel(panel)
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
}
