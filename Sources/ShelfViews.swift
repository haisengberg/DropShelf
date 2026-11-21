import AppKit
import Foundation

// MARK: - Protocol for Same-Shelf Drag Identification

protocol ShelfDraggingOrigin: AnyObject {
    var shelfID: UUID { get }
}

// MARK: - Flipped Helpers

final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Compact Hover Icon Button

final class IconActionButton: NSButton {
    private var trackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet { updateAppearance() }
    }

    var activeTintColor: NSColor = .labelColor {
        didSet { updateAppearance() }
    }
    var inactiveTintColor: NSColor = .secondaryLabelColor {
        didSet { updateAppearance() }
    }
    var isActiveState: Bool = false {
        didSet { updateAppearance() }
    }
    var hoverBackgroundColor: NSColor = NSColor.labelColor.withAlphaComponent(0.09)

    override var mouseDownCanMoveWindow: Bool { false }

    init(symbolName: String, pointSize: CGFloat = 12, weight: NSFont.Weight = .medium, tooltip: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        isBordered = false
        bezelStyle = .regularSquare
        title = ""
        imagePosition = .imageOnly
        toolTip = tooltip
        wantsLayer = true
        layer?.cornerRadius = 6

        setSymbol(symbolName, pointSize: pointSize, weight: weight)
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSymbol(_ name: String, pointSize: CGFloat = 12, weight: NSFont.Weight = .medium) {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        let img = NSImage(systemSymbolName: name, accessibilityDescription: toolTip)?.withSymbolConfiguration(config)
        img?.isTemplate = true
        image = img
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        contentTintColor = isActiveState ? activeTintColor : (isHovered ? .labelColor : inactiveTintColor)
        layer?.backgroundColor = isHovered ? hoverBackgroundColor.cgColor : NSColor.clear.cgColor
    }
}

// MARK: - Root Frosted Drop Container

final class ShelfDropContainerView: NSVisualEffectView {
    let shelfID: UUID

    var onValidateDrop: (([URL]) -> Bool)?
    var onAcceptDrop: (([URL]) -> Bool)?
    var onDragHoverChanged: ((Bool) -> Void)?
    var onMouseHoverChanged: ((Bool) -> Void)?

    private var hoverTrackingArea: NSTrackingArea?
    private let highlightOverlay = NSView()
    private var isDragHighlighted = false

