import Foundation

enum DragOutMode: String, CaseIterable {
    case systemDefault
    case copyOnly

    var shortBadgeTitle: String {
        switch self {
        case .systemDefault:
            return "默认"
        case .copyOnly:
            return "仅复制"
        }
    }

    var badgeTooltip: String {
        switch self {
        case .systemDefault:
            return "当前拖出模式：系统默认（同卷移动 / 跨卷复制）。点击切换为「仅复制」。"
        case .copyOnly:
            return "当前拖出模式：仅复制（更安全，不移动原文件）。点击切换为「系统默认」。"
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
