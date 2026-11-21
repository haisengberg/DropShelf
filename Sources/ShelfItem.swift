import AppKit
import Foundation
import ImageIO

final class ShelfItem {
    let url: URL
    let displayName: String
    let isDirectory: Bool
    let isImageFile: Bool

    private(set) var fileSize: Int64?
    private(set) var isComputingSize: Bool
    private(set) var thumbnail: NSImage?
    private(set) var icon: NSImage

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

    var displayImage: NSImage {
        thumbnail ?? icon
    }

    var formattedSize: String {
        if let size = fileSize {
            return Self.formatByteCount(size)
        }
        return isComputingSize ? "计算中…" : "文件夹"
    }

    static func formatByteCount(_ bytes: Int64) -> String {
        byteFormatter.string(fromByteCount: max(0, bytes))
    }

    func loadThumbnailIfNeeded(completion: @escaping (NSImage?) -> Void) {
        guard isImageFile, thumbnail == nil else {
            completion(thumbnail)
            return
        }
        let targetURL = self.url
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let loaded = Self.generateThumbnail(for: targetURL, maxPixelSize: 120)
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let loaded = loaded {
                    self.thumbnail = loaded
                }
                completion(loaded)
            }
        }
    }

    func computeDirectorySizeIfNeeded(isCancelled: @escaping () -> Bool, completion: @escaping (Int64?) -> Void) {
        guard isComputingSize else {
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
