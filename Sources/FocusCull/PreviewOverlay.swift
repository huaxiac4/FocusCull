import AppKit
import FocusCullCore
import SwiftUI

struct PreviewOverlay: View {
    @ObservedObject var model: AppModel
    @EnvironmentObject private var settings: AppSettings

    @State private var image: NSImage?
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var isHoveringImage = false
    @State private var exifInfo: ExifInfo?
    @State private var isLoadingEXIF = false
    @State private var zoomScale: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var scrollMonitor: Any?

    private var photo: PhotoItem? { model.previewPhoto }

    private var statusColor: Color {
        guard let photo else { return Theme.blur }
        return Theme.statusColor(isSharp: photo.isSharp, isFailed: photo.isFailed)
    }

    var body: some View {
        GeometryReader { proxy in
            let contentHeight = max(360, proxy.size.height - 160)

            ZStack {
                previewBackground

                if let photo {
                    VStack(spacing: 0) {
                        topBar(photo)
                            .padding(.horizontal, 14)
                            .padding(.top, 12)

                        HStack(spacing: 12) {
                            imageArea(photo)
                                .layoutPriority(1)
                            if settings.showEXIF {
                                EXIFPanel(
                                    info: exifInfo,
                                    isLoading: isLoadingEXIF,
                                    onCopy: copyEXIF
                                )
                                .frame(width: 340)
                                .frame(maxHeight: .infinity)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: contentHeight)
                        .padding(.horizontal, 14)
                        .padding(.top, 10)

                        bottomBar(photo)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 12)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .transition(.opacity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .environment(\.colorScheme, .dark)
        .onExitCommand {
            model.closePreview()
        }
        .task(id: photo?.id) {
            await loadImage()
        }
        .task(id: photo?.id) {
            await loadEXIF()
        }
        .onAppear {
            installScrollMonitor()
        }
        .onDisappear {
            removeScrollMonitor()
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: settings.showEXIF)
    }

    private var previewBackground: some View {
        ZStack {
            Color.black
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 54)
                    .opacity(0.42)
                    .clipped()
            }
            Color.black.opacity(0.44)
            LinearGradient(
                colors: [.black.opacity(0.24), .clear, .black.opacity(0.34)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private func topBar(_ photo: PhotoItem) -> some View {
        HStack(spacing: 11) {
            Button {
                model.closePreview()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.11), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .help("关闭 (Esc)")

            VStack(alignment: .leading, spacing: 2) {
                Text(photo.analysis.fileName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(abbreviatedPath(photo.analysis.url.deletingLastPathComponent()))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            FocusStatusPill(isSharp: photo.isSharp, isFailed: photo.isFailed)

            if let subject = photo.analysis.subject, subject.subject != .unknown {
                Label(subject.subject.title, systemImage: subject.subject.symbolName)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Theme.accent.opacity(0.12), in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.18), lineWidth: 1))
                    .help("AI 主体：\(subject.identifier) · \(subject.confidenceText)")
            }

            Button {
                model.toggleSelection(photo)
            } label: {
                Label(
                    model.isSelected(photo) ? "已选择" : "选择",
                    systemImage: model.isSelected(photo) ? "checkmark.circle.fill" : "checkmark.circle"
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(model.isSelected(photo) ? Theme.accent : .white.opacity(0.85))
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(.white.opacity(0.09), in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                model.chooseAppend()
            } label: {
                Label("追加", systemImage: "plus")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.09), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("追加更多照片或文件夹")

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    settings.showEXIF.toggle()
                }
            } label: {
                Image(systemName: settings.showEXIF ? "sidebar.right" : "info.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(settings.showEXIF ? Theme.accent : .white.opacity(0.82))
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.09), in: Circle())
            }
            .buttonStyle(.plain)
            .help(settings.showEXIF ? "隐藏 EXIF 信息" : "显示完整 EXIF 信息")

            Button {
                model.revealInFinder(photo)
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.09), in: Circle())
            }
            .buttonStyle(.plain)
            .help("在 Finder 中显示")

            Button {
                model.requestDelete(url: photo.id, mode: .trash)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.danger)
                    .frame(width: 30, height: 30)
                    .background(Theme.danger.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
            .help("移到废纸篓")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .glassPanel(
            cornerRadius: 22,
            tint: Color.black.opacity(0.16),
            interactive: true
        )
    }

    private func imageArea(_ photo: PhotoItem) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.001))
                .glassPanel(
                    cornerRadius: 26,
                    tint: Color.black.opacity(0.12),
                    interactive: true,
                    shadow: false
                )

            if let image {
                ZoomablePhotoContent(
                    image: image,
                    photo: photo,
                    showFocusBox: settings.showFocusBox,
                    hoverMagnification: settings.hoverMagnification,
                    zoomScale: $zoomScale,
                    panOffset: $panOffset
                )
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .transition(.opacity.animation(.easeOut(duration: 0.18)))
            } else if loadFailed {
                VStack(spacing: 10) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 44, weight: .light))
                    Text("无法读取这张照片")
                        .font(.system(size: 13))
                }
                .foregroundStyle(.white.opacity(0.55))
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }

            HStack {
                navigationButton(systemImage: "chevron.left", help: "上一张 (←)") {
                    model.showPreviousPreview()
                }
                .keyboardShortcut(.leftArrow, modifiers: [])

                Spacer()

                navigationButton(systemImage: "chevron.right", help: "下一张 (→)") {
                    model.showNextPreview()
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
            }
            .padding(.horizontal, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(.white.opacity(0.09), lineWidth: 1)
        )
    }

    private func navigationButton(
        systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .frame(width: 42, height: 58)
                .glassPanel(
                    cornerRadius: 14,
                    tint: Color.black.opacity(0.18),
                    interactive: true,
                    shadow: false
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func bottomBar(_ photo: PhotoItem) -> some View {
        HStack(spacing: 15) {
            scoreRing(photo)

            VStack(alignment: .leading, spacing: 4) {
                FocusStatusPill(isSharp: photo.isSharp, isFailed: photo.isFailed)
                Text(photo.isFailed
                     ? (photo.analysis.errorMessage ?? "无法分析")
                     : "清晰度 \(photo.scoreText) / 100 · 阈值 \(model.thresholdText)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.50))
                    .lineLimit(1)
            }

            Divider()
                .overlay(.white.opacity(0.14))
                .frame(height: 34)

            meta(label: "尺寸", value: AppModel.formattedDimensions(photo.analysis.pixelWidth, photo.analysis.pixelHeight))
            meta(label: "文件大小", value: AppModel.formattedFileSize(photo.analysis.fileSize))
            meta(label: "拍摄时间", value: AppModel.formattedDate(photo.analysis.captureDate))
            meta(
                label: "分析引擎",
                value: photo.analysis.backend.displayName
                    + (photo.analysis.subject != nil ? " + Neural Engine" : "")
            )

            Spacer(minLength: 4)

            Toggle(isOn: $settings.showFocusBox) {
                Text("合焦框")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.74))
            }
            .toggleStyle(.checkbox)
            .help("在画面中标记检测到的合焦区域")

            zoomIndicator

            hoverZoomControl

            Text("滚轮缩放 · ← →")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.28))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .glassPanel(
            cornerRadius: 22,
            tint: Color.black.opacity(0.14),
            interactive: true
        )
    }