    init(shelfID: UUID) {
        self.shelfID = shelfID
        super.init(frame: .zero)

        material = .hudWindow
        blendingMode = .behindWindow
        state = .active

        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
        layer?.borderWidth = 1.0

        highlightOverlay.wantsLayer = true
        highlightOverlay.layer?.cornerRadius = 14
        highlightOverlay.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
        highlightOverlay.alphaValue = 0
        highlightOverlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(highlightOverlay)
        NSLayoutConstraint.activate([
            highlightOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            highlightOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            highlightOverlay.topAnchor.constraint(equalTo: topAnchor),
            highlightOverlay.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        registerForDraggedTypes([.fileURL])
        updateBorderColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBorderColors()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = hoverTrackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onMouseHoverChanged?(false)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        super.mouseDown(with: event)
    }

    private func setDragHighlighted(_ highlighted: Bool) {
        guard isDragHighlighted != highlighted else { return }
        isDragHighlighted = highlighted
        onDragHoverChanged?(highlighted)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            highlightOverlay.animator().alphaValue = highlighted ? 1.0 : 0.0
        }
        updateBorderColors()
    }

    private func updateBorderColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if isDragHighlighted {
                layer?.borderWidth = 2.0
                layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.9).cgColor
                highlightOverlay.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.09).cgColor
            } else {
                layer?.borderWidth = 1.0
                layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
            }
        }
    }

    // MARK: - NSDraggingDestination

    private func isSameShelfDrag(_ sender: NSDraggingInfo) -> Bool {
        if let origin = sender.draggingSource as? ShelfDraggingOrigin, origin.shelfID == shelfID {
            return true
        }
        if ShelfManager.shared.isInternalDragActive(for: shelfID) {
            return true
        }
        return false
    }

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
        guard !isSameShelfDrag(sender) else {
            setDragHighlighted(false)
            return []
        }
        let urls = extractValidFileURLs(from: sender)
        guard !urls.isEmpty, onValidateDrop?(urls) ?? true else {
            setDragHighlighted(false)
            return []
        }
        setDragHighlighted(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !isSameShelfDrag(sender) else {
            return []
        }
        return isDragHighlighted ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setDragHighlighted(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        setDragHighlighted(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        setDragHighlighted(false)
        guard !isSameShelfDrag(sender) else {
            return false
        }
        let urls = extractValidFileURLs(from: sender)
        guard !urls.isEmpty else { return false }
        return onAcceptDrop?(urls) ?? false
    }
}

// MARK: - Empty State Dashed Drop Zone

final class DashedDropZoneView: NSView {
    private let dashedBorderLayer = CAShapeLayer()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "拖入文件或文件夹到此")
    private let subtitleLabel = NSTextField(labelWithString: "支持 ⌘V 粘贴 · ⌥⇧D 随时呼出")

    var isHighlighted: Bool = false {
        didSet { updateStyling() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 11

        dashedBorderLayer.fillColor = NSColor.clear.cgColor
        dashedBorderLayer.lineWidth = 1.4
        dashedBorderLayer.lineDashPattern = [5, 4]
        layer?.addSublayer(dashedBorderLayer)

        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 28, weight: .light)
        let img = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: "拖入文件")?
            .withSymbolConfiguration(symbolConfig)
        img?.isTemplate = true
        iconView.image = img
        iconView.contentTintColor = .secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = .tertiaryLabelColor
        subtitleLabel.alignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [iconView, titleLabel, subtitleLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.setCustomSpacing(10, after: iconView)
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12)
        ])

        updateStyling()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let insetRect = bounds.insetBy(dx: 1, dy: 1)
        dashedBorderLayer.frame = bounds
        dashedBorderLayer.path = CGPath(
            roundedRect: insetRect,
            cornerWidth: 11,
            cornerHeight: 11,
            transform: nil
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateStyling()
    }

    private func updateStyling() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if isHighlighted {
                dashedBorderLayer.strokeColor = NSColor.controlAccentColor.cgColor
                layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
                iconView.contentTintColor = .controlAccentColor
                titleLabel.stringValue = "松开鼠标添加到中转架"
            } else {
                dashedBorderLayer.strokeColor = NSColor.tertiaryLabelColor.withAlphaComponent(0.6).cgColor
                layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.03).cgColor
                iconView.contentTintColor = .secondaryLabelColor
                titleLabel.stringValue = "拖入文件或文件夹到此"
            }
        }
    }
}

// MARK: - Drag-All Stack Card

final class DragAllCardView: NSView, NSDraggingSource, ShelfDraggingOrigin {
    let shelfID: UUID

    var itemsProvider: (() -> [ShelfItem])?
    var onDragOperationEnded: (([URL], NSDragOperation) -> Void)?

