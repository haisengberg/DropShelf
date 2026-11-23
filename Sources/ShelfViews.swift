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

// MARK: - Footer Drag-Mode Pill Toggle

final class DragModeBadgeButton: NSButton {
    private let iconView = NSImageView()
    private let labelField = NSTextField(labelWithString: "")
    private let contentStack = NSStackView()

    private var trackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet { updateAppearance() }
    }
    private var currentMode: DragOutMode = .systemDefault

    override var mouseDownCanMoveWindow: Bool { false }

    init() {
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        title = ""
        image = nil
        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.borderWidth = 0.5

        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        labelField.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        labelField.lineBreakMode = .byClipping
        labelField.translatesAutoresizingMaskIntoConstraints = false
        labelField.setContentHuggingPriority(.required, for: .horizontal)
        labelField.setContentCompressionResistancePriority(.required, for: .horizontal)

        contentStack.orientation = .horizontal
        contentStack.alignment = .centerY
        contentStack.spacing = 4
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(iconView)
        contentStack.addArrangedSubview(labelField)
        addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        apply(mode: Preferences.shared.dragOutMode)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) != nil ? self : nil
    }

    func apply(mode: DragOutMode) {
        currentMode = mode
        labelField.stringValue = mode.shortBadgeTitle
        toolTip = mode.badgeTooltip

        let cfg = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        let img = NSImage(systemSymbolName: mode.badgeSymbolName, accessibilityDescription: mode.shortBadgeTitle)?
            .withSymbolConfiguration(cfg)
        img?.isTemplate = true
        iconView.image = img

        invalidateIntrinsicContentSize()
        updateAppearance()
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
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if currentMode == .copyOnly {
                let tint = NSColor.systemGreen
                iconView.contentTintColor = tint
                labelField.textColor = tint
                let bgAlpha: CGFloat = isHovered ? 0.22 : 0.14
                layer?.backgroundColor = tint.withAlphaComponent(bgAlpha).cgColor
                layer?.borderColor = tint.withAlphaComponent(0.32).cgColor
            } else {
                let tint: NSColor = isHovered ? .labelColor : .secondaryLabelColor
                iconView.contentTintColor = tint
                labelField.textColor = tint
                let bgAlpha: CGFloat = isHovered ? 0.11 : 0.06
                layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(bgAlpha).cgColor
                layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.22).cgColor
            }
        }
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
    var onWillBeginDrag: (() -> Void)?
    var onDragOperationEnded: (([UUID], NSDragOperation) -> Void)?

    private let stackContainer = NSView()
    private let iconImageViews: [NSImageView] = (0..<3).map { _ in NSImageView() }
    private let summaryLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private let gripIconView = NSImageView()

    private var trackingArea: NSTrackingArea?
    private var hasValidItems = false
    private var isHovered = false {
        didSet {
            updateStyling()
            updateDragModeHint()
        }
    }
    private var mouseDownEvent: NSEvent?
    private var draggingItemIDs: [UUID] = []

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
        let validItems = items.filter { !$0.isMissing }
        let missingCount = items.count - validItems.count
        hasValidItems = !validItems.isEmpty

        let knownBytes = validItems.compactMap { $0.fileSize }.reduce(0, +)
        let stillComputing = validItems.contains { $0.isComputingSize }

        let sizeText: String
        if stillComputing && knownBytes == 0 {
            sizeText = "计算大小中…"
        } else if stillComputing {
            sizeText = "\(ShelfItem.formatByteCount(knownBytes))+"
        } else {
            sizeText = ShelfItem.formatByteCount(knownBytes)
        }

        if validItems.isEmpty {
            summaryLabel.stringValue = "共 \(items.count) 项 · 均已失效"
        } else if missingCount > 0 {
            summaryLabel.stringValue = "\(validItems.count) 个可用 · \(missingCount) 个已失效"
        } else {
            summaryLabel.stringValue = "\(validItems.count) 个项目 · \(sizeText)"
        }

        updateDragModeHint()
        updateStyling()

        let previewItems = validItems.isEmpty ? items : validItems
        let previewCount = previewItems.count
        stackContainer.alphaValue = hasValidItems ? 1.0 : 0.45

        for iv in iconImageViews {
            iv.isHidden = true
            iv.frameCenterRotation = 0
        }

        if previewCount == 1 {
            let front = iconImageViews[2]
            front.image = previewItems[0].displayImage
            front.frame = NSRect(x: 8, y: 5, width: 32, height: 32)
            front.isHidden = false
        } else if previewCount == 2 {
            let left = iconImageViews[0]
            left.image = previewItems[1].displayImage
            left.frame = NSRect(x: 4, y: 6, width: 28, height: 28)
            left.frameCenterRotation = 8
            left.isHidden = false

            let front = iconImageViews[2]
            front.image = previewItems[0].displayImage
            front.frame = NSRect(x: 14, y: 4, width: 30, height: 30)
            front.frameCenterRotation = -4
            front.isHidden = false
        } else if previewCount >= 3 {
            let backLeft = iconImageViews[0]
            backLeft.image = previewItems[2].displayImage
            backLeft.frame = NSRect(x: 2, y: 6, width: 26, height: 26)
            backLeft.frameCenterRotation = 10
            backLeft.isHidden = false

            let backRight = iconImageViews[1]
            backRight.image = previewItems[1].displayImage
            backRight.frame = NSRect(x: 20, y: 6, width: 26, height: 26)
            backRight.frameCenterRotation = -10
            backRight.isHidden = false

            let front = iconImageViews[2]
            front.image = previewItems[0].displayImage
            front.frame = NSRect(x: 10, y: 4, width: 30, height: 30)
            front.frameCenterRotation = 0
            front.isHidden = false
        }
    }

    func refreshDragModeAppearance() {
        updateDragModeHint()
        updateStyling()
    }

    private func updateDragModeHint() {
        if !hasValidItems {
            hintLabel.stringValue = "原文件已移除，可点击下方清空"
            hintLabel.textColor = .systemRed
            toolTip = "中转架内的原文件均已删除或移至废纸篓"
            return
        }

        let mode = Preferences.shared.dragOutMode
        hintLabel.stringValue = isHovered ? mode.hoverDragHintText : mode.dragHintText
        hintLabel.textColor = (mode == .copyOnly) ? .systemGreen : .secondaryLabelColor
        toolTip = mode.rowDragTooltipSummary
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
        if hasValidItems {
            NSCursor.openHand.set()
        }
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
            if !hasValidItems {
                layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.08).cgColor
                layer?.borderColor = NSColor.systemRed.withAlphaComponent(0.30).cgColor
                gripIconView.contentTintColor = .tertiaryLabelColor
                summaryLabel.textColor = .secondaryLabelColor
            } else if isHovered {
                let accent: NSColor = (Preferences.shared.dragOutMode == .copyOnly) ? .systemGreen : .controlAccentColor
                layer?.backgroundColor = accent.withAlphaComponent(0.14).cgColor
                layer?.borderColor = accent.withAlphaComponent(0.45).cgColor
                gripIconView.contentTintColor = accent
                summaryLabel.textColor = .labelColor
            } else {
                layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
                layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
                gripIconView.contentTintColor = .tertiaryLabelColor
                summaryLabel.textColor = .labelColor
            }
        }
    }

    // MARK: - Mouse & Drag Out

    override func mouseDown(with event: NSEvent) {
        guard hasValidItems else {
            NSSound.beep()
            return
        }
        mouseDownEvent = event
        NSCursor.closedHand.set()
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
        if isHovered && hasValidItems {
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
        onWillBeginDrag?()
        let items = (itemsProvider?() ?? []).filter { !$0.isMissing }
        guard !items.isEmpty else {
            NSSound.beep()
            NSCursor.arrow.set()
            return
        }

        draggingItemIDs = items.map { $0.id }
        let dragLocation = convert(event.locationInWindow, from: nil)
        let optionPressed = event.modifierFlags.contains(.option)
        let badge = Preferences.shared.dragOutMode.dragPreviewBadge(optionKeyPressed: optionPressed)

        var draggingItems: [NSDraggingItem] = []
        for (index, item) in items.enumerated() {
            let dragItem = NSDraggingItem(pasteboardWriter: item.url as NSURL)
            let iconSize: CGFloat = 44
            let offset = CGFloat(min(index, 4)) * 3.0
            let dragImage: NSImage
            if index == 0 {
                dragImage = Self.makeDragImage(
                    from: item.displayImage,
                    iconSize: NSSize(width: iconSize, height: iconSize),
                    badgeText: badge.text,
                    isCopyBadge: badge.isCopyOnly
                )
            } else {
                dragImage = Self.makeDragImage(
                    from: item.displayImage,
                    iconSize: NSSize(width: iconSize, height: iconSize),
                    badgeText: nil,
                    isCopyBadge: false
                )
            }
            let imgSize = dragImage.size
            let frame = NSRect(
                x: dragLocation.x - imgSize.width / 2 + offset,
                y: dragLocation.y - imgSize.height / 2 - offset,
                width: imgSize.width,
                height: imgSize.height
            )
            dragItem.setDraggingFrame(frame, contents: dragImage)
            draggingItems.append(dragItem)
        }

        ShelfManager.shared.markInternalDragStarted(shelfID: shelfID)
        let session = beginDraggingSession(with: draggingItems, event: event, source: self)
        session.draggingFormation = .pile
    }

    static func makeDragImage(
        from image: NSImage,
        iconSize: NSSize,
        badgeText: String? = nil,
        isCopyBadge: Bool = false
    ) -> NSImage {
        guard let badgeText = badgeText, !badgeText.isEmpty else {
            return NSImage(size: iconSize, flipped: false) { rect in
                NSGraphicsContext.current?.imageInterpolation = .high
                image.draw(
                    in: rect,
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 0.95
                )
                return true
            }
        }

        let font = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let textSize = (badgeText as NSString).size(withAttributes: attrs)
        let pillHeight: CGFloat = 16
        let pillWidth = max(36, ceil(textSize.width) + 12)
        let gap: CGFloat = 2
        let canvasSize = NSSize(
            width: max(iconSize.width, pillWidth + 4),
            height: iconSize.height + pillHeight + gap + 2
        )

        return NSImage(size: canvasSize, flipped: false) { _ in
            NSGraphicsContext.current?.imageInterpolation = .high

            let iconRect = NSRect(
                x: (canvasSize.width - iconSize.width) / 2,
                y: pillHeight + gap + 1,
                width: iconSize.width,
                height: iconSize.height
            )
            image.draw(
                in: iconRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 0.95
            )

            let pillRect = NSRect(
                x: (canvasSize.width - pillWidth) / 2,
                y: 1,
                width: pillWidth,
                height: pillHeight
            )
            let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: pillHeight / 2, yRadius: pillHeight / 2)
            let bgColor = isCopyBadge
                ? NSColor.systemGreen.withAlphaComponent(0.92)
                : NSColor(calibratedWhite: 0.12, alpha: 0.86)
            bgColor.setFill()
            pillPath.fill()

            NSColor.white.withAlphaComponent(0.24).setStroke()
            pillPath.lineWidth = 0.5
            pillPath.stroke()

            let textRect = NSRect(
                x: pillRect.minX + (pillRect.width - textSize.width) / 2,
                y: pillRect.minY + (pillRect.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            (badgeText as NSString).draw(in: textRect, withAttributes: attrs)
            return true
        }
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
        let ids = draggingItemIDs
        draggingItemIDs = []
        NSCursor.arrow.set()
        onDragOperationEnded?(ids, operation)
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
    var onWillBeginDrag: (() -> Void)?
    var onDragOperationEnded: (([UUID], NSDragOperation) -> Void)?

    var isSelected: Bool = false {
        didSet { updateStyling() }
    }

    private let thumbnailView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let sizeLabel = NSTextField(labelWithString: "")
    private let missingBadgeContainer = NSView()
    private let missingBadgeIcon = NSImageView()
    private let missingBadgeLabel = NSTextField(labelWithString: "已失效")
    private let rightStack = NSStackView()
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

        // Missing-file badge pill
        missingBadgeContainer.wantsLayer = true
        missingBadgeContainer.layer?.cornerRadius = 6
        missingBadgeContainer.layer?.borderWidth = 0.5
        missingBadgeContainer.translatesAutoresizingMaskIntoConstraints = false
        missingBadgeContainer.setContentHuggingPriority(.required, for: .horizontal)
        missingBadgeContainer.setContentCompressionResistancePriority(.required, for: .horizontal)

        let warnCfg = NSImage.SymbolConfiguration(pointSize: 9.5, weight: .semibold)
        let warnImg = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "已失效")?
            .withSymbolConfiguration(warnCfg)
        warnImg?.isTemplate = true
        missingBadgeIcon.image = warnImg
        missingBadgeIcon.contentTintColor = .systemRed
        missingBadgeIcon.translatesAutoresizingMaskIntoConstraints = false

        missingBadgeLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        missingBadgeLabel.textColor = .systemRed
        missingBadgeLabel.translatesAutoresizingMaskIntoConstraints = false

        let badgeStack = NSStackView(views: [missingBadgeIcon, missingBadgeLabel])
        badgeStack.orientation = .horizontal
        badgeStack.alignment = .centerY
        badgeStack.spacing = 3
        badgeStack.translatesAutoresizingMaskIntoConstraints = false
        missingBadgeContainer.addSubview(badgeStack)

        NSLayoutConstraint.activate([
            missingBadgeContainer.heightAnchor.constraint(equalToConstant: 18),
            badgeStack.leadingAnchor.constraint(equalTo: missingBadgeContainer.leadingAnchor, constant: 6),
            badgeStack.trailingAnchor.constraint(equalTo: missingBadgeContainer.trailingAnchor, constant: -6),
            badgeStack.centerYAnchor.constraint(equalTo: missingBadgeContainer.centerYAnchor)
        ])

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

        rightStack.orientation = .horizontal
        rightStack.alignment = .centerY
        rightStack.spacing = 4
        rightStack.addArrangedSubview(missingBadgeContainer)
        rightStack.addArrangedSubview(actionsStack)
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        rightStack.setContentHuggingPriority(.required, for: .horizontal)
        rightStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(rightStack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 44),

            thumbnailView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            thumbnailView.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 30),
            thumbnailView.heightAnchor.constraint(equalToConstant: 30),

            textStack.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 9),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -6),

            rightStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            rightStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        refreshVisuals()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refreshVisuals() {
        thumbnailView.image = item.displayImage
        nameLabel.stringValue = item.displayName
        sizeLabel.stringValue = item.formattedSize

        if item.isMissing {
            let tip = "原文件已删除或移至废纸篓\n上次位置：\(item.url.path)"
            nameLabel.toolTip = tip
            toolTip = tip
        } else {
            let tip = "\(item.url.path)\n\(Preferences.shared.dragOutMode.rowDragTooltipSummary)"
            nameLabel.toolTip = tip
            toolTip = tip
        }

        updateStyling()
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
        let missing = item.isMissing
        missingBadgeContainer.isHidden = !missing
        previewButton.isHidden = missing
        revealButton.isHidden = missing
        removeButton.isHidden = false
        actionsStack.isHidden = !isHovered

        thumbnailView.alphaValue = missing ? 0.42 : 1.0
        nameLabel.textColor = missing ? .tertiaryLabelColor : .labelColor
        sizeLabel.textColor = missing ? .systemRed : .secondaryLabelColor

        effectiveAppearance.performAsCurrentDrawingAppearance {
            missingBadgeContainer.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.14).cgColor
            missingBadgeContainer.layer?.borderColor = NSColor.systemRed.withAlphaComponent(0.34).cgColor

            if isSelected {
                let bg = missing
                    ? NSColor.systemRed.withAlphaComponent(0.13)
                    : NSColor.controlAccentColor.withAlphaComponent(0.18)
                layer?.backgroundColor = bg.cgColor
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
        onWillBeginDrag?()

        let missing = item.isMissing
        let menu = NSMenu()
        menu.autoenablesItems = false

        let previewItem = NSMenuItem(title: "预览 (Quick Look)", action: #selector(previewClicked), keyEquivalent: "")
        previewItem.target = self
        previewItem.isEnabled = !missing
        menu.addItem(previewItem)

        let revealItem = NSMenuItem(title: "在访达中显示", action: #selector(revealClicked), keyEquivalent: "")
        revealItem.target = self
        revealItem.isEnabled = !missing
        menu.addItem(revealItem)

        menu.addItem(.separator())

        let copyFileItem = NSMenuItem(title: "拷贝文件", action: #selector(copyFileClicked), keyEquivalent: "")
        copyFileItem.target = self
        copyFileItem.isEnabled = !missing
        menu.addItem(copyFileItem)

        let copyPathItem = NSMenuItem(
            title: missing ? "拷贝上次路径" : "拷贝文件路径",
            action: #selector(copyPathClicked),
            keyEquivalent: ""
        )
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
            if item.isMissing {
                NSSound.beep()
            } else {
                onQuickLook?()
            }
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
        onWillBeginDrag?()
        guard !item.isMissing else {
            NSSound.beep()
            return
        }

        let dragItem = NSDraggingItem(pasteboardWriter: item.url as NSURL)
        let loc = convert(event.locationInWindow, from: nil)
        let optionPressed = event.modifierFlags.contains(.option)
        let badge = Preferences.shared.dragOutMode.dragPreviewBadge(optionKeyPressed: optionPressed)
        let img = DragAllCardView.makeDragImage(
            from: item.displayImage,
            iconSize: NSSize(width: 40, height: 40),
            badgeText: badge.text,
            isCopyBadge: badge.isCopyOnly
        )
        let imgSize = img.size
        let frame = NSRect(
            x: loc.x - imgSize.width / 2,
            y: loc.y - imgSize.height / 2,
            width: imgSize.width,
            height: imgSize.height
        )
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
        onDragOperationEnded?([item.id], operation)
    }
}
