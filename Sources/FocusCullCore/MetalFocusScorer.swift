import Foundation
import Metal

public struct MetalFocusResult: Sendable {
    public let score: Double
    public let isotropicScore: Double
    public let directionalScore: Double
    public let focusRect: FocusRect?
}

/// GPU implementation of the local Laplacian focus metric.
///
/// The CPU prepares a downsampled 8-bit grayscale buffer, then Metal computes
/// the binomial blur and the per-block horizontal/vertical second-derivative
/// statistics. Top-percentile selection is done on the CPU because it only
/// touches a couple of thousand block values.
public final class MetalFocusScorer: @unchecked Sendable {
    public static let shared: MetalFocusScorer? = MetalFocusScorer()

    public static var isAvailable: Bool { shared != nil }

    public static var deviceDescription: String {
        shared?.device.name ?? "不可用"
    }

    public let device: MTLDevice
    private let queue: MTLCommandQueue
    private let blurPipeline: MTLComputePipelineState
    private let blockPipeline: MTLComputePipelineState

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            return nil
        }

        do {
            let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            guard let blurFunction = library.makeFunction(name: "focusBlur"),
                  let blockFunction = library.makeFunction(name: "focusBlocks") else {
                return nil
            }
            let blurPipeline = try device.makeComputePipelineState(function: blurFunction)
            let blockPipeline = try device.makeComputePipelineState(function: blockFunction)

            self.device = device
            self.queue = queue
            self.blurPipeline = blurPipeline
            self.blockPipeline = blockPipeline
        } catch {
            return nil
        }
    }

    public func score(
        gray: [UInt8],
        width: Int,
        height: Int,
        blockSize: Int,
        blockStride: Int,
        topFraction: Double
    ) -> MetalFocusResult? {
        guard width > 2, height > 2, gray.count == width * height else { return nil }
        let grid = Self.blockGrid(
            width: width,
            height: height,
            blockSize: blockSize,
            blockStride: blockStride
        )
        guard grid.x > 0, grid.y > 0 else { return nil }

        let grayLength = gray.count
        let blurredLength = width * height * MemoryLayout<Float>.stride
        let statsCount = grid.x * grid.y
        let statsLength = statsCount * MemoryLayout<SIMD2<Float>>.stride

        guard let grayBuffer = device.makeBuffer(
            bytes: gray,
            length: grayLength,
            options: .storageModeShared
        ),
        let blurredBuffer = device.makeBuffer(
            length: blurredLength,
            options: .storageModeShared
        ),
        let statsBuffer = device.makeBuffer(
            length: statsLength,
            options: .storageModeShared
        ) else {
            return nil
        }

        guard let commandBuffer = queue.makeCommandBuffer() else { return nil }

        // Pass 1: grayscale -> separable-quality 3x3 binomial blur.
        guard let blurEncoder = commandBuffer.makeComputeCommandEncoder() else { return nil }
        blurEncoder.setComputePipelineState(blurPipeline)
        blurEncoder.setBuffer(grayBuffer, offset: 0, index: 0)
        blurEncoder.setBuffer(blurredBuffer, offset: 0, index: 1)
        setUInt32(UInt32(width), at: 2, on: blurEncoder)
        setUInt32(UInt32(height), at: 3, on: blurEncoder)
        let threads = MTLSize(width: 16, height: 16, depth: 1)
        let blurGroups = MTLSize(
            width: (width + 15) / 16,
            height: (height + 15) / 16,
            depth: 1
        )
        blurEncoder.dispatchThreadgroups(blurGroups, threadsPerThreadgroup: threads)
        blurEncoder.endEncoding()

        // Pass 2: per-block second-derivative variances.
        guard let blockEncoder = commandBuffer.makeComputeCommandEncoder() else { return nil }
        blockEncoder.setComputePipelineState(blockPipeline)
        blockEncoder.setBuffer(blurredBuffer, offset: 0, index: 0)
        blockEncoder.setBuffer(statsBuffer, offset: 0, index: 1)
        setUInt32(UInt32(width), at: 2, on: blockEncoder)
        setUInt32(UInt32(height), at: 3, on: blockEncoder)
        setUInt32(UInt32(blockSize), at: 4, on: blockEncoder)
        setUInt32(UInt32(blockStride), at: 5, on: blockEncoder)
        setUInt32(UInt32(grid.x), at: 6, on: blockEncoder)
        let blockGroups = MTLSize(
            width: (grid.x + 15) / 16,
            height: (grid.y + 15) / 16,
            depth: 1
        )
        blockEncoder.dispatchThreadgroups(blockGroups, threadsPerThreadgroup: threads)
        blockEncoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.error == nil else { return nil }

        let stats = statsBuffer.contents().bindMemory(
            to: SIMD2<Float>.self,
            capacity: statsCount
        )

        var blocks: [FocusBlock] = []
        blocks.reserveCapacity(statsCount)
        for y in 0..<grid.y {
            for x in 0..<grid.x {
                let value = stats[y * grid.x + x]
                let varianceX = Double(max(0, value.x))
                let varianceY = Double(max(0, value.y))
                blocks.append(FocusBlock(
                    x: 1 + x * blockStride,
                    y: 1 + y * blockStride,
                    width: blockSize,
                    height: blockSize,
                    combined: varianceX + varianceY,
                    directional: (varianceX * varianceY).squareRoot()
                ))
            }
        }

        let scores = FocusBlockScoring.scores(blocks: blocks, topFraction: topFraction)
        let focusRect = FocusBlockScoring.focusRect(
            blocks: blocks,
            imageWidth: width,
            imageHeight: height
        )

        return MetalFocusResult(
            score: scores.combined,
            isotropicScore: scores.isotropic,
            directionalScore: scores.directional,
            focusRect: focusRect
        )
    }

    public static func blockGrid(
        width: Int,
        height: Int,
        blockSize: Int,
        blockStride: Int
    ) -> (x: Int, y: Int) {
        guard width > blockSize + 1, height > blockSize + 1 else { return (0, 0) }
        let x = (width - blockSize - 2) / blockStride + 1
        let y = (height - blockSize - 2) / blockStride + 1
        return (max(0, x), max(0, y))
    }

    private func setUInt32(
        _ value: UInt32,
        at index: Int,
        on encoder: MTLComputeCommandEncoder
    ) {
        var mutable = value
        encoder.setBytes(&mutable, length: MemoryLayout<UInt32>.stride, index: index)
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    kernel void focusBlur(device const uchar *gray [[buffer(0)]],
                          device float *blurred [[buffer(1)]],
                          constant uint &width [[buffer(2)]],
                          constant uint &height [[buffer(3)]],
                          uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= width || gid.y >= height) {
            return;
        }
        float sum = 0.0f;
        for (int dy = -1; dy <= 1; ++dy) {
            int yy = clamp(int(gid.y) + dy, 0, int(height) - 1);
            for (int dx = -1; dx <= 1; ++dx) {
                int xx = clamp(int(gid.x) + dx, 0, int(width) - 1);
                int weight = (dx == 0 ? 2 : 1) * (dy == 0 ? 2 : 1);
                sum += float(gray[yy * int(width) + xx]) * float(weight);
            }
        }
        blurred[int(gid.y) * int(width) + int(gid.x)] = sum * (1.0f / 16.0f);
    }

    kernel void focusBlocks(device const float *blurred [[buffer(0)]],
                            device float2 *stats [[buffer(1)]],
                            constant uint &width [[buffer(2)]],
                            constant uint &height [[buffer(3)]],
                            constant uint &blockSize [[buffer(4)]],
                            constant uint &blockStride [[buffer(5)]],
                            constant uint &blocksX [[buffer(6)]],
                            uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= blocksX) {
            return;
        }
        uint blockX = 1 + gid.x * blockStride;
        uint blockY = 1 + gid.y * blockStride;
        if (blockX + blockSize >= width || blockY + blockSize >= height) {
            return;
        }

        float sumX = 0.0f;
        float sumX2 = 0.0f;
        float sumY = 0.0f;
        float sumY2 = 0.0f;
        for (uint y = blockY; y < blockY + blockSize; ++y) {
            uint row = y * width;
            for (uint x = blockX; x < blockX + blockSize; ++x) {
                uint index = row + x;
                float center = blurred[index];
                float dx = 2.0f * center - blurred[index - 1] - blurred[index + 1];
                float dy = 2.0f * center - blurred[index - width] - blurred[index + width];
                sumX += dx;
                sumX2 += dx * dx;
                sumY += dy;
                sumY2 += dy * dy;
            }
        }

        float count = float(blockSize * blockSize);
        float meanX = sumX / count;
        float meanY = sumY / count;
        float varianceX = max(0.0f, sumX2 / count - meanX * meanX);
        float varianceY = max(0.0f, sumY2 / count - meanY * meanY);
        stats[gid.y * blocksX + gid.x] = float2(varianceX, varianceY);
    }
    """
}