    private var zoomIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
            Text(String(format: "%.1f×", Double(zoomScale)))
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.60))
                .frame(width: 32, alignment: .trailing)
            if zoomScale > 1.01 {
                Button {
                    zoomScale = 1
                    panOffset = .zero
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
                .help("重置缩放")
            }
        }
        .help("鼠标滚轮缩放，放大后可拖动平移")
    }

    private var hoverZoomControl: some View {
        HStack(spacing: 7) {
            Image(systemName: "plus.magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))

            Slider(
                value: Binding(
                    get: { settings.hoverMagnification },
                    set: { settings.hoverMagnification = (($0 * 100).rounded() / 100) }
                ),
                in: 1.0...1.2
            )
            .frame(width: 102)
            .controlSize(.mini)
            .tint(Theme.accent)

            Text(settings.hoverMagnificationText)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.58))
                .frame(width: 37, alignment: .trailing)
        }
        .help("鼠标悬停在图片上时的自动放大倍率")
    }

    private func scoreRing(_ photo: PhotoItem) -> some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.12), lineWidth: 4)
            Circle()
                .trim(from: 0, to: min(1, max(0, photo.score / 100)))
                .stroke(statusColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(photo.scoreText)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .frame(width: 50, height: 50)
    }

    private func meta(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8.5))
                .foregroundStyle(.white.opacity(0.38))
            Text(value)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
        }
    }

    private func abbreviatedPath(_ url: URL) -> String {
        url.path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
    }

    private func loadImage() async {
        guard let url = photo?.id else { return }
        isLoading = true
        loadFailed = false
        image = nil
        isHoveringImage = false
        zoomScale = 1
        panOffset = .zero

        let loaded = await ThumbnailStore.shared.image(
            for: url,
            maxPixel: 3200,
            preferEmbedded: true
        )
        guard !Task.isCancelled else { return }
        image = loaded
        loadFailed = loaded == nil
        isLoading = false
    }

    private func loadEXIF() async {
        guard let url = photo?.id else {
            exifInfo = nil
            return
        }
        isLoadingEXIF = true
        exifInfo = nil
        let info = await Task.detached(priority: .utility) {
            ExifReader.read(url: url)
        }.value
        guard !Task.isCancelled else { return }
        exifInfo = info
        isLoadingEXIF = false
    }

    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard model.previewPhoto != nil,
                  let window = event.window,
                  window == NSApp.keyWindow else {
                return event
            }
            let contentWidth = window.contentView?.bounds.width ?? 0
            let panelWidth: CGFloat = settings.showEXIF ? 354 : 0
            guard event.locationInWindow.x < contentWidth - panelWidth else {
                return event
            }
            let delta = event.hasPreciseScrollingDeltas
                ? event.scrollingDeltaY
                : event.scrollingDeltaY * 6
            let factor = exp(delta * 0.006)
            zoomScale = min(8, max(1, zoomScale * factor))
            if zoomScale <= 1.001 {
                panOffset = .zero
            }
            return nil
        }
    }

    private func removeScrollMonitor() {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
        }
        scrollMonitor = nil
    }

    private func copyEXIF() {
        guard let exifInfo, !exifInfo.plainText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(exifInfo.plainText, forType: .string)
        model.showToast("已复制 EXIF 信息", systemImage: "doc.on.doc", kind: .success)
    }
}

private struct EXIFPanel: View {
    let info: ExifInfo?
    let isLoading: Bool
    let onCopy: () -> Void

    private var entryCount: Int {
        info?.sections.reduce(0) { $0 + $1.entries.count } ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "camera.metering.center.weighted")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("EXIF")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                if entryCount > 0 {
                    Text("\(entryCount)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.42))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.07), in: Capsule())
                }
                Spacer()
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 24, height: 24)
                        .background(.white.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(info == nil)
                .help("复制全部 EXIF 信息")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()
                .overlay(.white.opacity(0.10))

            if isLoading {
                VStack(spacing: 9) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text("正在读取 EXIF…")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.42))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let info, !info.sections.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(info.sections) { section in
                            sectionView(section)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                }
                .scrollIndicators(.automatic)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "text.badge.xmark")
                        .font(.system(size: 24, weight: .light))
                    Text("没有读取到 EXIF 信息")
                        .font(.system(size: 10.5))
                }
                .foregroundStyle(.white.opacity(0.38))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .glassPanel(
            cornerRadius: 22,
            tint: Color.black.opacity(0.14),
            interactive: true
        )
    }

    private func sectionView(_ section: ExifSection) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(section.title)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Theme.accent.opacity(0.82))
                .textCase(.uppercase)
                .tracking(0.7)

            ForEach(section.entries) { entry in
                HStack(alignment: .top, spacing: 8) {
                    Text(entry.label)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.40))
                        .frame(width: 88, alignment: .leading)
                    Text(entry.value)
                        .font(.system(size: 10.2, weight: .medium))
                        .foregroundStyle(.white.opacity(0.86))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