    private let stackContainer = NSView()
    private let iconImageViews: [NSImageView] = (0..<3).map { _ in NSImageView() }
    private let summaryLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "按住拖出全部")
    private let gripIconView = NSImageView()

    private var trackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet { updateStyling() }
    }
    private var mouseDownEvent: NSEvent?
    private var draggingURLs: [URL] = []

    override var mouseDownCanMoveWindow: Bool { false }

    init(shelfID: UUID) {
        self.shelfID = shelfID
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1.0

        stackContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackContainer)

        // Setup 3 stacked icon slots (index 0 = back-left, 1 = back-right, 2 = front-center)
        for (idx, iv) in iconImageViews.enumerated() {
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.wantsLayer = true
            iv.layer?.cornerRadius = 6
            iv.layer?.masksToBounds = true
            iv.layer?.borderWidth = 0.5
            iv.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
            iv.isHidden = true
            stackContainer.addSubview(iv)
            iv.frame = iconFrame(forSlot: idx)
        }

        summaryLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        summaryLabel.textColor = .labelColor
        summaryLabel.lineBreakMode = .byTruncatingTail
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false

        hintLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.lineBreakMode = .byTruncatingTail
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView(views: [summaryLabel, hintLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textStack)

        let gripConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let gripImg = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: "拖拽手柄")?
            .withSymbolConfiguration(gripConfig)
        gripImg?.isTemplate = true
        gripIconView.image = gripImg
        gripIconView.contentTintColor = .tertiaryLabelColor
        gripIconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(gripIconView)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 58),

            stackContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stackContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            stackContainer.widthAnchor.constraint(equalToConstant: 48),
            stackContainer.heightAnchor.constraint(equalToConstant: 42),

            textStack.leadingAnchor.constraint(equalTo: stackContainer.trailingAnchor, constant: 10),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: gripIconView.leadingAnchor, constant: -8),

            gripIconView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            gripIconView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateStyling()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func iconFrame(forSlot idx: Int) -> NSRect {
        switch idx {
        case 0: return NSRect(x: 2, y: 6, width: 28, height: 28)
        case 1: return NSRect(x: 18, y: 6, width: 28, height: 28)
        default: return NSRect(x: 10, y: 4, width: 32, height: 32)
        }
    }

    func configure(with items: [ShelfItem]) {
        let count = items.count
        let knownBytes = items.compactMap { $0.fileSize }.reduce(0, +)
        let stillComputing = items.contains { $0.isComputingSize }

        let sizeText: String
        if stillComputing && knownBytes == 0 {
            sizeText = "计算大小中…"
        } else if stillComputing {
            sizeText = "\(ShelfItem.formatByteCount(knownBytes))+"
        } else {
            sizeText = ShelfItem.formatByteCount(knownBytes)
        }

        summaryLabel.stringValue = "\(count) 个项目 · \(sizeText)"
        hintLabel.stringValue = count == 1 ? "按住拖出此项目" : "按住拖出全部 \(count) 个项目"

        for iv in iconImageViews {
            iv.isHidden = true
            iv.frameCenterRotation = 0
        }

        if count == 1 {
            let front = iconImageViews[2]
            front.image = items[0].displayImage
            front.frame = NSRect(x: 8, y: 5, width: 32, height: 32)
            front.isHidden = false
        } else if count == 2 {
            let left = iconImageViews[0]
            left.image = items[1].displayImage
            left.frame = NSRect(x: 4, y: 6, width: 28, height: 28)
            left.frameCenterRotation = 8
            left.isHidden = false

            let front = iconImageViews[2]
            front.image = items[0].displayImage
            front.frame = NSRect(x: 14, y: 4, width: 30, height: 30)
            front.frameCenterRotation = -4
            front.isHidden = false
        } else if count >= 3 {
            let backLeft = iconImageViews[0]
            backLeft.image = items[2].displayImage
            backLeft.frame = NSRect(x: 2, y: 6, width: 26, height: 26)
            backLeft.frameCenterRotation = 10
            backLeft.isHidden = false

            let backRight = iconImageViews[1]
            backRight.image = items[1].displayImage
            backRight.frame = NSRect(x: 20, y: 6, width: 26, height: 26)
            backRight.frameCenterRotation = -10
            backRight.isHidden = false

            let front = iconImageViews[2]
            front.image = items[0].displayImage
            front.frame = NSRect(x: 10, y: 4, width: 30, height: 30)
            front.frameCenterRotation = 0
            front.isHidden = false
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        NSCursor.openHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        NSCursor.arrow.set()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateStyling()
    }

    private func updateStyling() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if isHovered {
                layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor
                layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.45).cgColor
                gripIconView.contentTintColor = .controlAccentColor
            } else {
                layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
                layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
                gripIconView.contentTintColor = .tertiaryLabelColor
            }
        }
    }

    // MARK: - Mouse & Drag Out

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        NSCursor.closedHand.set()
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
        if isHovered {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let downEvent = mouseDownEvent else { return }
        let dx = event.locationInWindow.x - downEvent.locationInWindow.x
        let dy = event.locationInWindow.y - downEvent.locationInWindow.y
        guard hypot(dx, dy) >= 3 else { return }

        mouseDownEvent = nil
        startDraggingAll(with: downEvent)
    }

    private func startDraggingAll(with event: NSEvent) {
        let items = itemsProvider?() ?? []
        guard !items.isEmpty else { return }

        draggingURLs = items.map { $0.url }
        let dragLocation = convert(event.locationInWindow, from: nil)

        var draggingItems: [NSDraggingItem] = []
        for (index, item) in items.enumerated() {
            let dragItem = NSDraggingItem(pasteboardWriter: item.url as NSURL)
            let iconSize: CGFloat = 44
            let offset = CGFloat(min(index, 4)) * 3.0
            let frame = NSRect(
                x: dragLocation.x - iconSize / 2 + offset,
                y: dragLocation.y - iconSize / 2 - offset,
                width: iconSize,
                height: iconSize
            )
            let dragImage = Self.makeDragImage(from: item.displayImage, size: NSSize(width: iconSize, height: iconSize))
            dragItem.setDraggingFrame(frame, contents: dragImage)
            draggingItems.append(dragItem)
        }

        ShelfManager.shared.markInternalDragStarted(shelfID: shelfID)
        let session = beginDraggingSession(with: draggingItems, event: event, source: self)
        session.draggingFormation = .pile
    }

    static func makeDragImage(from image: NSImage, size: NSSize) -> NSImage {
        let copy = NSImage(size: size)
        copy.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .sourceOver,
            fraction: 0.95
        )
        copy.unlockFocus()
        return copy
    }

    // MARK: - NSDraggingSource

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        switch Preferences.shared.dragOutMode {
        case .copyOnly:
            return .copy
        case .systemDefault:
            return [.copy, .move, .link]
        }
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        ShelfManager.shared.markInternalDragEnded(shelfID: shelfID)
        let urls = draggingURLs
        draggingURLs = []
        NSCursor.arrow.set()
        onDragOperationEnded?(urls, operation)
    }
}

