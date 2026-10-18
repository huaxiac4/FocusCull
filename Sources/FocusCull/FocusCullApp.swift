import AppKit
import SwiftUI

@main
struct FocusCullApp: App {
    @NSApplicationDelegateAdaptor(FocusCullAppDelegate.self) private var appDelegate
    @StateObject private var settings: AppSettings
    @StateObject private var history: OperationHistory
    @StateObject private var model: AppModel

    init() {
        let settings = AppSettings()
        let history = OperationHistory()
        _settings = StateObject(wrappedValue: settings)
        _history = StateObject(wrappedValue: history)
        _model = StateObject(wrappedValue: AppModel(settings: settings, history: history))
    }

    var body: some Scene {
        WindowGroup("FocusCull", id: "main") {
            ContentView(model: model)
                .environmentObject(settings)
                .modifier(AppAppearanceModifier(appearance: settings.appearance))
                .id(settings.theme)
                .frame(minWidth: 1180, minHeight: 760)
        }
        .defaultSize(width: 1320, height: 880)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            FocusCullCommands(model: model)
        }

        MenuBarExtra("FocusCull", systemImage: "camera.aperture") {
            MenuBarPanel(model: model, settings: settings)
                .environmentObject(settings)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: settings, history: history)
                .modifier(AppAppearanceModifier(appearance: settings.appearance))
        }
    }
}

struct FocusCullCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("打开照片文件夹…") {
                model.chooseFolder()
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("重新扫描当前文件夹") {
                model.rescan()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.folderURL == nil || model.phase.isScanning)

            Divider()

            Button("在 Finder 中显示文件夹") {
                model.revealFolderInFinder()
            }
            .disabled(model.folderURL == nil)
        }

        CommandGroup(after: .pasteboard) {
            Button("全选照片") {
                model.selectAllVisible()
            }
            .keyboardShortcut("a", modifiers: .command)
            .disabled(model.visiblePhotos.isEmpty)

            Button("全选疑似失焦") {
                model.selectAllBlurred()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(model.blurryCount == 0)

            Button("取消选择") {
                model.clearSelection()
            }
            .disabled(model.selectedCount == 0)
        }

        CommandMenu("照片") {
            Button("移到废纸篓") {
                model.requestDeleteSelected(mode: .trash)
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(model.selectedCount == 0)

            Button("永久删除所选…") {
                model.requestDeleteSelected(mode: .permanent)
            }
            .disabled(model.selectedCount == 0)

            Divider()

            Button("在 Finder 中显示所选") {
                model.revealSelectionInFinder()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(model.totalCount == 0)

            Divider()

            Toggle(
                "包含子文件夹",
                isOn: Binding(
                    get: { model.includeSubfolders },
                    set: { model.setIncludeSubfolders($0) }
                )
            )
        }
    }
}


private struct AppAppearanceModifier: ViewModifier {
    let appearance: AppAppearance

    @ViewBuilder
    func body(content: Content) -> some View {
        switch appearance {
        case .system:
            content
        case .light:
            content.preferredColorScheme(.light)
        case .dark:
            content.preferredColorScheme(.dark)
        }
    }
}
