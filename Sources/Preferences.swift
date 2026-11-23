import Foundation

enum DragOutMode: String, CaseIterable {
    case systemDefault
    case copyOnly

    var shortBadgeTitle: String {
        switch self {
        case .systemDefault:
            return "移动/复制"
        case .copyOnly:
            return "仅复制"
        }
    }

    var badgeSymbolName: String {
        switch self {
        case .systemDefault:
            return "arrow.right.arrow.left"
        case .copyOnly:
            return "doc.on.doc.fill"
        }
    }

    var dragHintText: String {
        switch self {
        case .systemDefault:
            return "拖出：同盘移动 / 跨盘复制"
        case .copyOnly:
            return "拖出：仅复制（保留原文件）"
        }
    }

    var hoverDragHintText: String {
        switch self {
        case .systemDefault:
            return "按住拖出 · 同盘移动 / 跨盘复制"
        case .copyOnly:
            return "按住拖出 · 仅复制（保留原文件）"
        }
    }

    var rowDragTooltipSummary: String {
        switch self {
        case .systemDefault:
            return "拖出方式：同盘移动 / 跨盘复制（按住 ⌥ 可临时复制）"
        case .copyOnly:
            return "拖出方式：仅复制（不会移动原文件）"
        }
    }

    func dragPreviewBadge(optionKeyPressed: Bool) -> (text: String, isCopyOnly: Bool) {
        if self == .copyOnly || optionKeyPressed {
            return ("复制", true)
        }
        return ("移动/复制", false)
    }

    var badgeTooltip: String {
        switch self {
        case .systemDefault:
            return "当前拖出模式：同盘移动 / 跨盘复制（系统默认，拖出时按住 ⌥ 可临时强制复制）。点击切换为「仅复制」。"
        case .copyOnly:
            return "当前拖出模式：仅复制（不会移动原文件，更安全）。点击切换为「移动/复制」。"
        }
    }
}

final class Preferences {
    static let shared = Preferences()
    static let didChangeNotification = Notification.Name("DropShelf.PreferencesDidChange")

    private enum Keys {
        static let shakeToOpenEnabled = "DropShelf.shakeToOpenEnabled"
        static let autoClearAndCloseOnDragOut = "DropShelf.autoClearAndCloseOnDragOut"
        static let dragOutMode = "DropShelf.dragOutMode"
    }

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.shakeToOpenEnabled: true,
            Keys.autoClearAndCloseOnDragOut: true,
            Keys.dragOutMode: DragOutMode.systemDefault.rawValue
        ])
    }

    var shakeToOpenEnabled: Bool {
        get { defaults.bool(forKey: Keys.shakeToOpenEnabled) }
        set {
            guard newValue != shakeToOpenEnabled else { return }
            defaults.set(newValue, forKey: Keys.shakeToOpenEnabled)
            notifyChange()
        }
    }

    var autoClearAndCloseOnDragOut: Bool {
        get { defaults.bool(forKey: Keys.autoClearAndCloseOnDragOut) }
        set {
            guard newValue != autoClearAndCloseOnDragOut else { return }
            defaults.set(newValue, forKey: Keys.autoClearAndCloseOnDragOut)
            notifyChange()
        }
    }

    var dragOutMode: DragOutMode {
        get {
            guard let raw = defaults.string(forKey: Keys.dragOutMode),
                  let mode = DragOutMode(rawValue: raw) else {
                return .systemDefault
            }
            return mode
        }
        set {
            guard newValue != dragOutMode else { return }
            defaults.set(newValue.rawValue, forKey: Keys.dragOutMode)
            notifyChange()
        }
    }

    func toggleDragOutMode() {
        dragOutMode = (dragOutMode == .systemDefault) ? .copyOnly : .systemDefault
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
