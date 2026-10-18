import AppKit
import FocusCullCore
import SwiftUI
import UniformTypeIdentifiers

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case analysis
    case viewing
    case appearance
    case history
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .analysis: return "分析"
        case .viewing: return "浏览"
        case .appearance: return "外观"
        case .history: return "记录"
        case .about: return "关于"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var history: OperationHistory
    @State private var tab: SettingsTab = .general
    @State private var showResetAlert = false
    @State private var showClearHistory = false
    @State private var exportStatus: String?

    var body: some View {
        ZStack(alignment: .top) {
            LiquidBackground()
                .id(settings.theme)

            VStack(spacing: 14) {
                Picker("设置分类", selection: $tab) {
                    ForEach(SettingsTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        switch tab {
                        case .general:
                            general
                        case .analysis:
                            analysis
                        case .viewing:
                            viewing
                        case .appearance:
                            appearance
                        case .history:
                            operationHistory
                        case .about:
                            about
                        }
                    }
                    .padding(.vertical, 2)
                }
                .id(settings.theme)
                .frame(maxHeight: .infinity)
                .scrollIndicators(.automatic)

                HStack {
                    Text("更改会即时保存。")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if tab == .general {
                        Button("恢复默认设置…") {
                            showResetAlert = true
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 18)
            .padding(.top, 58)
            .padding(.bottom, 18)
            .frame(width: 660, height: 540, alignment: .top)
        }
        .frame(width: 660, height: 540)
        .alert("恢复默认设置？", isPresented: $showResetAlert) {
            Button("恢复默认", role: .destructive) {
                settings.reset()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将恢复扫描、分析、浏览与外观的全部设置为初始值。")
        }
        .confirmationDialog("清空操作记录？", isPresented: $showClearHistory) {
            Button("清空记录", role: .destructive) {
                history.clear()
                exportStatus = "操作记录已清空"
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("清空后无法恢复。已导出的文件不受影响。")
        }
        .onChange(of: settings.theme) { _, theme in
            history.log(.settings, "切换主题", theme.title)
        }
        .onChange(of: settings.enableSubjectAI) { _, enabled in
            history.log(.settings, "AI 主体识别", enabled ? "已启用" : "已停用")
        }
        .onChange(of: settings.useMetal) { _, enabled in
            history.log(.settings, "Metal GPU 分析", enabled ? "已启用" : "已停用")
        }
        .onChange(of: settings.appearance) { _, appearance in
            history.log(.settings, "切换外观", appearance.title)
        }
    }

    private var general: some View {
        VStack(spacing: 14) {
            SettingsCard(
                title: "载入与筛选",
                subtitle: "这些选项会影响下一次分析。"
            ) {
                SettingsToggleRow(
                    title: "包含子文件夹",
                    subtitle: "递归读取所选文件夹下的所有子文件夹。",
                    isOn: $settings.scanSubfolders
                )

                Divider().opacity(0.55)

                SettingsToggleRow(
                    title: "分析后自动选中疑似失焦",
                    subtitle: "载入完成后直接勾选所有低于阈值的照片，仍需手动确认删除。",
                    isOn: $settings.autoSelectBlurry
                )

                Divider().opacity(0.55)

                SettingsToggleRow(
                    title: "移到废纸篓前确认",
                    subtitle: "关闭后，点「移到废纸篓」会立即执行。照片仍可从废纸篓恢复。",
                    isOn: $settings.confirmBeforeTrash
                )
            }
        }
    }

    private var analysis: some View {
        VStack(spacing: 14) {
            SettingsCard(
                title: "Metal GPU 加速",
                subtitle: "清晰度计算使用 Mac 的 GPU，CPU 只负责解码与整理结果。"
            ) {
                SettingsToggleRow(
                    title: "使用 Metal GPU",
                    subtitle: "不可用时自动回退到 CPU，不影响功能。",
                    isOn: $settings.useMetal
                )

                HStack(spacing: 9) {
                    Circle()
                        .fill(MetalFocusScorer.isAvailable ? Theme.sharp : Theme.blur)
                        .frame(width: 6, height: 6)
                    Text(MetalFocusScorer.isAvailable ? "Metal 可用" : "Metal 不可用")
                        .font(.system(size: 10.5, weight: .medium))
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text(MetalFocusScorer.deviceDescription)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.top, 2)
            }

            SettingsCard(
                title: "AI 主体识别",
                subtitle: "使用 macOS Vision 在本机分类照片主体，用于筛选飞机、鸟类、动物、人物、汽车、自行车和摩托车。"
            ) {
                SettingsToggleRow(
                    title: "启用 AI 主体识别",
                    subtitle: "关闭后 AI 主体筛选不可用，分析速度会稍快。",
                    isOn: $settings.enableSubjectAI
                )

                HStack(spacing: 6) {
                    Image(systemName: "bolt.horizontal.circle")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Vision 自动调度 Neural Engine，与 Metal GPU 协同分析。")
                        .font(.system(size: 9.5))
                }
                .foregroundStyle(.secondary)
            }

            SettingsCard(
                title: "分析精度",
                subtitle: "精度越高，远景小主体的细节保留越好，但处理时间更长。"
            ) {
                Picker("分析精度", selection: $settings.analysisQuality) {
                    ForEach(AnalysisQuality.allCases) { quality in
                        Text(quality.title).tag(quality)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                HStack {
                    Text("分析长边")
                    Spacer()
                    Text("\(settings.analysisQuality.maxPixel) px")
                        .monospacedDigit()
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            }
        }
    }

    private var viewing: some View {
        VStack(spacing: 14) {
            SettingsCard(
                title: "悬停放大",
                subtitle: "鼠标移到照片上时自动放大，帮助快速判断合焦。"
            ) {
                HStack {
                    Text("放大倍率")
                        .font(.system(size: 11.5, weight: .medium))
                    Spacer()
                    Text(settings.hoverMagnificationText)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent)
                }

                Slider(
                    value: Binding(
                        get: { settings.hoverMagnification },
                        set: { settings.hoverMagnification = (($0 * 100).rounded() / 100) }
                    ),
                    in: 1.0...1.2
                )
                .tint(Theme.accent)

                HStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 42, height: 32)
                        .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                        .scaleEffect(settings.hoverMagnification)
                    Text("相册卡片和大图预览都会使用这个倍率。")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }
                .frame(height: 44)
            }

            SettingsCard(
                title: "缩略图",
                subtitle: "调整相册页每张卡片的基准大小。"
            ) {
                HStack {
                    Text("卡片大小")
                        .font(.system(size: 11.5, weight: .medium))
                    Spacer()
                    Text("\(Int(settings.thumbnailSize)) pt")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent)
                }

                Slider(
                    value: Binding(
                        get: { settings.thumbnailSize },
                        set: { settings.thumbnailSize = $0.rounded() }
                    ),
                    in: 180...300
                )
                .tint(Theme.accent)
            }

            SettingsCard(title: "大图工具栏") {
                SettingsToggleRow(
                    title: "在大图中显示完整 EXIF",
                    subtitle: "打开后可在大图右侧查看相机、镜头、曝光、GPS 等完整元数据。",
                    isOn: $settings.showEXIF
                )

                Divider().opacity(0.55)

                SettingsToggleRow(
                    title: "默认显示合焦框",
                    subtitle: "在大图中勾选「合焦框」后，会在检测到的最清晰区域绘制标记。",
                    isOn: $settings.showFocusBox
                )
            }
        }
    }

    private var appearance: some View {
        VStack(spacing: 14) {
            SettingsCard(
                title: "主题",
                subtitle: "点击即时切换配色、光晕与玻璃氛围。"
            ) {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(AppTheme.allCases) { theme in
                        themeCard(theme)
                    }
                }
            }

            SettingsCard(
                title: "外观",
                subtitle: "FocusCull 会跟随系统在浅色与深色之间切换。"
            ) {
                Picker("外观", selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            SettingsCard(title: "Liquid Glass") {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 28, height: 28)
                        .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                    Text("macOS 26 及以上使用系统 Liquid Glass 材质；较早系统自动使用半透明玻璃回退样式。悬浮工具栏会透出下方照片的模糊与色彩。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func themeCard(_ theme: AppTheme) -> some View {
        let selected = settings.theme == theme
        return Button {
            settings.theme = theme
        } label: {
            HStack(spacing: 9) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [theme.accent, theme.secondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 20, height: 20)
                    .shadow(color: theme.accent.opacity(0.35), radius: 5)

                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.title)
                        .font(.system(size: 11, weight: .semibold))
                    Text(theme.subtitle)
                        .font(.system(size: 8.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 2)

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.accent.opacity(selected ? 0.13 : 0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        selected ? theme.accent.opacity(0.75) : Color.primary.opacity(0.07),
                        lineWidth: selected ? 1.4 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .help("切换到 \(theme.title) 主题")
    }

    private var operationHistory: some View {
        VStack(spacing: 14) {
            SettingsCard(
                title: "操作记录",
                subtitle: "记录载入、分析、追加、删除和设置变更，最多保留 800 条。"
            ) {
                HStack(spacing: 10) {
                    Text("共 \(history.entries.count) 条")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        exportHistory()
                    } label: {
                        Label("导出 CSV…", systemImage: "square.and.arrow.up")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .disabled(history.entries.isEmpty)

                    Button("清空…") {
                        showClearHistory = true
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.danger)
                    .disabled(history.entries.isEmpty)
                }

                if let exportStatus {
                    Text(exportStatus)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(2)
                }

                Divider().opacity(0.55)

                if history.entries.isEmpty {
                    VStack(spacing: 7) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 24, weight: .light))
                        Text("还没有操作记录")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 140)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 7) {
                            ForEach(history.entries) { entry in
                                operationRow(entry)
                            }
                        }
                    }
                    .frame(maxHeight: 270)
                }
            }
        }
    }

    private func operationRow(_ entry: OperationEntry) -> some View {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return HStack(alignment: .top, spacing: 9) {
            Image(systemName: entry.category.systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(entry.category.tint)
                .frame(width: 22, height: 22)
                .background(entry.category.tint.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.title)
                        .font(.system(size: 10.8, weight: .semibold))
                    Spacer(minLength: 8)
                    Text(formatter.string(from: entry.date))
                        .font(.system(size: 8.5))
                        .foregroundStyle(.tertiary)
                }
                Text(entry.detail)
                    .font(.system(size: 9.3))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
    }

    private func exportHistory() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let panel = NSSavePanel()
        panel.title = "导出操作记录"
        panel.nameFieldStringValue = "FocusCull-操作记录-\(formatter.string(from: Date())).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try history.csvData.write(to: url, options: .atomic)
                exportStatus = "已导出到 \(url.lastPathComponent)"
                history.log(.export, "导出操作记录", "\(history.entries.count) 条 · \(url.lastPathComponent)")
            } catch {
                exportStatus = "导出失败：\(error.localizedDescription)"
            }
        }
    }

    private var about: some View {
        VStack(spacing: 14) {
            SettingsCard {
                HStack(spacing: 16) {
                    AppMark(size: 64)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("FocusCull")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("合焦筛选 · 版本 1.4.1")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        Text("开发者：Lee · 开发工具：DeepSeek")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text("Universal · macOS 14+ · © 2026 Lee")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
            }

            SettingsCard(title: "运行状态") {
                SettingsInfoRow(
                    icon: "cpu",
                    title: "焦点分析引擎",
                    value: MetalFocusScorer.isAvailable ? "Metal GPU" : "CPU"
                )
                Divider().opacity(0.55)
                SettingsInfoRow(
                    icon: "memorychip",
                    title: "Metal 设备",
                    value: MetalFocusScorer.deviceDescription
                )
                Divider().opacity(0.55)
                SettingsInfoRow(
                    icon: "brain.head.profile",
                    title: "AI 主体识别",
                    value: "Vision · Neural Engine"
                )
                Divider().opacity(0.55)
                SettingsInfoRow(
                    icon: "lock.shield",
                    title: "隐私",
                    value: "照片只在本机分析"
                )
            }

            SettingsCard(title: "说明") {
                Text("FocusCull 使用局部高频能量与方向平衡判断合焦程度。分数是同一批照片内部的相对值，建议在删除前逐张预览确认，尤其是背景比主体更清晰的画面。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SettingsCard<Content: View>: View {
    var title: String?
    var subtitle: String?
    @ViewBuilder var content: () -> Content

    init(
        title: String? = nil,
        subtitle: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            content()
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 18, shadow: false)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .tint(Theme.accent)
    }
}

private struct SettingsInfoRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 20)
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }
}
