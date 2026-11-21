import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private let shakeDetector = ShakeDetector()
    private let hotKeyManager = HotKeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let bundleID = Bundle.main.bundleIdentifier {
            let otherInstances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if !otherInstances.isEmpty {
                NSApp.terminate(nil)
                return
            }
        }

        NSApp.setActivationPolicy(.accessory)

        statusBarController = StatusBarController()

        shakeDetector.shouldSuppress = {
            ShelfManager.shared.isAnyInternalDragActive
        }
        shakeDetector.onShakeDetected = { cursorLocation in
            ShelfManager.shared.createShelf(
                near: cursorLocation,
                anchorBelowPoint: false,
                initialURLs: [],
                autoDismissIfEmpty: true,
                makeKey: false
            )
        }
        shakeDetector.start()

        hotKeyManager.onHotKeyPressed = {
            let cursor = NSEvent.mouseLocation
            ShelfManager.shared.createShelf(
                near: cursor,
                anchorBelowPoint: false,
                initialURLs: [],
                autoDismissIfEmpty: false,
                makeKey: true
            )
        }
        hotKeyManager.registerDefaultHotKey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        shakeDetector.stop()
        hotKeyManager.unregister()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let validURLs = urls
            .filter { $0.isFileURL }
            .map { $0.standardizedFileURL }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !validURLs.isEmpty else { return }

        ShelfManager.shared.createShelf(
            near: NSEvent.mouseLocation,
            anchorBelowPoint: false,
            initialURLs: validURLs,
            autoDismissIfEmpty: false,
            makeKey: false
        )
    }
}
