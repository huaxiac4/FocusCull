import AppKit
import FocusCullCore
import SwiftUI

struct PhotoBrowser: View {
    @ObservedObject var model: AppModel
    @EnvironmentObject private var settings: AppSettings

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: settings.thumbnailSize, maximum: settings.thumbnailSize * 1.28), spacing: 16, alignment: .top)]
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if model.allSoftWarning, model.sharpCount > 0 {
                    AllSoftBanner(model: model)
                }

                if model.filter == .all,
                   model.blurryCount == 0,
                   model.sharpCount > 0,
                   model.failedCount == 0 {
                    AllSharpBanner()
                }

                if model.sections.allSatisfy({ $0.photos.isEmpty }) {
                    emptyFilterState
                } else {
                    ForEach(model.sections) { section in
                        if !section.photos.isEmpty {
                            sectionView(section)
                        }
                    }
                }

                Color.clear
                    .frame(height: 28)
            }
            .padding(.horizontal, 22)
            .padding(.top, 208)
            .padding(.bottom, 74)
        }
        .id("\(model.filter.rawValue)-\(model.sortOrder.rawValue)-\(model.subjectFilter.rawValue)")
        .background(Color.clear)
    }

    @ViewBuilder
    private var emptyFilterState: some View {
        if model.subjectFilter != .all, model.filteredTotalCount == 0 {
            EmptyFilterView(
                icon: "sparkles",
                title: "没有识别为「\(model.subjectFilterTitle)」的照片",
                message: "可以清除 AI 主体筛选查看全部照片，或在设置中确认已启用主体识别。",
                actionTitle: "清除 AI 主体筛选",
                action: { model.subjectFilter = .all }
            )
        } else {
            switch model.filter {
        case .blurry:
            EmptyFilterView(
                icon: "checkmark.seal",
                title: "没有疑似失焦的照片",
                message: "当前阈值下，这组照片都达到了合焦标准。\n可以查看合焦照片，或拖动阈值滑块重新判定。",
                actionTitle: model.sharpCount > 0 ? "查看合焦照片" : nil,
                action: model.sharpCount > 0 ? { model.filter = .sharp } : nil
            )
        case .sharp:
            EmptyFilterView(
                icon: "exclamationmark.triangle",
                title: "没有合焦的照片",
                message: "所有照片都被判定为疑似失焦。\n建议先打开大图逐张确认，或降低判定阈值。",
                actionTitle: model.blurryCount > 0 ? "查看疑似失焦" : nil,
                action: model.blurryCount > 0 ? { model.filter = .blurry } : nil
            )
        case .all:
            EmptyFilterView(
                icon: model.totalCount == 0 ? "photo.on.rectangle.angled" : "line.3.horizontal.decrease.circle",
                title: model.totalCount == 0 ? "文件夹已经空了" : "没有可显示的照片",
                message: model.totalCount == 0
                    ? "照片已从文件夹中移除。可以重新扫描或打开另一个文件夹。"
                    : "请调整筛选条件或重新扫描文件夹。",
                actionTitle: "打开文件夹…",
                action: { model.chooseFolder() }
            )
            }
        }
    }

    private func sectionView(_ section: PhotoSection) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeader(
                section: section,
                threshold: model.thresholdText,
                allSelected: model.areAllSelected(section.photos),
                onToggleAll: { model.toggleSelection(for: section.photos) }
            )

            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                ForEach(section.photos) { photo in
                    PhotoCard(model: model, photo: photo)
                }
            }
        }
    }
}

