import Foundation
import ImageIO

/// Which engine computed the focus score.
/// Normalized rectangle in image coordinates, origin at the top-left.
public struct FocusRect: Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum FocusBackend: String, Sendable, Hashable {
    case metal
    case cpu
    case failed

    public var displayName: String {
        switch self {
        case .metal: return "Metal GPU"
        case .cpu: return "CPU"
        case .failed: return "未分析"
        }
    }
}

/// One photo after the focus-analysis pass.
public struct PhotoAnalysis: Identifiable, Hashable, Sendable {
    public let url: URL
    public let fileName: String
    public let fileSize: Int64
    public let captureDate: Date?
    public let pixelWidth: Int
    public let pixelHeight: Int
    /// Raw focus score. Higher is sharper.
    public let rawScore: Double
    /// Isotropic high-frequency energy before directional balancing.
    public let isotropicScore: Double
    /// Direction-balanced high-frequency energy.
    public let directionalScore: Double
    /// Metal GPU, CPU fallback, or failed.
    public let backend: FocusBackend
    /// Normalized region containing the sharpest blocks, when available.
    public var focusRect: FocusRect?
    /// Local Vision subject classification, filled by the app after analysis.
    public var subject: SubjectPrediction?
    /// Image size actually used by the analyzer.
    public let analyzedWidth: Int
    public let analyzedHeight: Int
    /// A short, user-presentable reason when analysis failed.
    public let errorMessage: String?

    public var id: URL { url }

    public init(
        url: URL,
        fileName: String,
        fileSize: Int64,
        captureDate: Date?,
        pixelWidth: Int,
        pixelHeight: Int,
        rawScore: Double,
        isotropicScore: Double = 0,
        directionalScore: Double = 0,
        backend: FocusBackend = .cpu,
        focusRect: FocusRect? = nil,
        subject: SubjectPrediction? = nil,
        analyzedWidth: Int = 0,
        analyzedHeight: Int = 0,
        errorMessage: String? = nil
    ) {
        self.url = url
        self.fileName = fileName
        self.fileSize = fileSize
        self.captureDate = captureDate
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.rawScore = rawScore
        self.isotropicScore = isotropicScore
        self.directionalScore = directionalScore
        self.backend = backend
        self.focusRect = focusRect
        self.subject = subject
        self.analyzedWidth = analyzedWidth
        self.analyzedHeight = analyzedHeight
        self.errorMessage = errorMessage
    }

    public var hasError: Bool { errorMessage != nil }
    public var isRAW: Bool { PhotoFileType.isRAW(url) }
}

public enum PhotoFileType {
    public static let rawExtensions: Set<String> = [
        "dng", "cr2", "cr3", "nef", "nrw", "arw", "srf", "sr2",
        "raf", "orf", "rw2", "pef", "srw", "raw", "3fr", "erf",
        "mef", "mos", "mrw", "x3f", "iiq", "rwl"
    ]

    public static let standardExtensions: Set<String> = [
        "jpg", "jpeg", "jpe", "heic", "heif", "hif", "png", "tif", "tiff",
        "webp", "bmp", "gif"
    ]

    public static var supportedExtensions: Set<String> {
        rawExtensions.union(standardExtensions)
    }

    public static func isRAW(_ url: URL) -> Bool {
        rawExtensions.contains(url.pathExtension.lowercased())
    }

    public static func isSupported(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if supportedExtensions.contains(ext) {
            return true
        }

        // Camera makers occasionally introduce a new extension before it is
        // added to our list (Canon .HIF is a recent example). For unknown
        // extensions, let ImageIO sniff the file rather than silently skip it.
        guard !ext.isEmpty,
              let source = CGImageSourceCreateWithURL(url as CFURL, [
                  kCGImageSourceShouldCache: false
              ] as CFDictionary) else {
            return false
        }
        return CGImageSourceGetCount(source) > 0
    }
}

