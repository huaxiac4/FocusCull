import AppKit
import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case focusCull
    case adobe
    case finalCut
    case davinci

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focusCull: return "FocusCull"
        case .adobe: return "Adobe"
        case .finalCut: return "Final Cut Pro"
        case .davinci: return "DaVinci"
        }
    }

    var subtitle: String {
        switch self {
        case .focusCull: return "薄荷绿 · 清爽玻璃"
        case .adobe: return "Adobe 蓝 · 冷调专业"
        case .finalCut: return "紫红 · 剪辑台氛围"
        case .davinci: return "橙色 · 调色台质感"
        }
    }

    var accent: Color {
        switch self {
        case .focusCull: return Color(red: 0.16, green: 0.78, blue: 0.62)
        case .adobe: return Color(red: 0.16, green: 0.49, blue: 0.92)
        case .finalCut: return Color(red: 1.00, green: 0.28, blue: 0.57)
        case .davinci: return Color(red: 0.95, green: 0.58, blue: 0.18)
        }
    }

    var accentDeep: Color {
        switch self {
        case .focusCull: return Color(red: 0.04, green: 0.52, blue: 0.42)
        case .adobe: return Color(red: 0.06, green: 0.24, blue: 0.58)
        case .finalCut: return Color(red: 0.60, green: 0.08, blue: 0.30)
        case .davinci: return Color(red: 0.57, green: 0.27, blue: 0.04)
        }
    }

    var secondary: Color {
        switch self {
        case .focusCull: return Color(red: 1.00, green: 0.67, blue: 0.22)
        case .adobe: return Color(red: 0.89, green: 0.27, blue: 0.31)
        case .finalCut: return Color(red: 0.20, green: 0.78, blue: 0.91)
        case .davinci: return Color(red: 0.10, green: 0.70, blue: 0.66)
        }
    }
}

enum Theme {
    static var currentTheme: AppTheme = .focusCull

    static var accent: Color { currentTheme.accent }
    static var accentDeep: Color { currentTheme.accentDeep }
    static var secondaryAccent: Color { currentTheme.secondary }

    static let sharp = Color(red: 0.30, green: 0.84, blue: 0.55)
    static let blur = Color(red: 1.00, green: 0.67, blue: 0.22)
    static let danger = Color(red: 0.96, green: 0.34, blue: 0.34)
    static let failed = Color(red: 0.92, green: 0.40, blue: 0.42)

    static var canvas: Color { Color(nsColor: .windowBackgroundColor) }
    static var panel: Color { Color(nsColor: .controlBackgroundColor) }
    static var elevated: Color { Color(nsColor: .underPageBackgroundColor) }

    static func statusColor(isSharp: Bool, isFailed: Bool) -> Color {
        if isFailed { return failed }
        return isSharp ? sharp : blur
    }
}

struct AppMark: View {
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Theme.accent, Theme.accentDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .strokeBorder(Color.white.opacity(0.22), lineWidth: max(1, size * 0.025))
                .frame(width: size * 0.68, height: size * 0.68)
            Image(systemName: "camera.aperture")
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.accent.opacity(0.30), radius: size * 0.22, y: size * 0.08)
    }
}

struct CountBadge: View {
    let value: Int
    let title: String
    let color: Color
    let icon: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text("\(value)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(title)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(color.opacity(0.11), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.18), lineWidth: 1))
    }
}

struct FocusStatusPill: View {
    let isSharp: Bool
    let isFailed: Bool
    var compact = false

    private var color: Color {
        Theme.statusColor(isSharp: isSharp, isFailed: isFailed)
    }

    private var title: String {
        if isFailed { return "无法分析" }
        return isSharp ? "合焦" : "疑似失焦"
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: compact ? 5 : 6, height: compact ? 5 : 6)
            Text(title)
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, compact ? 7 : 9)
        .padding(.vertical, compact ? 3 : 5)
        .background(color.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.16), lineWidth: 1))
    }
}

struct PhotoThumbnail: View {
    let url: URL
    var maxPixel: Int = 640
    var contentMode: ContentMode = .fill

    @State private var image: NSImage?
    @State private var didFail = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.16)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity.animation(.easeOut(duration: 0.18)))
            } else if didFail {
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 26, weight: .light))
                    Text("无法读取")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .clipped()
        .task(id: url) {
            image = nil
            didFail = false
            let loaded = await ThumbnailStore.shared.image(for: url, maxPixel: maxPixel)
            guard !Task.isCancelled else { return }
            image = loaded
            didFail = loaded == nil
        }
    }
}

struct ToastView: View {
    let message: ToastMessage

    private var tint: Color {
        switch message.kind {
        case .success: return Theme.sharp
        case .info: return Theme.accent
        case .warning: return Theme.blur
        }
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: message.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
            Text(message.text)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
    }
}

struct ScoringHelpView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("清晰度是怎么算的？", systemImage: "sparkles")
                .font(.system(size: 14, weight: .semibold))
            Text("FocusCull 会把每张照片缩到统一尺寸，分析画面各区域的高频细节，并检查水平与垂直方向的细节是否平衡。这样既能发现整体虚焦，也能发现连拍中常见的单向运动模糊。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Text("分数是相对于本批照片中最清晰的一组归一化的，满分 100。不同批次之间不要直接比较分数。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Label("删除前建议先预览确认。默认移到废纸篓，可随时恢复。", systemImage: "trash")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 340)
    }
}

struct EmptyFilterView: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.accent.opacity(0.9))
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.large)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }
}
