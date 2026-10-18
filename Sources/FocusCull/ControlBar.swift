import SwiftUI

struct ControlBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Picker("显示", selection: $model.filter) {
                Text("全部 \(model.filteredTotalCount)").tag(PhotoFilter.all)
                Text("疑似失焦 \(model.blurryCount)").tag(PhotoFilter.blurry)
                Text("合焦 \(model.sharpCount)").tag(PhotoFilter.sharp)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 320)

            Spacer(minLength: 8)

            thresholdControl

            Divider()
                .frame(height: 22)

            sortMenu

            Button {
                model.selectAllBlurred()
            } label: {
                Label("全选失焦", systemImage: "checkmark.circle")
                    .font(.system(size: 10.5, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(model.blurryCount == 0)
            .help("选中所有疑似失焦的照片 (⌘⇧A)")

            Button {
                model.requestDeleteSelected(mode: .trash)
            } label: {
                HStack(spacing: 5) {
                    Label("移到废纸篓", systemImage: "trash")
                    if model.selectedCount > 0 {
                        Text("\(model.selectedCount)")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.white.opacity(0.22), in: Capsule())
                    }
                }
                .font(.system(size: 10.5, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.danger)
            .controlSize(.regular)
            .disabled(model.selectedCount == 0)
            .help("把已选照片移到废纸篓 (⌘⌫)")

            Menu {
                Button("永久删除所选…", role: .destructive) {
                    model.requestDeleteSelected(mode: .permanent)
                }
                .disabled(model.selectedCount == 0)

                Button {
                    model.revealSelectionInFinder()
                } label: {
                    Label("在 Finder 中显示所选", systemImage: "folder")
                }
                .disabled(model.totalCount == 0)

                Divider()

                Button("取消选择") {
                    model.clearSelection()
                }
                .disabled(model.selectedCount == 0)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
                    .frame(width: 17, height: 17)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
            .help("更多操作")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .glassPanel(cornerRadius: 20)
    }

    private var thresholdControl: some View {
        HStack(spacing: 7) {
            Text("失焦阈值")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            Text(model.thresholdText)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.blur)
                .frame(width: 22, alignment: .trailing)

            ThresholdSlider(model: model)
                .frame(width: 126, height: 20)
                .help("清晰度低于阈值的照片会被归入疑似失焦。拖动滑块可手动调整。")

            Button {
                model.resetToAutoThreshold()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: model.isAutoThreshold ? "wand.and.stars" : "arrow.counterclockwise")
                        .font(.system(size: 9))
                    Text(model.isAutoThreshold ? "自动 \(model.autoThresholdText)" : "恢复自动")
                        .font(.system(size: 9.5, weight: .medium))
                }
                .foregroundStyle(model.isAutoThreshold ? Theme.accent : Color.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(model.isAutoThreshold ? Theme.accent.opacity(0.10) : Color.primary.opacity(0.04))
                )
            }
            .buttonStyle(.plain)
            .help("重新使用根据本组照片分布自动计算的阈值")
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(PhotoSortOrder.allCases) { order in
                Button {
                    model.sortOrder = order
                } label: {
                    if model.sortOrder == order {
                        Label(order.title, systemImage: "checkmark")
                    } else {
                        Text(order.title)
                    }
                }
            }
        } label: {
            Label(model.sortOrder.title, systemImage: "arrow.up.arrow.down")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("排序方式")
    }
}


private struct ThresholdSlider: View {
    @ObservedObject var model: AppModel

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let progress = min(1, max(0, model.threshold / 100))
            let knob: CGFloat = 15

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.13))
                    .frame(height: 4)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Theme.blur.opacity(0.62), Theme.blur],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(4, width * progress), height: 4)
                Circle()
                    .fill(.white)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.28), radius: 3, y: 1)
                    .offset(x: (width - knob) * progress)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = min(1, max(0, value.location.x / max(width, 1)))
                        model.setManualThreshold((fraction * 100).rounded())
                    }
            )
        }
        .accessibilityElement()
        .accessibilityLabel("失焦阈值")
        .accessibilityValue("\(Int(model.threshold))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                model.setManualThreshold(model.threshold + 1)
            case .decrement:
                model.setManualThreshold(model.threshold - 1)
            @unknown default:
                break
            }
        }
    }
}
