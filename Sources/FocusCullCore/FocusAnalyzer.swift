import CoreGraphics
import Foundation
import ImageIO

public struct FocusAnalyzerOptions: Sendable {
    public var analysisMaxPixel: Int
    public var blockSize: Int
    public var blockStride: Int
    public var topFraction: Double
    public var directionalWeight: Double
    public var edgeTrim: Double
    public var useMetal: Bool

    public init(
        analysisMaxPixel: Int = 1100,
        blockSize: Int = 32,
        blockStride: Int = 24,
        topFraction: Double = 0.02,
        directionalWeight: Double = 0.45,
        edgeTrim: Double = 0,
        useMetal: Bool = true
    ) {
        self.analysisMaxPixel = analysisMaxPixel
        self.blockSize = blockSize
        self.blockStride = blockStride
        self.topFraction = topFraction
        self.directionalWeight = directionalWeight
        self.edgeTrim = edgeTrim
        self.useMetal = useMetal
    }

    public static let `default` = FocusAnalyzerOptions()
}

public enum FocusAnalyzerError: LocalizedError {
    case imageSourceUnavailable
    case thumbnailUnavailable
    case bitmapCreationFailed
    case imageTooSmall

    public var errorDescription: String? {
        switch self {
        case .imageSourceUnavailable:
            return "无法读取图像数据"
        case .thumbnailUnavailable:
            return "无法生成图像预览"
        case .bitmapCreationFailed:
            return "无法创建灰度分析图"
        case .imageTooSmall:
            return "图像尺寸过小"
        }
    }
}

