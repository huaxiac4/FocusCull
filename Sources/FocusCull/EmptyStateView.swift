import SwiftUI

struct EmptyStateView: View {
    @ObservedObject var model: AppModel
    let isDropTargeted: Bool
    @State private var showHelp = false

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    AppMark(size: 30)
                    Text("FocusCull")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("合焦筛选")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        showHelp = true
                    } label: {
                        Label("评分说明", systemImage: "questionmark.circle")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .popover(isPresented: $showHelp, arrowEdge: .bottom) {
                        ScoringHelpView()
                    }

                    SettingsLink {
                        Label("设置", systemImage: "gearshape")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("FocusCull 设置 (⌘,)")
                }
                .padding(.horizontal, 26)
                .padding(.top, 20)

                Spacer(minLength: 24)

                VStack(spacing: 26) {
                    VStack(spacing: 18) {
                        AppMark(size: 82)

                        VStack(spacing: 9) {
                            Text("把连拍交给 FocusCull")
                                .font(.system(size: 33, weight: .bold, design: .rounded))
                            Text("自动找出失焦的飞鸟与飞机照片，只留下真正合焦的瞬间。")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }

                    dropZone

                    HStack(spacing: 10) {
                        feature(
                            icon: "bolt.fill",
                            title: "批量分析",
                            text: "整组连拍一次载入"
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .glassPanel(cornerRadius: 16, shadow: false)

                        feature(
                            icon: "scope",
                            title: "失焦识别",
                            text: "细节 + 方向平衡"
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .glassPanel(cornerRadius: 16, shadow: false)

                        feature(
                            icon: "trash.slash.fill",
                            title: "安全清理",
                            text: "默认移到废纸篓"
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .glassPanel(cornerRadius: 16, shadow: false)
                    }
                    .frame(maxWidth: 650)

                    if let recent = model.recentFolderURL {
                        Button {
                            model.openFolder(recent)
                        } label: {
                            Label("继续上次：\(recent.lastPathComponent)", systemImage: "clock.arrow.circlepath")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help(recent.path)
                    }
                }
                .padding(.horizontal, 32)

                Spacer(minLength: 24)

                HStack(spacing: 7) {
                    Image(systemName: "lock.shield")
                    Text("照片只在本机分析，不会上传")
                    Text("·")
                    Text("FocusCull \(version)")
                }
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 18)
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Theme.accent)
                .symbolEffect(.bounce, value: isDropTargeted)

            VStack(spacing: 5) {
                Text("将照片文件夹拖到这里")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text("把一次拍摄的所有连拍照片放在同一个文件夹里")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Button {
                model.chooseFolder()
            } label: {
                Label("选择文件夹…", systemImage: "folder")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)

            HStack(spacing: 10) {
                Text("JPEG · HEIC · PNG · TIFF · DNG / NEF / CR3 等 RAW")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                Text("·")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.quaternary)
                Toggle(
                    "包含子文件夹",
                    isOn: Binding(
                        get: { model.includeSubfolders },
                        set: { model.setIncludeSubfolders($0) }
                    )
                )
                .toggleStyle(.checkbox)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 600)
        .padding(.vertical, 30)
        .glassPanel(
            cornerRadius: 28,
            tint: isDropTargeted ? Theme.accent.opacity(0.22) : nil,
            interactive: true
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? Theme.accent : Color.secondary.opacity(0.30),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2.5 : 1.5, dash: [8, 6])
                )
        )
        .scaleEffect(isDropTargeted ? 1.008 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isDropTargeted)
    }

    private func feature(icon: String, title: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 26, height: 26)
                .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(text)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }


}
