import AppKit
import Foundation

final class ShelfManager {
    static let shared = ShelfManager()

    private(set) var shelves: [ShelfPanel] = []
    private var activeInternalDragShelfIDs: Set<UUID> = []

    var hasOpenShelves: Bool { !shelves.isEmpty }
    var shelfCount: Int { shelves.count }
    var isAnyInternalDragActive: Bool { !activeInternalDragShelfIDs.isEmpty }

    private init() {}

    func markInternalDragStarted(shelfID: UUID) {
        activeInternalDragShelfIDs.insert(shelfID)
    }

    func markInternalDragEnded(shelfID: UUID) {
        activeInternalDragShelfIDs.remove(shelfID)
    }

    func isInternalDragActive(for shelfID: UUID) -> Bool {
        activeInternalDragShelfIDs.contains(shelfID)
    }

    @discardableResult
    func createShelf(
        near anchorPoint: NSPoint? = nil,
        anchorBelowPoint: Bool = false,
        initialURLs: [URL] = [],
        autoDismissIfEmpty: Bool = false,
        makeKey: Bool = false
    ) -> ShelfPanel {
        let shelfID = UUID()
        let initialSize = ShelfViewController.preferredSize(forItemCount: initialURLs.count)
        let targetPoint = anchorPoint ?? NSEvent.mouseLocation
        let origin = computeOrigin(
            for: initialSize,
            near: targetPoint,
            anchorBelowPoint: anchorBelowPoint
        )

        let panel = ShelfPanel(
            shelfID: shelfID,
            contentRect: NSRect(origin: origin, size: initialSize)
        )
        let controller = ShelfViewController(
            shelfID: shelfID,
            autoDismissIfEmpty: autoDismissIfEmpty && initialURLs.isEmpty
        )
        controller.onRequestClose = { [weak self, weak panel] in
            guard let self = self, let panel = panel else { return }
            self.closeShelf(panel)
        }

        panel.shelfController = controller
        panel.contentViewController = controller

        if !initialURLs.isEmpty {
            controller.addFileURLs(initialURLs, animatedResize: false)
        }

        shelves.append(panel)

        panel.alphaValue = 0
        if makeKey {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        } completionHandler: {
            panel.invalidateShadow()
        }

        return panel
    }

    func showAllShelves() {
        for panel in shelves {
            panel.orderFrontRegardless()
        }
    }

    func closeAllShelves() {
        let current = shelves
        for panel in current {
            closeShelf(panel)
        }
    }

    func closeShelf(_ panel: ShelfPanel) {
        guard let idx = shelves.firstIndex(where: { $0 === panel }) else {
            panel.orderOut(nil)
            return
        }
        shelves.remove(at: idx)
        activeInternalDragShelfIDs.remove(panel.shelfID)
        panel.shelfController?.prepareForClose()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            panel.close()
        })
    }

    // MARK: - Positioning

    private func computeOrigin(
        for size: NSSize,
        near point: NSPoint,
        anchorBelowPoint: Bool
    ) -> NSPoint {
        let screen = screenContaining(point: point) ?? NSScreen.main ?? NSScreen.screens.first
        let visible = (screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900))
            .insetBy(dx: 12, dy: 12)

        var origin: NSPoint
        if anchorBelowPoint {
            // Anchored neatly beneath the menu bar icon
            origin = NSPoint(
                x: point.x - size.width / 2,
                y: point.y - size.height - 8
            )
        } else {
            // Centered slightly offset from cursor so dragged files can be dropped immediately
            origin = NSPoint(
                x: point.x - size.width / 2,
                y: point.y - size.height / 2
            )
        }

        origin = clamp(origin: origin, size: size, within: visible)

        // Cascade slightly if overlapping an existing shelf at nearly the same top-left position
        for _ in 0..<8 {
            let overlaps = shelves.contains { existing in
                let dx = abs(existing.frame.minX - origin.x)
                let dy = abs(existing.frame.maxY - (origin.y + size.height))
                return dx < 20 && dy < 20
            }
            if !overlaps { break }
            origin.x += 26
            origin.y -= 26
            origin = clamp(origin: origin, size: size, within: visible)
        }

        return origin
    }

    private func clamp(origin: NSPoint, size: NSSize, within visible: NSRect) -> NSPoint {
        let minX = visible.minX
        let maxX = max(visible.minX, visible.maxX - size.width)
        let minY = visible.minY
        let maxY = max(visible.minY, visible.maxY - size.height)

        return NSPoint(
            x: min(max(origin.x, minX), maxX),
            y: min(max(origin.y, minY), maxY)
        )
    }

    private func screenContaining(point: NSPoint) -> NSScreen? {
        for screen in NSScreen.screens {
            if screen.frame.contains(point) {
                return screen
            }
        }
        return nil
    }
}
