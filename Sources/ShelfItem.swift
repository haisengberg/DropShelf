import AppKit
import Darwin
import Foundation
import ImageIO

final class ShelfItem {
    let id = UUID()

    private(set) var url: URL
    private(set) var displayName: String
    private(set) var isDirectory: Bool
    private(set) var isImageFile: Bool
    private(set) var isMissing: Bool = false

    private(set) var fileSize: Int64?
    private(set) var isComputingSize: Bool
    private(set) var thumbnail: NSImage?
    private(set) var icon: NSImage

    private var fileReferenceURL: CFURL?
    private let startedInTrash: Bool
    private var vnodeSource: DispatchSourceFileSystemObject?
    private var changeHandler: (() -> Void)?

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "heif",
        "tif", "tiff", "bmp", "ico", "icns", "psd"
    ]

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    init(url: URL) {
        let standardized = url.standardizedFileURL
        self.url = standardized
        self.fileReferenceURL = Self.makeFileReferenceURL(for: standardized)
        self.startedInTrash = Self.isInTrash(standardized)
        self.displayName = FileManager.default.displayName(atPath: standardized.path)

        let resourceValues = try? standardized.resourceValues(forKeys: [
            .isDirectoryKey,
            .isPackageKey,
            .fileSizeKey
        ])
        let isDir = resourceValues?.isDirectory ?? false
        let isPkg = resourceValues?.isPackage ?? false
        self.isDirectory = isDir
        self.isImageFile = !isDir && Self.imageExtensions.contains(standardized.pathExtension.lowercased())

        if isDir || isPkg {
            self.fileSize = nil
            self.isComputingSize = true
        } else if let size = resourceValues?.fileSize {
            self.fileSize = Int64(size)
            self.isComputingSize = false
        } else {
            let attrs = try? FileManager.default.attributesOfItem(atPath: standardized.path)
            if let num = attrs?[.size] as? NSNumber {
                self.fileSize = num.int64Value
            } else {
                self.fileSize = 0
            }
            self.isComputingSize = false
        }

        let wsIcon = NSWorkspace.shared.icon(forFile: standardized.path)
        wsIcon.size = NSSize(width: 64, height: 64)
        self.icon = wsIcon
    }

    deinit {
        stopMonitoring()
    }

    var fileReferenceKey: String? {
        (fileReferenceURL as NSURL?)?.absoluteString
    }

    var displayImage: NSImage {
        thumbnail ?? icon
    }

    var formattedSize: String {
        if isMissing {
            return "原文件未找到"
        }
        if let size = fileSize {
            return Self.formatByteCount(size)
        }
        return isComputingSize ? "计算中…" : "文件夹"
    }

    static func formatByteCount(_ bytes: Int64) -> String {
        byteFormatter.string(fromByteCount: max(0, bytes))
    }

    static func makeFileReferenceURL(for url: URL) -> CFURL? {
        // Construct a fresh path URL so CoreFoundation never serves a stale cached inode/file-ID
        let freshURL = URL(fileURLWithPath: url.standardizedFileURL.path)
        return CFURLCreateFileReferenceURL(kCFAllocatorDefault, freshURL as CFURL, nil)?.takeRetainedValue()
    }

    static func fileReferenceKey(for url: URL) -> String? {
        (makeFileReferenceURL(for: url) as NSURL?)?.absoluteString
    }

    static func isInTrash(_ url: URL) -> Bool {
        let fm = FileManager.default
        var relationship: FileManager.URLRelationship = .other
        if (try? fm.getRelationship(&relationship, of: .trashDirectory, in: .userDomainMask, toItemAt: url)) != nil,
           relationship == .contains {
            return true
        }
        if let trashURL = try? fm.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: url, create: false) {
            let trashPath = trashURL.standardizedFileURL.path
            let itemPath = url.standardizedFileURL.path
            if itemPath == trashPath || itemPath.hasPrefix(trashPath + "/") {
                return true
            }
        }
        return false
    }

    /// Resolves the current path from the macOS file reference URL (inode / file ID)
    /// so Finder renames and same-volume moves are followed automatically.
    /// Returns `true` if any visible property (path, display name, missing state, or size) changed.
    @discardableResult
    func refreshFileState() -> Bool {
        let fm = FileManager.default
        let previousURL = self.url
        let previousName = self.displayName
        let previousMissing = self.isMissing
        let previousSize = self.fileSize

        // 1. Prefer resolving the inode-backed CFURL file reference
        if let refURL = fileReferenceURL,
           let currentRefKey = (refURL as NSURL).absoluteString,
           let resolvedCFURL = CFURLCreateFilePathURL(kCFAllocatorDefault, refURL, nil)?.takeRetainedValue() {
            let resolvedURL = (resolvedCFURL as URL).standardizedFileURL
            let exists = fm.fileExists(atPath: resolvedURL.path)
            let trashed = !startedInTrash && Self.isInTrash(resolvedURL)
            // Verify the file currently at resolvedURL still has the same inode/file ID
            // (prevents stale vnode cache hits when an open O_EVTONLY fd survives an atomic replace)
            let sameInode = exists && (Self.fileReferenceKey(for: resolvedURL) == currentRefKey)

            if sameInode && !trashed {
                applyValidURL(resolvedURL, reacquiredReference: false)
                return self.url != previousURL ||
                       self.displayName != previousName ||
                       self.isMissing != previousMissing ||
                       self.fileSize != previousSize
            }
        }

        // 2. Fallback: check last known path (handles atomic safe-save replacing inode)
        let fallbackExists = fm.fileExists(atPath: previousURL.path)
        let fallbackTrashed = !startedInTrash && Self.isInTrash(previousURL)
        if fallbackExists && !fallbackTrashed {
            fileReferenceURL = Self.makeFileReferenceURL(for: previousURL)
            applyValidURL(previousURL, reacquiredReference: true)
            return self.url != previousURL ||
                   self.displayName != previousName ||
                   self.isMissing != previousMissing ||
                   self.fileSize != previousSize
        }

        // 3. File no longer exists (deleted, unmounted, or moved to Trash)
        isMissing = true
        isComputingSize = false
        return !previousMissing
    }

    private func applyValidURL(_ resolvedURL: URL, reacquiredReference: Bool) {
        let pathChanged = (resolvedURL.path != self.url.path)
        let extChanged = (resolvedURL.pathExtension.lowercased() != self.url.pathExtension.lowercased())

        self.url = resolvedURL
        self.displayName = FileManager.default.displayName(atPath: resolvedURL.path)
        self.isMissing = false

        if pathChanged || reacquiredReference {
            let wsIcon = NSWorkspace.shared.icon(forFile: resolvedURL.path)
            wsIcon.size = NSSize(width: 64, height: 64)
            self.icon = wsIcon

            let resourceValues = try? resolvedURL.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .fileSizeKey])
            let isDir = resourceValues?.isDirectory ?? self.isDirectory
            let isPkg = resourceValues?.isPackage ?? false
            self.isDirectory = isDir
            self.isImageFile = !isDir && Self.imageExtensions.contains(resolvedURL.pathExtension.lowercased())

            if !self.isImageFile || extChanged {
                self.thumbnail = nil
            }

            if !isDir && !isPkg {
                if let size = resourceValues?.fileSize {
                    self.fileSize = Int64(size)
                }
                self.isComputingSize = false
            }
        } else if !isDirectory {
            if let size = (try? resolvedURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                self.fileSize = Int64(size)
            }
        }

        if reacquiredReference, let handler = changeHandler {
            startMonitoring(onChange: handler)
        }
    }

    // MARK: - VNODE File Monitoring

    func startMonitoring(onChange: @escaping () -> Void) {
        stopMonitoring()
        changeHandler = onChange

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.rename, .delete, .revoke],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.changeHandler?()
        }
        source.setCancelHandler {
            close(fd)
        }
        vnodeSource = source
        source.resume()
    }

    func stopMonitoring() {
        changeHandler = nil
        if let source = vnodeSource {
            vnodeSource = nil
            source.cancel()
        }
    }

    func loadThumbnailIfNeeded(completion: @escaping (NSImage?) -> Void) {
        guard !isMissing, isImageFile, thumbnail == nil else {
            completion(thumbnail)
            return
        }
        let targetURL = self.url
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let loaded = Self.generateThumbnail(for: targetURL, maxPixelSize: 120)
            DispatchQueue.main.async {
                guard let self = self else { return }
                if !self.isMissing, let loaded = loaded {
                    self.thumbnail = loaded
                }
                completion(loaded)
            }
        }
    }

    func computeDirectorySizeIfNeeded(isCancelled: @escaping () -> Bool, completion: @escaping (Int64?) -> Void) {
        guard !isMissing, isComputingSize else {
            completion(fileSize)
            return
        }
        let targetURL = self.url
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let computed = Self.calculateDirectorySize(at: targetURL, isCancelled: isCancelled)
            DispatchQueue.main.async {
                guard let self = self else { return }
                if !isCancelled() {
                    self.fileSize = computed
                    self.isComputingSize = false
                    completion(computed)
                }
            }
        }
    }

    private static func generateThumbnail(for url: URL, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private static func calculateDirectorySize(at url: URL, isCancelled: () -> Bool) -> Int64? {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return nil
        }

        var total: Int64 = 0
        var visited = 0
        let maxEntries = 50_000

        for case let fileURL as URL in enumerator {
            if isCancelled() { return nil }
            visited += 1
            if visited > maxEntries {
                break
            }
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let size = values.fileSize else {
                continue
            }
            total += Int64(size)
        }
        return total
    }
}