/// Batch-level normalization and automatic blur threshold estimation.
public struct SharpnessBatch: Sendable {
    /// Scores in the same order as the input array, normalized to 0...100.
    public let scores: [Double]
    /// The suggested threshold on the normalized scale.
    public let autoThreshold: Double
    /// 90th-percentile raw score used as the 100-point reference.
    public let referenceRawScore: Double
    /// Highest raw score in the batch.
    public let maximumRawScore: Double
    /// True when every image in the batch is soft, so relative scoring is unreliable.
    public let allSoftWarning: Bool

    public init(
        scores: [Double],
        autoThreshold: Double,
        referenceRawScore: Double,
        maximumRawScore: Double,
        allSoftWarning: Bool
    ) {
        self.scores = scores
        self.autoThreshold = autoThreshold
        self.referenceRawScore = referenceRawScore
        self.maximumRawScore = maximumRawScore
        self.allSoftWarning = allSoftWarning
    }
}

public enum SharpnessScoring {
    /// Raw peak-variance values below this are considered soft even for the best
    /// frame in a batch. Calibrated against downsampled, pre-blurred images.
    public static let absoluteSoftFloor: Double = 120

    public static func makeBatch(rawScores: [Double]) -> SharpnessBatch {
        let clean = rawScores.map { $0.isFinite ? max(0, $0) : 0 }
        guard !clean.isEmpty else {
            return SharpnessBatch(
                scores: [],
                autoThreshold: 35,
                referenceRawScore: 0,
                maximumRawScore: 0,
                allSoftWarning: true
            )
        }

        let reference = max(percentile(clean, 0.90), 0.000_001)
        let maximum = clean.max() ?? 0
        let normalized = clean.map { raw -> Double in
            min(100, max(0, 100 * raw / reference))
        }

        let auto = suggestedThreshold(for: normalized)
        let warning = maximum < absoluteSoftFloor

        return SharpnessBatch(
            scores: normalized,
            autoThreshold: auto,
            referenceRawScore: reference,
            maximumRawScore: maximum,
            allSoftWarning: warning
        )
    }

    /// Finds a convincing gap in a mostly bimodal score distribution. Falls back
    /// to a conservative fixed threshold when there is no clear separation.
    public static func suggestedThreshold(for scores: [Double]) -> Double {
        let sorted = scores.sorted()
        guard sorted.count >= 3 else {
            return sorted.first.map { $0 < 20 ? 25.0 : 50.0 } ?? 50
        }

        var bestGap = 0.0
        var bestIndex = -1
        for index in 1..<sorted.count {
            // Ignore a completely clipped top end as a split candidate.
            let gap = sorted[index] - sorted[index - 1]
            if gap > bestGap {
                bestGap = gap
                bestIndex = index
            }
        }

        let lowerCount = bestIndex
        let upperCount = sorted.count - bestIndex
        let lowerMean = bestIndex > 0
            ? sorted[0..<bestIndex].reduce(0, +) / Double(bestIndex)
            : 0
        let upperMean = sorted[bestIndex..<sorted.count].reduce(0, +) / Double(upperCount)

        // A real culling split needs a visible gap and enough images on both
        // sides. Otherwise keep the stable default so that sharp sets stay green.
        if bestGap >= 24,
           lowerCount >= 1,
           upperCount >= 1,
           lowerMean <= 72,
           upperMean >= 52,
           upperMean - lowerMean >= 28 {
            let midpoint = (sorted[bestIndex - 1] + sorted[bestIndex]) / 2
            return min(60, max(12, midpoint.rounded()))
        }
        return 50
    }

    public static func percentile(_ values: [Double], _ fraction: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        if sorted.count == 1 { return sorted[0] }
        let clamped = min(1, max(0, fraction))
        let position = clamped * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(sorted.count - 1, lower + 1)
        let weight = position - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }

    public static func formattedScore(_ score: Double) -> String {
        String(format: "%.0f", score.rounded())
    }
}
