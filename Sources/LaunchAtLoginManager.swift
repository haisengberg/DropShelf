import Foundation

final class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    private var label: String {
        Bundle.main.bundleIdentifier ?? "dev.dropshelf.DropShelf"
    }

    private var launchAgentsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
    }

    var plistURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(label).plist")
    }

    var isEnabled: Bool {
        guard FileManager.default.fileExists(atPath: plistURL.path),
              let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ) as? [String: Any] else {
            return false
        }
        return (plist["RunAtLoad"] as? Bool) ?? true
    }

    func setEnabled(_ enabled: Bool) throws {
        let fm = FileManager.default
        if enabled {
            try fm.createDirectory(
                at: launchAgentsDirectory,
                withIntermediateDirectories: true
            )

            let executablePath = resolvedExecutablePath()
            let bundleID = Bundle.main.bundleIdentifier ?? label
            let plist: [String: Any] = [
                "Label": label,
                "AssociatedBundleIdentifiers": [bundleID],
                "ProgramArguments": [executablePath],
                "RunAtLoad": true,
                "LimitLoadToSessionType": "Aqua",
                "ProcessType": "Interactive"
            ]

            let data = try PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            )
            try data.write(to: plistURL, options: .atomic)
        } else {
            if fm.fileExists(atPath: plistURL.path) {
                try fm.removeItem(at: plistURL)
            }
        }
    }

    private func resolvedExecutablePath() -> String {
        if let path = Bundle.main.executablePath,
           FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return "/Applications/DropShelf.app/Contents/MacOS/DropShelf"
    }
}
