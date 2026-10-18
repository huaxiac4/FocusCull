import Foundation

public struct PhotoScanResult: Sendable {
    public let urls: [URL]
    public let skippedCount: Int
    public init(urls: [URL], skippedCount: Int) {
        self.urls = urls
        self.skippedCount = skippedCount
    }
}

public enum PhotoScannerError: LocalizedError {
    case notAFolder(URL)
    case cannotRead(URL, Error)

    public var errorDescription: String? {
        switch self {
        case .notAFolder:
            return "请选择一个文件夹。"
        case let .cannotRead(url, error):
            return "无法读取「\(url.lastPathComponent)」：\(error.localizedDescription)"
        }
    }
}

public enum PhotoScanner {
    /// Recursively or non-recursively finds supported image files.
    public static func scan(folder: URL, recursive: Bool) throws -> PhotoScanResult {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw PhotoScannerError.notAFolder(folder)
        }

        let keys: [URLResourceKey] = [.isRegularFileKey, .isHiddenKey, .nameKey]
        var urls: [URL] = []
        var skipped = 0

        if recursive {
            var enumerationError: Error?
            guard let enumerator = fileManager.enumerator(
                at: folder,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles],
                errorHandler: { _, error in
                    enumerationError = error
                    return true
                }
            ) else {
                throw PhotoScannerError.cannotRead(folder, CocoaError(.fileReadNoPermission))
            }

            for case let url as URL in enumerator {
                guard PhotoFileType.isSupported(url) else { continue }
                do {
                    let values = try url.resourceValues(forKeys: Set(keys))
                    guard values.isRegularFile == true, values.isHidden != true else { continue }
                    urls.append(url)
                } catch {
                    skipped += 1
                }
            }
            if let enumerationError, urls.isEmpty {
                throw PhotoScannerError.cannotRead(folder, enumerationError)
            }
        } else {
            let contents: [URL]
            do {
                contents = try fileManager.contentsOfDirectory(
                    at: folder,
                    includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles]
                )
            } catch {
                throw PhotoScannerError.cannotRead(folder, error)
            }
            for url in contents {
                guard PhotoFileType.isSupported(url) else { continue }
                do {
                    let values = try url.resourceValues(forKeys: Set(keys))
                    guard values.isRegularFile == true, values.isHidden != true else { continue }
                    urls.append(url)
                } catch {
                    skipped += 1
                }
            }
        }

        urls.sort { lhs, rhs in
            lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
        }

        return PhotoScanResult(urls: urls, skippedCount: skipped)
    }
}
