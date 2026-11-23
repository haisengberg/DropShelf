import AppKit
import Foundation
import Quartz

final class ShelfViewController: NSViewController, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    let shelfID: UUID
    var onRequestClose: (() -> Void)?

    private var items: [ShelfItem] = []
    private var rowViews: [ShelfItemRowView] = []
    private var selectedIndex: Int?
    private var isPinned: Bool = false {
        didSet { updatePinButton() }
    }
    private var isClosed: Bool = false

    // Auto-dismiss state (for shake-to-open empty shelves)
    private var autoDismissIfEmpty: Bool
    private var isMouseInside: Bool = false
    private var autoDismissTimer: Timer?
    private var fileHealthTimer: Timer?
    private let initialAutoDismissDelay: TimeInterval = 6.0
    private let hoverExitDismissDelay: TimeInterval = 2.5
    private let fileHealthCheckInterval: TimeInterval = 2.0
    private let maxVNodeWatchers: Int = 64

    // UI elements
    private lazy var dropContainer = ShelfDropContainerView(shelfID: shelfID)
    private let headerView = NSView()
    private let headerIconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "中转架")
    private let countBadgeLabel = NSTextField(labelWithString: "")
    private let countBadgeContainer = NSView()
    private lazy var pinButton = IconActionButton(
        symbolName: "pin",
        pointSize: 12,
        tooltip: "固定中转架（拖出后不自动关闭）"
    )
    private lazy var addButton = IconActionButton(
        symbolName: "plus",
        pointSize: 12.5,
        weight: .semibold,
        tooltip: "添加文件或文件夹"
    )
    private lazy var closeButton = IconActionButton(
        symbolName: "xmark",
        pointSize: 11.5,
        weight: .semibold,
        tooltip: "关闭中转架 (Esc)"
    )

    private let headerDivider = NSBox()
    private let emptyDropZone = DashedDropZoneView()

    private let populatedContainer = NSView()
    private lazy var dragAllCard = DragAllCardView(shelfID: shelfID)
    private let scrollView = NSScrollView()
    private let listStackView = NSStackView()

    private let footerDivider = NSBox()
    private let footerView = NSView()
    private let copyAllButton = NSButton()
    private let clearButton = NSButton()
    private let dragModeBadgeButton = DragModeBadgeButton()
    private var copyFeedbackWorkItem: DispatchWorkItem?

    var hasItems: Bool { !items.isEmpty }
    private var validItems: [ShelfItem] { items.filter { !$0.isMissing } }

    // Layout sizing helper
    static func preferredSize(forItemCount count: Int) -> NSSize {
        if count == 0 {
            return NSSize(width: 268, height: 192)
        }
        let headerHeight: CGFloat = 38
        let cardHeight: CGFloat = 58
        let footerHeight: CGFloat = 36
        let paddingAndGaps: CGFloat = 34
        let rowHeight: CGFloat = 46
        let visibleRows = min(count, 5)
        let listHeight = CGFloat(visibleRows) * rowHeight + (count > 5 ? 10 : 0)
        let totalHeight = min(460, headerHeight + cardHeight + listHeight + footerHeight + paddingAndGaps)
        return NSSize(width: 296, height: totalHeight)
    }

    init(shelfID: UUID, autoDismissIfEmpty: Bool) {
        self.shelfID = shelfID
        self.autoDismissIfEmpty = autoDismissIfEmpty
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        autoDismissTimer?.invalidate()
        fileHealthTimer?.invalidate()
        copyFeedbackWorkItem?.cancel()
        for item in items {
            item.stopMonitoring()
        }
    }

    override func loadView() {
        view = dropContainer
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCallbacks()
        setupHeader()
        setupEmptyState()
        setupPopulatedState()
        setupFooter()
        setupLayoutConstraints()
        updateUIState(animatedResize: false)
        updateDragModeBadge()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidChange),
            name: Preferences.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        if autoDismissIfEmpty {
            scheduleAutoDismiss(after: initialAutoDismissDelay)
        }
    }

    func prepareForClose() {
        isClosed = true
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
        fileHealthTimer?.invalidate()
        fileHealthTimer = nil
        copyFeedbackWorkItem?.cancel()
        for item in items {
            item.stopMonitoring()
        }
        if QLPreviewPanel.sharedPreviewPanelExists() {
            let ql = QLPreviewPanel.shared()
            if ql?.isVisible == true && (ql?.dataSource as AnyObject?) === self {
                ql?.orderOut(nil)
            }
        }
    }

    // MARK: - UI Construction

    private func setupCallbacks() {
        dropContainer.onValidateDrop = { urls in
            !urls.isEmpty
        }
        dropContainer.onAcceptDrop = { [weak self] urls in
            guard let self = self else { return false }
            self.addFileURLs(urls, animatedResize: true)
            return true
        }
        dropContainer.onDragHoverChanged = { [weak self] hovering in
            self?.emptyDropZone.isHighlighted = hovering
            if hovering {
                self?.autoDismissTimer?.invalidate()
            } else {
                self?.rescheduleAutoDismissIfNeeded(delay: self?.hoverExitDismissDelay ?? 2.5)
            }
        }
        dropContainer.onMouseHoverChanged = { [weak self] inside in
            guard let self = self else { return }
            self.isMouseInside = inside
            if inside {
                self.autoDismissTimer?.invalidate()
                self.refreshAllItemStates()
            } else {
                self.rescheduleAutoDismissIfNeeded(delay: self.hoverExitDismissDelay)
            }
        }
    }

    private func setupHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        dropContainer.addSubview(headerView)

        let iconConfig = NSImage.SymbolConfiguration(pointSize: 12.5, weight: .semibold)
        let img = NSImage(systemSymbolName: "tray.and.arrow.down.fill", accessibilityDescription: "DropShelf")?
            .withSymbolConfiguration(iconConfig)
        img?.isTemplate = true
        headerIconView.image = img
        headerIconView.contentTintColor = .controlAccentColor
        headerIconView.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(headerIconView)

        titleLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(titleLabel)

        countBadgeContainer.wantsLayer = true
        countBadgeContainer.layer?.cornerRadius = 8
        countBadgeContainer.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
        countBadgeContainer.isHidden = true
        countBadgeContainer.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(countBadgeContainer)

        countBadgeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
        countBadgeLabel.textColor = .controlAccentColor
        countBadgeLabel.alignment = .center
        countBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        countBadgeContainer.addSubview(countBadgeLabel)

        pinButton.activeTintColor = .controlAccentColor
        pinButton.target = self
        pinButton.action = #selector(togglePin)
        pinButton.translatesAutoresizingMaskIntoConstraints = false

        addButton.target = self
        addButton.action = #selector(addFilesClicked)
        addButton.translatesAutoresizingMaskIntoConstraints = false

        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        let rightStack = NSStackView(views: [pinButton, addButton, closeButton])
        rightStack.orientation = .horizontal
        rightStack.spacing = 2
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(rightStack)

        for btn in [pinButton, addButton, closeButton] {
            NSLayoutConstraint.activate([
                btn.widthAnchor.constraint(equalToConstant: 24),
                btn.heightAnchor.constraint(equalToConstant: 24)
            ])
        }

        NSLayoutConstraint.activate([
            headerIconView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
            headerIconView.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: headerIconView.trailingAnchor, constant: 6),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            countBadgeContainer.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 6),
            countBadgeContainer.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            countBadgeContainer.heightAnchor.constraint(equalToConstant: 16),

            countBadgeLabel.leadingAnchor.constraint(equalTo: countBadgeContainer.leadingAnchor, constant: 6),
            countBadgeLabel.trailingAnchor.constraint(equalTo: countBadgeContainer.trailingAnchor, constant: -6),
            countBadgeLabel.centerYAnchor.constraint(equalTo: countBadgeContainer.centerYAnchor),

            rightStack.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -8),
            rightStack.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
        ])

        headerDivider.boxType = .separator
        headerDivider.translatesAutoresizingMaskIntoConstraints = false
        dropContainer.addSubview(headerDivider)
    }

    private func setupEmptyState() {
        emptyDropZone.translatesAutoresizingMaskIntoConstraints = false
        dropContainer.addSubview(emptyDropZone)
    }

    private func setupPopulatedState() {
        populatedContainer.translatesAutoresizingMaskIntoConstraints = false
        dropContainer.addSubview(populatedContainer)

        dragAllCard.translatesAutoresizingMaskIntoConstraints = false
        dragAllCard.itemsProvider = { [weak self] in self?.items ?? [] }
        dragAllCard.onWillBeginDrag = { [weak self] in
            self?.refreshAllItemStates()
        }
        dragAllCard.onDragOperationEnded = { [weak self] itemIDs, operation in
            self?.handleDragOutEnded(draggedItemIDs: itemIDs, operation: operation)
        }
        populatedContainer.addSubview(dragAllCard)

        let clipView = FlippedClipView()
        clipView.drawsBackground = false
        scrollView.contentView = clipView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let docView = FlippedView()
        docView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = docView

        listStackView.orientation = .vertical
        listStackView.alignment = .leading
        listStackView.spacing = 2
        listStackView.translatesAutoresizingMaskIntoConstraints = false
        docView.addSubview(listStackView)

        populatedContainer.addSubview(scrollView)

        NSLayoutConstraint.activate([
            dragAllCard.topAnchor.constraint(equalTo: populatedContainer.topAnchor),
            dragAllCard.leadingAnchor.constraint(equalTo: populatedContainer.leadingAnchor),
            dragAllCard.trailingAnchor.constraint(equalTo: populatedContainer.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: dragAllCard.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: populatedContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: populatedContainer.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: populatedContainer.bottomAnchor),

            docView.topAnchor.constraint(equalTo: clipView.topAnchor),
            docView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            docView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
            docView.widthAnchor.constraint(equalTo: clipView.widthAnchor),

            listStackView.topAnchor.constraint(equalTo: docView.topAnchor),
            listStackView.leadingAnchor.constraint(equalTo: docView.leadingAnchor),
            listStackView.trailingAnchor.constraint(equalTo: docView.trailingAnchor),
            listStackView.bottomAnchor.constraint(equalTo: docView.bottomAnchor)
        ])
    }

    private func setupFooter() {
        footerDivider.boxType = .separator
        footerDivider.translatesAutoresizingMaskIntoConstraints = false
        dropContainer.addSubview(footerDivider)

        footerView.translatesAutoresizingMaskIntoConstraints = false
        dropContainer.addSubview(footerView)

        configureFooterButton(copyAllButton, title: "复制全部", symbol: "doc.on.doc", action: #selector(copyAllClicked))
        configureFooterButton(clearButton, title: "清空", symbol: "trash", action: #selector(clearAllClicked))

        dragModeBadgeButton.target = self
        dragModeBadgeButton.action = #selector(toggleDragModeClicked)
        dragModeBadgeButton.translatesAutoresizingMaskIntoConstraints = false

        footerView.addSubview(copyAllButton)
        footerView.addSubview(clearButton)
        footerView.addSubview(dragModeBadgeButton)

        NSLayoutConstraint.activate([
            copyAllButton.leadingAnchor.constraint(equalTo: footerView.leadingAnchor, constant: 10),
            copyAllButton.centerYAnchor.constraint(equalTo: footerView.centerYAnchor),
            copyAllButton.heightAnchor.constraint(equalToConstant: 24),

            clearButton.leadingAnchor.constraint(equalTo: copyAllButton.trailingAnchor, constant: 4),
            clearButton.centerYAnchor.constraint(equalTo: footerView.centerYAnchor),
            clearButton.heightAnchor.constraint(equalToConstant: 24),

            dragModeBadgeButton.trailingAnchor.constraint(equalTo: footerView.trailingAnchor, constant: -10),
            dragModeBadgeButton.centerYAnchor.constraint(equalTo: footerView.centerYAnchor),
            dragModeBadgeButton.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    private func configureFooterButton(_ button: NSButton, title: String, symbol: String, action: Selector) {
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.title = " \(title)"
        button.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        button.contentTintColor = .secondaryLabelColor
        let cfg = NSImage.SymbolConfiguration(pointSize: 10.5, weight: .medium)
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?.withSymbolConfiguration(cfg)
        img?.isTemplate = true
        button.image = img
        button.imagePosition = .imageLeading
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupLayoutConstraints() {
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: dropContainer.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: dropContainer.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: dropContainer.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 36),

            headerDivider.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            headerDivider.leadingAnchor.constraint(equalTo: dropContainer.leadingAnchor, constant: 10),
            headerDivider.trailingAnchor.constraint(equalTo: dropContainer.trailingAnchor, constant: -10),

            emptyDropZone.topAnchor.constraint(equalTo: headerDivider.bottomAnchor, constant: 10),
            emptyDropZone.leadingAnchor.constraint(equalTo: dropContainer.leadingAnchor, constant: 12),
            emptyDropZone.trailingAnchor.constraint(equalTo: dropContainer.trailingAnchor, constant: -12),
            emptyDropZone.bottomAnchor.constraint(equalTo: dropContainer.bottomAnchor, constant: -12),

            populatedContainer.topAnchor.constraint(equalTo: headerDivider.bottomAnchor, constant: 10),
            populatedContainer.leadingAnchor.constraint(equalTo: dropContainer.leadingAnchor, constant: 10),
            populatedContainer.trailingAnchor.constraint(equalTo: dropContainer.trailingAnchor, constant: -10),
            populatedContainer.bottomAnchor.constraint(equalTo: footerDivider.topAnchor, constant: -8),

            footerDivider.leadingAnchor.constraint(equalTo: dropContainer.leadingAnchor, constant: 10),
            footerDivider.trailingAnchor.constraint(equalTo: dropContainer.trailingAnchor, constant: -10),
            footerDivider.bottomAnchor.constraint(equalTo: footerView.topAnchor),

            footerView.leadingAnchor.constraint(equalTo: dropContainer.leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: dropContainer.trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: dropContainer.bottomAnchor),
            footerView.heightAnchor.constraint(equalToConstant: 34)
        ])
    }

    // MARK: - Items Management

    func addFileURLs(_ urls: [URL], animatedResize: Bool = true) {
        refreshAllItemStates()

        var seenPaths = Set(items.map { $0.url.standardizedFileURL.path })
        var seenRefKeys = Set(items.compactMap { $0.fileReferenceKey })
        var addedItems: [ShelfItem] = []

        for rawURL in urls {
            guard rawURL.isFileURL else { continue }
            let standardized = rawURL.standardizedFileURL
            guard FileManager.default.fileExists(atPath: standardized.path) else { continue }
            let refKey = ShelfItem.fileReferenceKey(for: standardized)
            if seenPaths.contains(standardized.path) { continue }
            if let refKey = refKey, seenRefKeys.contains(refKey) { continue }

            seenPaths.insert(standardized.path)
            if let refKey = refKey {
                seenRefKeys.insert(refKey)
            }

            let item = ShelfItem(url: standardized)
            items.append(item)
            addedItems.append(item)
        }

        guard !addedItems.isEmpty else { return }

        // Cancel auto-dismiss permanently once user drops files in
        autoDismissIfEmpty = false
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil

        for item in addedItems {
            startMonitoringIfAllowed(for: item)
        }
        updateFileHealthTimer()

        rebuildListUI(animatedResize: animatedResize)
        kickOffAsyncMetadata(for: addedItems)
        reloadQuickLookIfVisible()
    }

    private func startMonitoringIfAllowed(for item: ShelfItem) {
        guard items.prefix(maxVNodeWatchers).contains(where: { $0 === item }) else { return }
        item.startMonitoring { [weak self, weak item] in
            guard let self = self, let item = item, !self.isClosed else { return }
            self.handleFileSystemChange(for: item)
        }
    }

    private func updateFileHealthTimer() {
        if items.isEmpty || isClosed {
            fileHealthTimer?.invalidate()
            fileHealthTimer = nil
            return
        }
        guard fileHealthTimer == nil else { return }
        let timer = Timer(timeInterval: fileHealthCheckInterval, repeats: true) { [weak self] _ in
            guard let self = self, !self.isClosed else { return }
            self.refreshAllItemStates()
        }
        RunLoop.main.add(timer, forMode: .common)
        fileHealthTimer = timer
    }

    private func handleFileSystemChange(for item: ShelfItem) {
        guard item.refreshFileState() else { return }
        if !item.isMissing && item.isImageFile && item.thumbnail == nil {
            item.loadThumbnailIfNeeded { [weak self, weak item] image in
                guard let self = self, let item = item, image != nil, !self.isClosed else { return }
                self.refreshVisuals(for: item)
            }
        }
        refreshVisuals(for: item)
        reloadQuickLookIfVisible()
    }

    private func refreshAllItemStates() {
        guard !items.isEmpty, !isClosed else { return }
        var anyChanged = false

        for item in items {
            if item.refreshFileState() {
                anyChanged = true
                if !item.isMissing && item.isImageFile && item.thumbnail == nil {
                    item.loadThumbnailIfNeeded { [weak self, weak item] image in
                        guard let self = self, let item = item, image != nil, !self.isClosed else { return }
                        self.refreshVisuals(for: item)
                    }
                }
                if let row = rowViews.first(where: { $0.item === item }) {
                    row.refreshVisuals()
                }
            }
        }

        if anyChanged {
            dragAllCard.configure(with: items)
            reloadQuickLookIfVisible()
        }
    }

    private func kickOffAsyncMetadata(for newItems: [ShelfItem]) {
        for item in newItems {
            item.loadThumbnailIfNeeded { [weak self, weak item] image in
                guard let self = self, let item = item, image != nil, !self.isClosed else { return }
                self.refreshVisuals(for: item)
            }
            item.computeDirectorySizeIfNeeded(
                isCancelled: { [weak self] in self?.isClosed ?? true },
                completion: { [weak self, weak item] _ in
                    guard let self = self, let item = item, !self.isClosed else { return }
                    self.refreshVisuals(for: item)
                }
            )
        }
    }

    private func refreshVisuals(for item: ShelfItem) {
        if let row = rowViews.first(where: { $0.item === item }) {
            row.refreshVisuals()
        }
        if !items.isEmpty {
            dragAllCard.configure(with: items)
        }
    }

    private func removeItems(withIDs ids: Set<UUID>, animatedResize: Bool = true) {
        let beforeCount = items.count
        for item in items where ids.contains(item.id) {
            item.stopMonitoring()
        }
        items.removeAll { ids.contains($0.id) }
        guard items.count != beforeCount else { return }

        updateFileHealthTimer()

        if let sel = selectedIndex {
            if items.isEmpty {
                selectedIndex = nil
            } else if sel >= items.count {
                selectedIndex = items.count - 1
            }
        }
        rebuildListUI(animatedResize: animatedResize)
        reloadQuickLookIfVisible()
    }

    private func handleDragOutEnded(draggedItemIDs: [UUID], operation: NSDragOperation) {
        // Resolve current file references first so same-volume moves follow the new path
        // and deleted/trashed files immediately show their Missing badge.
        refreshAllItemStates()

        if operation != [],
           Preferences.shared.autoClearAndCloseOnDragOut,
           !isPinned {
            let idSet = Set(draggedItemIDs)
            for item in items where idSet.contains(item.id) {
                item.stopMonitoring()
            }
            items.removeAll { idSet.contains($0.id) }
            updateFileHealthTimer()
            if items.isEmpty {
                onRequestClose?()
                return
            }
            if let sel = selectedIndex, sel >= items.count {
                selectedIndex = items.isEmpty ? nil : items.count - 1
            }
            rebuildListUI(animatedResize: true)
            reloadQuickLookIfVisible()
        }
    }

    // MARK: - UI State & Resizing

    private func rebuildListUI(animatedResize: Bool) {
        for view in listStackView.arrangedSubviews {
            listStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        rowViews.removeAll(keepingCapacity: true)

        for (index, item) in items.enumerated() {
            let row = ShelfItemRowView(shelfID: shelfID, item: item)
            row.isSelected = (selectedIndex == index)
            row.translatesAutoresizingMaskIntoConstraints = false

            row.onSelect = { [weak self] in
                self?.selectRow(at: index)
            }
            row.onWillBeginDrag = { [weak self] in
                self?.refreshAllItemStates()
            }
            row.onQuickLook = { [weak self] in
                self?.openQuickLook(at: index)
            }
            row.onRevealInFinder = { [weak self, weak item] in
                guard let self = self, let item = item else { return }
                self.refreshAllItemStates()
                guard !item.isMissing else {
                    NSSound.beep()
                    return
                }
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            row.onCopyFile = { [weak self, weak item] in
                guard let self = self, let item = item else { return }
                self.refreshAllItemStates()
                guard !item.isMissing else {
                    NSSound.beep()
                    return
                }
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.writeObjects([item.url as NSURL])
            }
            row.onCopyPath = { [weak self, weak item] in
                guard let self = self, let item = item else { return }
                self.refreshAllItemStates()
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(item.url.path, forType: .string)
            }
            row.onRemove = { [weak self, weak item] in
                guard let self = self, let itemID = item?.id else { return }
                self.removeItems(withIDs: [itemID], animatedResize: true)
            }
            row.onDragOperationEnded = { [weak self] itemIDs, op in
                self?.handleDragOutEnded(draggedItemIDs: itemIDs, operation: op)
            }

            listStackView.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: listStackView.widthAnchor).isActive = true
            rowViews.append(row)
        }

        updateUIState(animatedResize: animatedResize)
    }

    private func updateUIState(animatedResize: Bool) {
        let empty = items.isEmpty
        emptyDropZone.isHidden = !empty
        populatedContainer.isHidden = empty
        footerDivider.isHidden = empty
        footerView.isHidden = empty

        countBadgeContainer.isHidden = empty
        countBadgeLabel.stringValue = "\(items.count)"

        if !empty {
            dragAllCard.configure(with: items)
        }

        resizeWindowKeepingTopAnchor(animated: animatedResize)
    }

    private func resizeWindowKeepingTopAnchor(animated: Bool) {
        guard let window = view.window else { return }
        let targetSize = Self.preferredSize(forItemCount: items.count)
        let currentFrame = window.frame
        guard abs(currentFrame.width - targetSize.width) > 0.5 ||
              abs(currentFrame.height - targetSize.height) > 0.5 else {
            return
        }

        var newOrigin = NSPoint(
            x: currentFrame.minX,
            y: currentFrame.maxY - targetSize.height
        )

        if let screen = window.screen ?? NSScreen.main {
            let visible = screen.visibleFrame.insetBy(dx: 12, dy: 12)
            newOrigin.x = min(max(newOrigin.x, visible.minX), max(visible.minX, visible.maxX - targetSize.width))
            newOrigin.y = min(max(newOrigin.y, visible.minY), max(visible.minY, visible.maxY - targetSize.height))
        }

        let newFrame = NSRect(origin: newOrigin, size: targetSize)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(newFrame, display: true)
            } completionHandler: {
                window.invalidateShadow()
            }
        } else {
            window.setFrame(newFrame, display: true)
            window.invalidateShadow()
        }
    }

    private func selectRow(at index: Int) {
        guard index >= 0 && index < items.count else { return }
        selectedIndex = index
        for (i, row) in rowViews.enumerated() {
            row.isSelected = (i == index)
        }
        if QLPreviewPanel.sharedPreviewPanelExists(),
           let ql = QLPreviewPanel.shared(),
           ql.isVisible,
           (ql.dataSource as AnyObject?) === self {
            let item = items[index]
            if let validIdx = validItems.firstIndex(where: { $0.id == item.id }) {
                ql.currentPreviewItemIndex = validIdx
            }
        }
    }

    // MARK: - Auto-Dismiss

    private func scheduleAutoDismiss(after delay: TimeInterval) {
        autoDismissTimer?.invalidate()
        guard autoDismissIfEmpty, items.isEmpty, !isPinned else { return }

        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            guard self.autoDismissIfEmpty, self.items.isEmpty, !self.isPinned, !self.isMouseInside else {
                return
            }
            self.onRequestClose?()
        }
        RunLoop.main.add(timer, forMode: .common)
        autoDismissTimer = timer
    }

    private func rescheduleAutoDismissIfNeeded(delay: TimeInterval) {
        guard autoDismissIfEmpty, items.isEmpty, !isPinned, !isMouseInside else { return }
        scheduleAutoDismiss(after: delay)
    }

    // MARK: - Header & Footer Actions

    @objc private func togglePin() {
        isPinned.toggle()
        if isPinned {
            autoDismissIfEmpty = false
            autoDismissTimer?.invalidate()
            autoDismissTimer = nil
        }
    }

    private func updatePinButton() {
        pinButton.setSymbol(isPinned ? "pin.fill" : "pin", pointSize: 12)
        pinButton.isActiveState = isPinned
        pinButton.toolTip = isPinned
            ? "已固定中转架（点击取消固定）"
            : "固定中转架（拖出后不自动关闭）"
    }

    @objc private func addFilesClicked() {
        autoDismissTimer?.invalidate()
        let panel = NSOpenPanel()
        panel.title = "选择要添加到中转架的文件或文件夹"
        panel.prompt = "添加"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true
        panel.level = .floating

        activateAppForInteraction()
        panel.begin { [weak self] response in
            guard let self = self else { return }
            if response == .OK {
                self.addFileURLs(panel.urls, animatedResize: true)
            } else {
                self.rescheduleAutoDismissIfNeeded(delay: self.hoverExitDismissDelay)
            }
        }
    }

    @objc private func closeClicked() {
        onRequestClose?()
    }

    @objc private func copyAllClicked() {
        copyAllItemsToPasteboard()
    }

    private func copyAllItemsToPasteboard() {
        refreshAllItemStates()
        let available = validItems
        guard !available.isEmpty else {
            NSSound.beep()
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        let urls = available.map { $0.url as NSURL }
        pb.writeObjects(urls)

        // Subtle confirmation feedback
        copyFeedbackWorkItem?.cancel()
        copyAllButton.title = " 已复制"
        copyAllButton.contentTintColor = .controlAccentColor

        let work = DispatchWorkItem { [weak self] in
            self?.copyAllButton.title = " 复制全部"
            self?.copyAllButton.contentTintColor = .secondaryLabelColor
        }
        copyFeedbackWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    @objc private func clearAllClicked() {
        for item in items {
            item.stopMonitoring()
        }
        items.removeAll()
        selectedIndex = nil
        updateFileHealthTimer()
        rebuildListUI(animatedResize: true)
        reloadQuickLookIfVisible()
    }

    @objc private func toggleDragModeClicked() {
        Preferences.shared.toggleDragOutMode()
    }

    @objc private func preferencesDidChange() {
        updateDragModeBadge()
        dragAllCard.refreshDragModeAppearance()
        for row in rowViews {
            row.refreshVisuals()
        }
    }

    @objc private func appDidBecomeActive() {
        refreshAllItemStates()
    }

    private func updateDragModeBadge() {
        dragModeBadgeButton.apply(mode: Preferences.shared.dragOutMode)
    }

    // MARK: - Keyboard Handling

    func handleKeyEvent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // ⌘V: Paste file URLs from clipboard
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "v" {
            pasteFileURLsFromClipboard()
            return true
        }

        // ⌘C: Copy all shelf file URLs
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "c" {
            if !items.isEmpty {
                copyAllItemsToPasteboard()
                return true
            }
            return false
        }

        // Space: Toggle Quick Look preview
        if flags.isEmpty && event.keyCode == 49 {
            if !items.isEmpty {
                toggleQuickLook()
                return true
            }
            return false
        }

        // Esc: Close Quick Look first, or close shelf if unpinned
        if flags.isEmpty && event.keyCode == 53 {
            if QLPreviewPanel.sharedPreviewPanelExists(),
               let ql = QLPreviewPanel.shared(),
               ql.isVisible {
                ql.orderOut(nil)
                return true
            }
            if !isPinned {
                onRequestClose?()
                return true
            }
            return false
        }

        // Up / Down arrow selection navigation
        if flags.isEmpty && (event.keyCode == 125 || event.keyCode == 126), !items.isEmpty {
            let current = selectedIndex ?? (event.keyCode == 125 ? -1 : items.count)
            let next: Int
            if event.keyCode == 125 {
                next = min(items.count - 1, current + 1)
            } else {
                next = max(0, current - 1)
            }
            selectRow(at: next)
            return true
        }

        return false
    }

    private func pasteFileURLsFromClipboard() {
        let pb = NSPasteboard.general
        guard let urls = pb.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty else {
            NSSound.beep()
            return
        }
        addFileURLs(urls, animatedResize: true)
    }

    // MARK: - Quick Look

    private func activateAppForInteraction() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func toggleQuickLook() {
        refreshAllItemStates()
        guard !validItems.isEmpty else {
            NSSound.beep()
            return
        }
        if QLPreviewPanel.sharedPreviewPanelExists(),
           let ql = QLPreviewPanel.shared(),
           ql.isVisible {
            ql.orderOut(nil)
        } else {
            let targetIndex: Int
            if let sel = selectedIndex, sel < items.count, !items[sel].isMissing {
                targetIndex = sel
            } else if let firstValid = items.firstIndex(where: { !$0.isMissing }) {
                targetIndex = firstValid
            } else {
                NSSound.beep()
                return
            }
            openQuickLook(at: targetIndex)
        }
    }

    func openQuickLook(at index: Int) {
        refreshAllItemStates()
        guard index >= 0 && index < items.count else { return }
        let targetItem = items[index]
        guard !targetItem.isMissing else {
            NSSound.beep()
            return
        }

        selectedIndex = index
        selectRow(at: index)

        let previewItems = validItems
        guard let previewIndex = previewItems.firstIndex(where: { $0.id == targetItem.id }) else {
            NSSound.beep()
            return
        }

        activateAppForInteraction()
        view.window?.makeKeyAndOrderFront(nil)

        guard let ql = QLPreviewPanel.shared() else { return }
        ql.updateController()
        if !ql.isVisible {
            ql.makeKeyAndOrderFront(nil)
        } else {
            ql.orderFront(nil)
        }
        ql.reloadData()
        ql.currentPreviewItemIndex = previewIndex
    }

    func configurePreviewPanel(_ panel: QLPreviewPanel) {
        let previewItems = validItems
        if let idx = selectedIndex, idx < items.count,
           let validIdx = previewItems.firstIndex(where: { $0.id == items[idx].id }) {
            panel.currentPreviewItemIndex = validIdx
        } else if !previewItems.isEmpty {
            panel.currentPreviewItemIndex = 0
        }
    }

    private func reloadQuickLookIfVisible() {
        guard QLPreviewPanel.sharedPreviewPanelExists(),
              let ql = QLPreviewPanel.shared(),
              ql.isVisible,
              (ql.dataSource as AnyObject?) === self else {
            return
        }
        if validItems.isEmpty {
            ql.orderOut(nil)
        } else {
            ql.reloadData()
        }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return validItems.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        let previewItems = validItems
        guard index >= 0 && index < previewItems.count else { return nil }
        return previewItems[index].url as NSURL
    }

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        if event.type == .keyDown {
            return handleKeyEvent(event)
        }
        return false
    }
}