// MARK: - Individual File Row View

final class ShelfItemRowView: NSView, NSDraggingSource, ShelfDraggingOrigin {
    let shelfID: UUID
    let item: ShelfItem

    var onSelect: (() -> Void)?
    var onQuickLook: (() -> Void)?
    var onRevealInFinder: (() -> Void)?
    var onCopyFile: (() -> Void)?
    var onCopyPath: (() -> Void)?
    var onRemove: (() -> Void)?
    var onDragOperationEnded: (([URL], NSDragOperation) -> Void)?

    var isSelected: Bool = false {
        didSet { updateStyling() }
    }

    private let thumbnailView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let sizeLabel = NSTextField(labelWithString: "")
    private let actionsStack = NSStackView()
    private let previewButton: IconActionButton
    private let revealButton: IconActionButton
    private let removeButton: IconActionButton

    private var trackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet { updateStyling() }
    }
    private var mouseDownEvent: NSEvent?

    override var mouseDownCanMoveWindow: Bool { false }

    init(shelfID: UUID, item: ShelfItem) {
        self.shelfID = shelfID
        self.item = item

        self.previewButton = IconActionButton(symbolName: "eye", pointSize: 11.5, tooltip: "快速预览 (空格)")
        self.revealButton = IconActionButton(symbolName: "folder", pointSize: 11.5, tooltip: "在访达中显示")
        self.removeButton = IconActionButton(symbolName: "xmark.circle.fill", pointSize: 12, tooltip: "从列表移除")

        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8

        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = 5
        thumbnailView.layer?.masksToBounds = true
        thumbnailView.image = item.displayImage
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(thumbnailView)

        nameLabel.stringValue = item.displayName
        nameLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.maximumNumberOfLines = 1
        nameLabel.toolTip = item.url.path
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        sizeLabel.stringValue = item.formattedSize
        sizeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        sizeLabel.textColor = .secondaryLabelColor
        sizeLabel.lineBreakMode = .byTruncatingTail
        sizeLabel.maximumNumberOfLines = 1

        let textStack = NSStackView(views: [nameLabel, sizeLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1
        textStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textStack)

        previewButton.target = self
        previewButton.action = #selector(previewClicked)
        revealButton.target = self
        revealButton.action = #selector(revealClicked)
        removeButton.target = self
        removeButton.action = #selector(removeClicked)

        for btn in [previewButton, revealButton, removeButton] {
            btn.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                btn.widthAnchor.constraint(equalToConstant: 22),
                btn.heightAnchor.constraint(equalToConstant: 22)
            ])
        }

        actionsStack.orientation = .horizontal
        actionsStack.spacing = 2
        actionsStack.addArrangedSubview(previewButton)
        actionsStack.addArrangedSubview(revealButton)
        actionsStack.addArrangedSubview(removeButton)
        actionsStack.isHidden = true
        actionsStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(actionsStack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 44),

            thumbnailView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            thumbnailView.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 30),
            thumbnailView.heightAnchor.constraint(equalToConstant: 30),

            textStack.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 9),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: actionsStack.leadingAnchor, constant: -6),

            actionsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            actionsStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateStyling()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refreshVisuals() {
        thumbnailView.image = item.displayImage
        sizeLabel.stringValue = item.formattedSize
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateStyling()
    }

    private func updateStyling() {
        actionsStack.isHidden = !isHovered
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if isSelected {
                layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
            } else if isHovered {
                layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.07).cgColor
            } else {
                layer?.backgroundColor = NSColor.clear.cgColor
            }
        }
    }

    // MARK: - Actions & Context Menu

    @objc private func previewClicked() { onQuickLook?() }
    @objc private func revealClicked() { onRevealInFinder?() }
    @objc private func removeClicked() { onRemove?() }
    @objc private func copyFileClicked() { onCopyFile?() }
    @objc private func copyPathClicked() { onCopyPath?() }

    override func menu(for event: NSEvent) -> NSMenu? {
        onSelect?()
        let menu = NSMenu()
        let previewItem = NSMenuItem(title: "预览 (Quick Look)", action: #selector(previewClicked), keyEquivalent: "")
        previewItem.target = self
        menu.addItem(previewItem)

        let revealItem = NSMenuItem(title: "在访达中显示", action: #selector(revealClicked), keyEquivalent: "")
        revealItem.target = self
        menu.addItem(revealItem)

        menu.addItem(.separator())

        let copyFileItem = NSMenuItem(title: "拷贝文件", action: #selector(copyFileClicked), keyEquivalent: "")
        copyFileItem.target = self
        menu.addItem(copyFileItem)

        let copyPathItem = NSMenuItem(title: "拷贝文件路径", action: #selector(copyPathClicked), keyEquivalent: "")
        copyPathItem.target = self
        menu.addItem(copyPathItem)

        menu.addItem(.separator())

        let removeItem = NSMenuItem(title: "移除", action: #selector(removeClicked), keyEquivalent: "")
        removeItem.target = self
        menu.addItem(removeItem)

        return menu
    }

    // MARK: - Mouse & Drag Out

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        onSelect?()
        if event.clickCount == 2 {
            mouseDownEvent = nil
            onQuickLook?()
            return
        }
        mouseDownEvent = event
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let downEvent = mouseDownEvent else { return }
        let dx = event.locationInWindow.x - downEvent.locationInWindow.x
        let dy = event.locationInWindow.y - downEvent.locationInWindow.y
        guard hypot(dx, dy) >= 3 else { return }

        mouseDownEvent = nil
        startDraggingSingleItem(with: downEvent)
    }

    private func startDraggingSingleItem(with event: NSEvent) {
        let dragItem = NSDraggingItem(pasteboardWriter: item.url as NSURL)
        let loc = convert(event.locationInWindow, from: nil)
        let size = NSSize(width: 40, height: 40)
        let frame = NSRect(
            x: loc.x - size.width / 2,
            y: loc.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        let img = DragAllCardView.makeDragImage(from: item.displayImage, size: size)
        dragItem.setDraggingFrame(frame, contents: img)

        ShelfManager.shared.markInternalDragStarted(shelfID: shelfID)
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    // MARK: - NSDraggingSource

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        switch Preferences.shared.dragOutMode {
        case .copyOnly:
            return .copy
        case .systemDefault:
            return [.copy, .move, .link]
        }
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        ShelfManager.shared.markInternalDragEnded(shelfID: shelfID)
        onDragOperationEnded?([item.url], operation)
    }
}