public enum FocusAnalyzer {
    private static let exifDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = .current
        return formatter
    }()

    private static let exifSubsecondFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss.SSS"
        formatter.timeZone = .current
        return formatter
    }()

    /// Analyzes one image without throwing so a single corrupt file can never
    /// abort a large import.
    public static func analyze(
        url: URL,
        options: FocusAnalyzerOptions = .default
    ) -> PhotoAnalysis {
        let resourceValues = try? url.resourceValues(forKeys: [
            .fileSizeKey,
            .contentModificationDateKey
        ])
        let fileSize = Int64(resourceValues?.fileSize ?? 0)

        guard let source = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            return failure(url: url, fileSize: fileSize, error: FocusAnalyzerError.imageSourceUnavailable)
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?
        let exif = properties?[kCGImagePropertyExifDictionary] as? NSDictionary
        let tiff = properties?[kCGImagePropertyTIFFDictionary] as? NSDictionary

        var pixelWidth = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        var pixelHeight = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0

        let dateString = exif?[kCGImagePropertyExifDateTimeOriginal] as? String
            ?? exif?[kCGImagePropertyExifDateTimeDigitized] as? String
            ?? tiff?[kCGImagePropertyTIFFDateTime] as? String
        var captureDate = dateString.flatMap(parseEXIFDate)
        if captureDate == nil {
            captureDate = resourceValues?.contentModificationDate
        }

        guard let image = loadThumbnail(source: source, maxPixel: options.analysisMaxPixel) else {
            return failure(url: url, fileSize: fileSize, error: FocusAnalyzerError.thumbnailUnavailable)
        }

        if pixelWidth == 0 { pixelWidth = image.width }
        if pixelHeight == 0 { pixelHeight = image.height }

        do {
            let metrics = try score(image: image, options: options)
            return PhotoAnalysis(
                url: url,
                fileName: url.lastPathComponent,
                fileSize: fileSize,
                captureDate: captureDate,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                rawScore: metrics.score,
                isotropicScore: metrics.isotropicScore,
                directionalScore: metrics.directionalScore,
                backend: metrics.backend,
                focusRect: metrics.focusRect,
                analyzedWidth: metrics.width,
                analyzedHeight: metrics.height,
                focusBlocks: metrics.blocks
            )
        } catch {
            return failure(
                url: url,
                fileSize: fileSize,
                captureDate: captureDate,
                width: pixelWidth,
                height: pixelHeight,
                error: error
            )
        }
    }

    private static func loadThumbnail(source: CGImageSource, maxPixel: Int) -> CGImage? {
        let common: [CFString: Any] = [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true
        ]

        // Embedded previews make RAW imports much faster, but tiny EXIF
        // thumbnails are useless for focus scoring, so retry from the full image.
        if var image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            ([kCGImageSourceCreateThumbnailFromImageIfAbsent: true] as [CFString: Any])
                .merging(common) { _, new in new } as CFDictionary
        ) {
            if max(image.width, image.height) < 900 {
                if let full = CGImageSourceCreateThumbnailAtIndex(
                    source,
                    0,
                    ([kCGImageSourceCreateThumbnailFromImageAlways: true] as [CFString: Any])
                        .merging(common) { _, new in new } as CFDictionary
                ) {
                    image = full
                }
            }
            return image
        }

        return CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            ([kCGImageSourceCreateThumbnailFromImageAlways: true] as [CFString: Any])
                .merging(common) { _, new in new } as CFDictionary
        )
    }

    private struct Metrics {
        let score: Double
        let isotropicScore: Double
        let directionalScore: Double
        let backend: FocusBackend
        let focusRect: FocusRect?
        let width: Int
        let height: Int
        let blocks: [FocusBlockSample]
    }

    private static func score(image: CGImage, options: FocusAnalyzerOptions) throws -> Metrics {
        let sourceWidth = image.width
        let sourceHeight = image.height
        guard sourceWidth >= 8, sourceHeight >= 8 else {
            throw FocusAnalyzerError.imageTooSmall
        }

        let longest = max(sourceWidth, sourceHeight)
        let scale = min(1.0, CGFloat(options.analysisMaxPixel) / CGFloat(longest))
        let width = max(8, Int((CGFloat(sourceWidth) * scale).rounded()))
        let height = max(8, Int((CGFloat(sourceHeight) * scale).rounded()))

        // 8-bit grayscale is enough for a focus metric and keeps the scan fast.
        var pixels = [UInt8](repeating: 0, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)

        let createdContext: CGContext? = pixels.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return nil }
            guard let context = CGContext(
                data: base,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ) else { return nil }
            context.interpolationQuality = .high
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return context
        }
        guard createdContext != nil else {
            throw FocusAnalyzerError.bitmapCreationFailed
        }

        let blockSize = max(12, options.blockSize)
        let blockStride = max(8, options.blockStride)
        guard width >= blockSize, height >= blockSize else {
            throw FocusAnalyzerError.imageTooSmall
        }

        // Heavy pixel math runs on the GPU. The CPU only prepares the
        // downsampled grayscale buffer and picks the top block percentiles.
        if options.useMetal,
           let metal = MetalFocusScorer.shared,
           let result = metal.score(
               gray: pixels,
               width: width,
               height: height,
               blockSize: blockSize,
               blockStride: blockStride,
               topFraction: options.topFraction,
               directionalWeight: options.directionalWeight,
               edgeTrim: options.edgeTrim
           ) {
            let blocks = result.blocks.map { block in
                FocusBlockSample(
                    rect: FocusRect(
                        x: Double(block.x) / Double(width),
                        y: Double(block.y) / Double(height),
                        width: Double(block.width) / Double(width),
                        height: Double(block.height) / Double(height)
                    ),
                    energy: block.combined,
                    directional: block.directional
                )
            }
            return Metrics(
                score: result.score,
                isotropicScore: result.isotropicScore,
                directionalScore: result.directionalScore,
                backend: .metal,
                focusRect: result.focusRect,
                width: width,
                height: height,
                blocks: blocks
            )
        }

        let gray = pixels.map(Float.init)
        let pixelCount = width * height

        // A small binomial blur suppresses sensor noise and JPEG ringing before
        // the second derivative, which makes the Laplacian much more stable.
        var horizontal = [Float](repeating: 0, count: pixelCount)
        for y in 0..<height {
            let row = y * width
            horizontal[row] = gray[row]
            horizontal[row + width - 1] = gray[row + width - 1]
            if width > 2 {
                for x in 1..<(width - 1) {
                    let index = row + x
                    horizontal[index] = (gray[index - 1] + 2 * gray[index] + gray[index + 1]) * 0.25
                }
            }
        }

        var blurred = [Float](repeating: 0, count: pixelCount)
        blurred.withUnsafeMutableBufferPointer { output in
            horizontal.withUnsafeBufferPointer { input in
                guard let out = output.baseAddress, let source = input.baseAddress else { return }
                for x in 0..<width {
                    out[x] = source[x]
                    out[(height - 1) * width + x] = source[(height - 1) * width + x]
                }
                if height > 2 {
                    for y in 1..<(height - 1) {
                        let row = y * width
                        for x in 0..<width {
                            let index = row + x
                            out[index] = (source[index - width] + 2 * source[index] + source[index + width]) * 0.25
                        }
                    }
                }
            }
        }

        // Compute horizontal and vertical second derivatives independently.
        // A directional motion blur can leave one axis looking sharp; requiring
        // energy on both axes catches that failure mode.
        var blocks: [FocusBlock] = []
        let blocksX = max(0, (width - blockSize - 2) / blockStride + 1)
        let blocksY = max(0, (height - blockSize - 2) / blockStride + 1)
        blocks.reserveCapacity(blocksX * blocksY)

        blurred.withUnsafeBufferPointer { input in
            guard let src = input.baseAddress else { return }
            var blockY = 1
            while blockY + blockSize < height {
                var blockX = 1
                while blockX + blockSize < width {
                    var sumX = 0.0
                    var sumX2 = 0.0
                    var sumY = 0.0
                    var sumY2 = 0.0
                    for y in blockY..<(blockY + blockSize) {
                        let row = y * width
                        for x in blockX..<(blockX + blockSize) {
                            let index = row + x
                            let center = Double(src[index])
                            let dx = 2 * center - Double(src[index - 1]) - Double(src[index + 1])
                            let dy = 2 * center - Double(src[index - width]) - Double(src[index + width])
                            sumX += dx
                            sumX2 += dx * dx
                            sumY += dy
                            sumY2 += dy * dy
                        }
                    }
                    let count = Double(blockSize * blockSize)
                    let meanX = sumX / count
                    let meanY = sumY / count
                    let varianceX = max(0, sumX2 / count - meanX * meanX)
                    let varianceY = max(0, sumY2 / count - meanY * meanY)
                    blocks.append(FocusBlock(
                        x: blockX,
                        y: blockY,
                        width: blockSize,
                        height: blockSize,
                        combined: varianceX + varianceY,
                        directional: (varianceX * varianceY).squareRoot()
                    ))
                    blockX += blockStride
                }
                blockY += blockStride
            }
        }

        guard !blocks.isEmpty else {
            throw FocusAnalyzerError.imageTooSmall
        }

        let usable = FocusBlockScoring.usableBlocks(
            blocks,
            imageWidth: width,
            imageHeight: height,
            edgeTrim: options.edgeTrim
        )
        let scores = FocusBlockScoring.scores(
            blocks: usable,
            topFraction: options.topFraction,
            directionalWeight: options.directionalWeight
        )
        let focusRect = FocusBlockScoring.focusRect(
            blocks: usable,
            imageWidth: width,
            imageHeight: height
        )
        let samples = usable.map { block in
            FocusBlockSample(
                rect: FocusRect(
                    x: Double(block.x) / Double(width),
                    y: Double(block.y) / Double(height),
                    width: Double(block.width) / Double(width),
                    height: Double(block.height) / Double(height)
                ),
                energy: block.combined,
                directional: block.directional
            )
        }

        return Metrics(
            score: scores.combined,
            isotropicScore: scores.isotropic,
            directionalScore: scores.directional,
            backend: .cpu,
            focusRect: focusRect,
            width: width,
            height: height,
            blocks: samples
        )
    }

    /// Turns a large attention box into a compact box around its sharpest
    /// blocks. This keeps the "合焦" marker useful for small distant subjects.
    public static func refinedFocusRect(
        blocks: [FocusBlockSample],
        within region: FocusRect
    ) -> FocusRect? {
        let minX = region.x
        let maxX = region.x + region.width
        let minY = region.y
        let maxY = region.y + region.height
        let selected = blocks.filter { block in
            let cx = block.rect.x + block.rect.width / 2
            let cy = block.rect.y + block.rect.height / 2
            return cx >= minX && cx <= maxX && cy >= minY && cy <= maxY
        }
        guard selected.count >= 3 else { return nil }
        let topCount = max(6, Int((Double(selected.count) * 0.10).rounded()))
        let top = selected.sorted { $0.energy > $1.energy }.prefix(topCount)
        var x1 = 1.0, y1 = 1.0, x2 = 0.0, y2 = 0.0
        for block in top {
            x1 = min(x1, block.rect.x)
            y1 = min(y1, block.rect.y)
            x2 = max(x2, block.rect.x + block.rect.width)
            y2 = max(y2, block.rect.y + block.rect.height)
        }
        guard x2 > x1, y2 > y1 else { return nil }
        let padX = (x2 - x1) * 0.12 + 0.01
        let padY = (y2 - y1) * 0.12 + 0.01
        x1 = max(0, x1 - padX)
        y1 = max(0, y1 - padY)
        x2 = min(1, x2 + padX)
        y2 = min(1, y2 + padY)
        return FocusRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1)
    }

    /// Re-scores only the AI subject/face region from the saved local blocks.
    public static func regionScore(
        blocks: [FocusBlockSample],
        rect: FocusRect,
        topFraction: Double,
        directionalWeight: Double
    ) -> (isotropic: Double, directional: Double, combined: Double, count: Int)? {
        FocusBlockScoring.regionScores(
            samples: blocks,
            rect: rect,
            topFraction: topFraction,
            directionalWeight: directionalWeight
        )
    }

    private static func parseEXIFDate(_ string: String) -> Date? {
        if let date = exifSubsecondFormatter.date(from: string) {
            return date
        }
        return exifDateFormatter.date(from: string)
    }

    private static func failure(
        url: URL,
        fileSize: Int64,
        captureDate: Date? = nil,
        width: Int = 0,
        height: Int = 0,
        error: Error
    ) -> PhotoAnalysis {
        PhotoAnalysis(
            url: url,
            fileName: url.lastPathComponent,
            fileSize: fileSize,
            captureDate: captureDate,
            pixelWidth: width,
            pixelHeight: height,
            rawScore: 0,
            backend: .failed,
            errorMessage: error.localizedDescription
        )
    }
}
