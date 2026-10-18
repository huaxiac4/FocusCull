import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MenuBarPanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    @Environment(\.openWindow) private var openWindow

    @State private var isDropTargeted = false
    @State private var dropMessage: String?

    private var isScanning: Bool {
        model.phase.isScanning || model.appendProgress != nil
    }

    private var statusText: String {
        if case let .scanning(done, total) = model.phase {
            return "正在分析 \(done)/\(max(total, 0))"
        }
        if let progress = model.appendProgress {
            return "正在追加 \(progress.done)/\(max(progress.total, 0))"
        }
        if model.totalCount > 0 {
            return "\(model.totalCount) 张 · \(model.blurryCount) 张疑似失焦"
        }
        return "拖入照片或文件夹开始"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            dropZone

            if let dropMessage {
                Text(dropMessage)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.blur)
                    .lineLimit(2)
            }

            actionGrid

            if model.totalCount > 0 {
                summary
            }

            if let progress = model.appendProgress {
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
            } else if case let .scanning(done, total) = model.phase {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
            }

            Divider().opacity(0.55)
            footer
        }
        .padding(14)
        .frame(width: 350)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onReceive(NotificationCenter.default.publisher(for: .focusCullShowMainWindow)) { _ in
            showMain()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            AppMark(size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("FocusCull")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text(statusText)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button {
                showMain()
            } label: {
                Image(systemName: "macwindow")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("显示主窗口")
        }
    }

    private var dropZone: some View {
        VStack(spacing: 5) {
            Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "square.and.arrow.down")
                .font(.system(size: 23, weight: .light))
                .foregroundStyle(isDropTargeted ? Theme.accent : .secondary)

            Text(isDropTargeted ? "松手即可导入" : "拖入图片或文件夹")
                .font(.system(size: 11.5, weight: .semibold))

            Text("支持 JPEG / HEIC / RAW，或整个文件夹")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isDropTargeted ? Theme.accent.opacity(0.14) : Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? Theme.accent.opacity(0.85) : Color.primary.opacity(0.10),
                    style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
            return true
        }
    }

    private var actionGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)],
            spacing: 7
        ) {
            panelButton("打开文件夹…", icon: "folder") {
                model.chooseFolder()
                showMain()
            }
            panelButton("添加图片…", icon: "photo.badge.plus") {
                model.chooseImagesForMenu()
                showMain()
            }
            panelButton("添加文件夹…", icon: "folder.badge.plus") {
                model.chooseFoldersForMenu()
                showMain()
            }
            panelButton("显示主窗口", icon: "macwindow") {
                showMain()
            }
        }
        .disabled(isScanning)
    }

    private func panelButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 10.2, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var summary: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(model.blurryCount > 0 ? Theme.blur : Theme.sharp)
                .frame(width: 6, height: 6)
            Text("\(model.totalCount) 张照片")
                .font(.system(size: 10.2, weight: .medium))
            Text("·")
                .foregroundStyle(.tertiary)
            Text("\(model.blurryCount) 张疑似失焦")
                .font(.system(size: 10.2))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button("查看") { showMain() }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            SettingsLink {
                Label("设置…", systemImage: "gearshape")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("彻底退出 FocusCull", systemImage: "power")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.danger)
            .help("退出应用并移除菜单栏图标")
        }
    }

    private func showMain() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        if let window = NSApplication.shared.windows.first(where: {
            $0.title == "FocusCull" && !($0 is NSPanel)
        }) {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            return
        }

        openWindow(id: "main")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if let window = NSApplication.shared.windows.first(where: {
                $0.title == "FocusCull" && !($0 is NSPanel)
            }) {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        dropMessage = nil
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                if let url = await loadURL(from: provider) {
                    urls.append(url)
                }
            }

            guard !urls.isEmpty else {
                dropMessage = "没有读取到文件或文件夹"
                return
            }

            model.ingestFromMenu(urls: urls)
            showMain()
        }
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let nsurl = item as? NSURL {
                    continuation.resume(returning: nsurl as URL)
                } else if let data = item as? Data,
                          let string = String(data: data, encoding: .utf8),
                          let url = URL(string: string) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
