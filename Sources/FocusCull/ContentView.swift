import AppKit
import FocusCullCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @State private var isDropTargeted = false
    @State private var didAttemptRestore = false

    var body: some View {
        ZStack(alignment: .bottom) {
            LiquidBackground()

            Group {
                switch model.phase {
                case .empty:
                    EmptyStateView(model: model, isDropTargeted: isDropTargeted)
                case .scanning:
                    ScanningView(model: model)
                case .ready:
                    ReadyView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let toast = model.toast {
                ToastView(message: toast)
                    .padding(.bottom, 68)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
                    .zIndex(5)
            }

            if model.previewPhoto != nil {
                PreviewOverlay(model: model)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 3, dash: [10, 7]))
                    .padding(8)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .alert(item: $model.activeAlert) { alert in
            alertView(for: alert)
        }
        .navigationTitle(model.folderURL?.lastPathComponent ?? "FocusCull")
        .accentColor(Theme.accent)
        .animation(.easeInOut(duration: 0.2), value: isDropTargeted)
        .animation(.easeInOut(duration: 0.22), value: model.phase)
        .task {
            guard !didAttemptRestore else { return }
            didAttemptRestore = true
            guard settings.restoreLastFolder,
                  model.phase == .empty,
                  model.photos.isEmpty,
                  let recent = model.recentFolderURL else { return }
            model.openFolder(recent)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        let identifier = UTType.fileURL.identifier
        provider.loadItem(forTypeIdentifier: identifier, options: nil) { item, _ in
            var droppedURL: URL?
            if let data = item as? Data {
                droppedURL = URL(dataRepresentation: data, relativeTo: nil)
            } else if let url = item as? URL {
                droppedURL = url
            } else if let string = item as? String {
                droppedURL = URL(fileURLWithPath: string)
            }

            guard let droppedURL else { return }
            Task { @MainActor in
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: droppedURL.path, isDirectory: &isDirectory) else {
                    model.activeAlert = .error(title: "无法读取", message: "拖入的文件夹不存在或无法访问。")
                    return
                }
                guard isDirectory.boolValue else {
                    model.activeAlert = .error(
                        title: "请拖入文件夹",
                        message: "FocusCull 需要一次载入一个照片文件夹，而不是单张图片。"
                    )
                    return
                }
                model.openFolder(droppedURL)
            }
        }
        return true
    }

    private func alertView(for alert: AppAlert) -> Alert {
        switch alert {
        case let .noPhotos(folderName):
            return Alert(
                title: Text("没有找到照片"),
                message: Text("「\(folderName)」中没有 FocusCull 可以读取的照片。支持 JPEG、HEIC、PNG、TIFF 以及常见 RAW 格式。"),
                primaryButton: .default(Text("选择其他文件夹")) {
                    model.activeAlert = nil
                    model.chooseFolder()
                },
                secondaryButton: .cancel(Text("取消"))
            )
        case let .error(title, message):
            return Alert(
                title: Text(title),
                message: Text(message),
                dismissButton: .default(Text("好"))
            )
        case let .deleteTrash(count):
            return Alert(
                title: Text("把 \(count) 张照片移到废纸篓？"),
                message: Text("照片会从当前文件夹移到废纸篓，之后仍可从废纸篓恢复。"),
                primaryButton: .destructive(Text("移到废纸篓")) {
                    model.confirmPendingDeletion()
                },
                secondaryButton: .cancel(Text("取消"))
            )
        case let .deletePermanent(count):
            return Alert(
                title: Text("永久删除 \(count) 张照片？"),
                message: Text("此操作不可撤销，照片不会进入废纸篓。建议优先使用「移到废纸篓」。"),
                primaryButton: .destructive(Text("永久删除")) {
                    model.confirmPendingDeletion()
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }
}

private struct ReadyView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack(alignment: .top) {
            PhotoBrowser(model: model)

            GlassGroup(spacing: 10) {
                VStack(spacing: 10) {
                    FolderHeader(model: model)
                    ControlBar(model: model)
                    SubjectFilterBar(model: model)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            VStack {
                Spacer()
                StatusBar(model: model)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }

            if let progress = model.appendProgress {
                VStack(spacing: 10) {
                    ProgressView(
                        value: Double(progress.done),
                        total: Double(max(progress.total, 1))
                    )
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
                    .frame(width: 220)
                    Text("正在追加分析 \(progress.done) / \(progress.total)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
                .glassPanel(cornerRadius: 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .allowsHitTesting(false)
                .transition(.opacity)
                .zIndex(6)
            }
        }
    }
}

struct FolderHeader: View {
    @ObservedObject var model: AppModel
    @State private var showHelp = false

    var body: some View {
        HStack(spacing: 14) {
            AppMark(size: 42)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(model.displayFolderName)
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    if model.phase.isScanning {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                Text(model.currentFolderDisplayPath)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 16)

            if model.phase == .ready {
                HStack(spacing: 8) {
                    CountBadge(value: model.sharpCount, title: "合焦", color: Theme.sharp, icon: "checkmark.circle.fill")
                    CountBadge(value: model.blurryCount, title: "疑似失焦", color: Theme.blur, icon: "exclamationmark.circle.fill")
                }
                .transition(.opacity)
            }

            if model.phase.isScanning {
                Button("取消") {
                    model.cancelScan()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Button {
                model.chooseFolder()
            } label: {
                Label("打开文件夹", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help("打开另一个照片文件夹 (⌘O)")

            Button {
                model.rescan()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(model.phase.isScanning)
            .help("重新扫描当前文件夹 (⌘R)")

            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help("FocusCull 设置 (⌘,)")

            Menu {
                Button {
                    model.chooseAppend()
                } label: {
                    Label("追加照片或文件夹…", systemImage: "plus")
                }
                .disabled(model.phase != .ready)

                Button {
                    model.revealFolderInFinder()
                } label: {
                    Label("在 Finder 中显示文件夹", systemImage: "folder")
                }

                Divider()

                Toggle(
                    "包含子文件夹",
                    isOn: Binding(
                        get: { model.includeSubfolders },
                        set: { model.setIncludeSubfolders($0) }
                    )
                )

                Button {
                    model.rescan()
                } label: {
                    Label("重新扫描", systemImage: "arrow.clockwise")
                }
                .disabled(model.phase.isScanning)

                Divider()

                Button {
                    showHelp = true
                } label: {
                    Label("评分说明", systemImage: "questionmark.circle")
                }

                SettingsLink {
                    Label("设置…", systemImage: "gearshape")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 18, height: 18)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 26)
            .help("更多选项")
            .popover(isPresented: $showHelp, arrowEdge: .bottom) {
                ScoringHelpView()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassPanel(cornerRadius: 24, interactive: true)
    }
}

private struct ScanningView: View {
    @ObservedObject var model: AppModel

    private var progress: (done: Int, total: Int) {
        if case let .scanning(done, total) = model.phase { return (done, total) }
        return (0, 0)
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack {
                Spacer()

                VStack(spacing: 22) {
                    ZStack {
                        Circle()
                            .fill(Theme.accent.opacity(0.10))
                            .frame(width: 132, height: 132)
                        Circle()
                            .strokeBorder(Theme.accent.opacity(0.22), lineWidth: 1)
                            .frame(width: 104, height: 104)
                        Image(systemName: "camera.aperture")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(Theme.accent)
                            .symbolEffect(.pulse.byLayer, options: .repeating)
                    }

                    VStack(spacing: 7) {
                        Text(progress.total > 0 ? "正在分析照片" : "正在读取文件夹")
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                        Text(progress.total > 0
                             ? "正在计算每张照片的清晰度，原文件不会被修改。"
                             : "正在查找文件夹中的照片…")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 9) {
                        if progress.total > 0 {
                            ProgressView(
                                value: Double(progress.done),
                                total: Double(max(progress.total, 1))
                            )
                            .progressViewStyle(.linear)
                            .tint(Theme.accent)
                            .frame(width: 400)

                            HStack {
                                Text("\(progress.done) / \(progress.total)")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .monospacedDigit()
                                Spacer()
                                Text("\(Int(Double(progress.done) / Double(max(progress.total, 1)) * 100))%")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 400)
                        } else {
                            ProgressView()
                                .progressViewStyle(.linear)
                                .tint(Theme.accent)
                                .frame(width: 400)
                        }
                    }

                    Text("提示：分析结果会按本批照片相对排序，连拍组越大，判断越准确。")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)

                    Button("取消分析") {
                        model.cancelScan()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.horizontal, 52)
                .padding(.vertical, 38)
                .glassPanel(cornerRadius: 32)
                .frame(maxWidth: 520)

                Spacer()
            }
            .padding(.vertical, 40)

            FolderHeader(model: model)
                .padding(.horizontal, 14)
                .padding(.top, 12)
        }
    }
}

private struct StatusBar: View {
    @ObservedObject var model: AppModel
    @State private var showHelp = false

    private var statusColor: Color {
        if model.totalCount == 0 { return .secondary }
        if model.failedCount > 0 { return Theme.failed }
        if model.allSoftWarning || model.blurryCount > 0 { return Theme.blur }
        return Theme.sharp
    }

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(model.subjectFilter == .all
                 ? "\(model.totalCount) 张照片"
                 : "\(model.filteredTotalCount) / \(model.totalCount) 张照片")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            if model.subjectFilter != .all {
                Text("·")
                    .foregroundStyle(.quaternary)
                Label("AI：\(model.subjectFilterTitle)", systemImage: "sparkles")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }

            if model.failedCount > 0 {
                Text("·")
                    .foregroundStyle(.quaternary)
                Text("\(model.failedCount) 张无法读取")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.failed)
            }

            if model.analyzedDuration > 0 {
                Text("·")
                    .foregroundStyle(.quaternary)
                Text("分析用时 \(String(format: "%.1f", model.analyzedDuration)) 秒")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            if model.selectedCount > 0 {
                Text("·")
                    .foregroundStyle(.quaternary)
                Text("已选 \(model.selectedCount) 张 · \(AppModel.formattedFileSize(model.selectedFileSize))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }

            if model.analysisEngineSummary != "—" {
                Text("·")
                    .foregroundStyle(.quaternary)
                Label(model.analysisEngineSummary, systemImage: "cpu")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label("本机分析 · 照片不会上传", systemImage: "lock.shield")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            Button {
                showHelp = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("评分说明")
            .popover(isPresented: $showHelp, arrowEdge: .bottom) {
                ScoringHelpView()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .glassPanel(cornerRadius: 16)
    }
}
