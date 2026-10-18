import SwiftUI

struct SubjectFilterBar: View {
    @ObservedObject var model: AppModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        HStack(spacing: 10) {
            Label("AI 主体", systemImage: "sparkles")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .fixedSize()

            if settings.enableSubjectAI {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(SubjectFilter.allCases) { filter in
                            chip(filter)
                        }
                    }
                }
            } else {
                Text("主体识别已在设置中关闭")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                SettingsLink {
                    Text("去开启")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.accent)
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .glassPanel(cornerRadius: 18)
        .onChange(of: settings.enableSubjectAI) { _, enabled in
            if !enabled {
                model.subjectFilter = .all
            }
        }
    }

    private func chip(_ filter: SubjectFilter) -> some View {
        let selected = model.subjectFilter == filter
        let count = model.subjectCount(for: filter)
        return Button {
            model.subjectFilter = filter
        } label: {
            HStack(spacing: 4) {
                Image(systemName: filter.symbolName)
                    .font(.system(size: 9, weight: .medium))
                Text(filter.title)
                    .font(.system(size: 10, weight: .medium))
                Text("\(count)")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .opacity(0.62)
            }
            .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.72))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(selected ? Theme.accent : Color.primary.opacity(0.045))
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        selected ? Theme.accent.opacity(0.7) : Color.primary.opacity(0.08),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .help("显示 AI 识别为「\(filter.title)」的照片")
    }
}
