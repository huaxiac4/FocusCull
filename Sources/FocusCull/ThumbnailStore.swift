import AppKit
import ImageIO

private struct SendableCGImage: @unchecked Sendable {
    let image: CGImage
    let cost: Int
}

@MainActor
final class ThumbnailStore {
    static let shared = ThumbnailStore()

    private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 800
        cache.totalCostLimit = 640 * 1024 * 1024
        return cache
    }()

    private init() {}

    func image(for url: URL, maxPixel: Int, preferEmbedded: Bool = true) async -> NSImage? {
        let key = "\(url.path)|\(maxPixel)|\(preferEmbedded)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let decoded = await Task.detached(priority: .utility) {
            Self.decode(url: url, maxPixel: maxPixel, preferEmbedded: preferEmbedded)
        }.value

        guard let decoded else { return nil }
        let image = NSImage(
            cgImage: decoded.image,
            size: NSSize(width: decoded.image.width, height: decoded.image.height)
        )
        cache.setObject(image, forKey: key, cost: decoded.cost)
        return image
    }

    private nonisolated static func decode(
        url: URL,
        maxPixel: Int,
        preferEmbedded: Bool
    ) -> SendableCGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            return nil
        }

        let common: [CFString: Any] = [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true
        ]

        var cgImage: CGImage?
        if preferEmbedded {
            cgImage = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                ([kCGImageSourceCreateThumbnailFromImageIfAbsent: true] as [CFString: Any])
                    .merging(common) { _, new in new } as CFDictionary
            )
        }

        let minimumUsefulSize = min(maxPixel, 1600)
        if cgImage == nil || max(cgImage?.width ?? 0, cgImage?.height ?? 0) < minimumUsefulSize {
            if let full = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                ([kCGImageSourceCreateThumbnailFromImageAlways: true] as [CFString: Any])
                    .merging(common) { _, new in new } as CFDictionary
            ) {
                cgImage = full
            }
        }

        guard let cgImage else { return nil }
        return SendableCGImage(
            image: cgImage,
            cost: max(1, cgImage.bytesPerRow * cgImage.height)
        )
    }
}