private struct AllSoftBanner: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.blur)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text("整组照片的清晰度偏低")
                    .font(.system(size: 13, weight: .semibold))
                Text("本组最高分仍低于绝对清晰度参考值。可能整组都没有合焦，也可能画面本身反差较低。建议逐张预览确认。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if model.sharpCount > 0 {
                Button("全部标为失焦") {
                    model.markAllAsBlurry()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(14)
        .background(Theme.blur.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.blur.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct AllSharpBanner: View {
    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.sharp)
            VStack(alignment: .leading, spacing: 3) {
                Text("这组照片没有明显失焦")
                    .font(.system(size: 13, weight: .semibold))
                Text("当前清晰度分布比较一致，没有发现明显掉队的画面。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Theme.sharp.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.sharp.opacity(0.20), lineWidth: 1)
        )
    }
}

private struct SectionHeader: View {
    let section: PhotoSection
    let threshold: String
    let allSelected: Bool
    let onToggleAll: () -> Void

    private var color: Color {
        switch section.kind {
        case .blurry: return Theme.blur
        case .sharp: return Theme.sharp
        case .failed: return Theme.failed
        }
    }

    private var subtitle: String {
        switch section.kind {
        case .blurry:
            return "清晰度低于 \(threshold)，建议逐张确认"
        case .sharp:
            return "清晰度达到 \(threshold)"
        case .failed:
            return "文件可能损坏，或格式暂不受支持"
        }
    }

    private var icon: String {
        switch section.kind {
        case .blurry: return "exclamationmark.circle.fill"
        case .sharp: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
            Text(section.title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            Text("\(section.photos.count)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(color.opacity(0.12), in: Capsule())
            Text(subtitle)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 12)
            if section.kind != .failed {
                Button {
                    onToggleAll()
                } label: {
                    Label(
                        allSelected ? "取消选择" : "全选此组",
                        systemImage: allSelected ? "checkmark.circle.fill" : "checkmark.circle"
                    )
                    .font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(allSelected ? color : Color.secondary)
            }
        }
        .padding(.bottom, 1)
    }
}

private struct PhotoCard: View {
    @ObservedObject var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    let photo: PhotoItem

    @State private var isHovering = false

    private var statusColor: Color {
        Theme.statusColor(isSharp: photo.isSharp, isFailed: photo.isFailed)
    }

    private var isSelected: Bool {
        model.selectedURLs.contains(photo.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                PhotoThumbnail(url: photo.id, maxPixel: 720)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                LinearGradient(
                    colors: [.black.opacity(0.30), .clear, .clear, .black.opacity(0.22)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                VStack {
                    HStack(alignment: .top) {
                        selectionIndicator
                        Spacer()
                        scoreBadge
                    }
                    Spacer()
                    if isHovering, !photo.isFailed {
                        HStack {
                            Spacer()
                            Label("双击查看大图", systemImage: "eye")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(.black.opacity(0.52), in: Capsule())
                        }
                        .transition(.opacity)
                    }
                }
                .padding(9)

                if photo.isFailed {
                    VStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.failed)
                        Text(photo.analysis.errorMessage ?? "无法分析")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, 14)
                    }
                    .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: max(120, settings.thumbnailSize * 0.75))
            .clipped()

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(photo.analysis.fileName)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 4) {
                        Text(AppModel.formattedDimensions(photo.analysis.pixelWidth, photo.analysis.pixelHeight))
                        Text("·")
                        Text(AppModel.formattedFileSize(photo.analysis.fileSize))
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                }
                Spacer(minLength: 4)
                if let subject = photo.analysis.subject, subject.subject != .unknown {
                    Image(systemName: subject.subject.symbolName)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .help("AI 主体：\(subject.subject.title)（\(subject.confidenceText)）")
                }
                FocusStatusPill(isSharp: photo.isSharp, isFailed: photo.isFailed, compact: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
        }
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isSelected ? Theme.accent : Color.primary.opacity(isHovering ? 0.16 : 0.07),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .shadow(
            color: .black.opacity(isSelected ? 0.16 : (isHovering ? 0.14 : 0.05)),
            radius: isSelected ? 10 : (isHovering ? 9 : 3),
            y: isSelected ? 4 : (isHovering ? 4 : 1)
        )
        .scaleEffect(isHovering ? settings.hoverMagnification : 1)
        .zIndex(isHovering ? 10 : 0)
        .animation(.spring(response: 0.26, dampingFraction: 0.82), value: isHovering)
        .animation(.easeOut(duration: 0.16), value: isSelected)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .gesture(
            TapGesture(count: 2)
                .onEnded { model.openPreview(photo) }
                .exclusively(
                    before: TapGesture(count: 1)
                        .onEnded { model.toggleSelection(photo) }
                )
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .help("\(photo.analysis.fileName)\n清晰度 \(photo.scoreText)\n单击选择，双击查看大图")
        .contextMenu {
            Button("查看大图") { model.openPreview(photo) }
            Button(isSelected ? "取消选择" : "选择") { model.toggleSelection(photo) }
            Divider()
            Button("在 Finder 中显示") { model.revealInFinder(photo) }
            Divider()
            Button("移到废纸篓", role: .destructive) {
                model.requestDelete(url: photo.id, mode: .trash)
            }
            Button("永久删除…", role: .destructive) {
                model.requestDelete(url: photo.id, mode: .permanent)
            }
        }
    }

    private var selectionIndicator: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Theme.accent : Color.black.opacity(0.42))
            Circle()
                .strokeBorder(.white.opacity(0.80), lineWidth: 1.2)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 23, height: 23)
        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
        .accessibilityHidden(true)
    }

    private var scoreBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor)
                .frame(width: 5, height: 5)
            Text(photo.scoreText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.black.opacity(0.55), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1))
        .help(photo.isFailed ? "无法分析" : "清晰度 \(photo.scoreText) / 100")
    }
}
