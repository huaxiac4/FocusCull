import Foundation

struct FocusBlock: Sendable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
    let combined: Double
    let directional: Double
}

enum FocusBlockScoring {
    static func scores(
        blocks: [FocusBlock],
        topFraction: Double
    ) -> (isotropic: Double, directional: Double, combined: Double) {
        guard !blocks.isEmpty else { return (0, 0, 0) }
        let topCount = min(
            blocks.count,
            max(10, Int((Double(blocks.count) * topFraction).rounded()))
        )
        var combined = blocks.map(\.combined)
        var directional = blocks.map(\.directional)
        combined.sort(by: >)
        directional.sort(by: >)
        let isotropicPeak = combined.prefix(topCount).reduce(0, +) / Double(topCount)
        let directionalPeak = directional.prefix(topCount).reduce(0, +) / Double(topCount)
        return (
            isotropicPeak,
            directionalPeak,
            isotropicPeak * 0.55 + directionalPeak * 0.45
        )
    }

    /// Finds a useful box around the sharpest cluster of blocks. The highest
    /// block is the anchor; nearby high-energy blocks are merged into its box.
    static func focusRect(
        blocks: [FocusBlock],
        imageWidth: Int,
        imageHeight: Int
    ) -> FocusRect? {
        guard !blocks.isEmpty, imageWidth > 0, imageHeight > 0 else { return nil }
        let sorted = blocks.sorted { $0.combined > $1.combined }
        guard let anchor = sorted.first, anchor.combined > 0 else { return nil }

        let maxDistance = Double(max(imageWidth, imageHeight)) * 0.36
        let anchorCenterX = Double(anchor.x) + Double(anchor.width) / 2
        let anchorCenterY = Double(anchor.y) + Double(anchor.height) / 2
        let threshold = anchor.combined * 0.28

        var minX = Double(anchor.x)
        var minY = Double(anchor.y)
        var maxX = Double(anchor.x + anchor.width)
        var maxY = Double(anchor.y + anchor.height)
        var included = 1

        for block in sorted.dropFirst() {
            guard block.combined >= threshold else { break }
            let centerX = Double(block.x) + Double(block.width) / 2
            let centerY = Double(block.y) + Double(block.height) / 2
            let distance = hypot(centerX - anchorCenterX, centerY - anchorCenterY)
            guard distance <= maxDistance else { continue }
            minX = min(minX, Double(block.x))
            minY = min(minY, Double(block.y))
            maxX = max(maxX, Double(block.x + block.width))
            maxY = max(maxY, Double(block.y + block.height))
            included += 1
            if included >= 48 { break }
        }

        // Expand a little so the box frames the subject rather than clipping it.
        let padX = Double(imageWidth) * 0.055 + 10
        let padY = Double(imageHeight) * 0.055 + 10
        minX = max(0, minX - padX)
        minY = max(0, minY - padY)
        maxX = min(Double(imageWidth), maxX + padX)
        maxY = min(Double(imageHeight), maxY + padY)

        // If the "sharp" energy is scattered across the whole frame, keep a
        // compact box around the anchor instead of a useless full-frame box.
        let maxBoxWidth = Double(imageWidth) * 0.78
        let maxBoxHeight = Double(imageHeight) * 0.78
        if maxX - minX > maxBoxWidth || maxY - minY > maxBoxHeight {
            let halfW = min(maxBoxWidth, Double(anchor.width) * 2.2) / 2
            let halfH = min(maxBoxHeight, Double(anchor.height) * 2.2) / 2
            minX = max(0, anchorCenterX - halfW - padX)
            maxX = min(Double(imageWidth), anchorCenterX + halfW + padX)
            minY = max(0, anchorCenterY - halfH - padY)
            maxY = min(Double(imageHeight), anchorCenterY + halfH + padY)
        }

        let width = max(1, maxX - minX)
        let height = max(1, maxY - minY)
        return FocusRect(
            x: minX / Double(imageWidth),
            y: minY / Double(imageHeight),
            width: min(1, width / Double(imageWidth)),
            height: min(1, height / Double(imageHeight))
        )
    }
}
