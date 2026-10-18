import Combine
import Foundation
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AnalysisQuality: String, CaseIterable, Identifiable {
    case fast
    case standard
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast: return "快速"
        case .standard: return "标准"
        case .high: return "精细"
        }
    }

    var maxPixel: Int {
        switch self {
        case .fast: return 900
        case .standard: return 1100
        case .high: return 1500
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let scanSubfolders = "FocusCull.settings.scanSubfolders"
        static let autoSelectBlurry = "FocusCull.settings.autoSelectBlurry"
        static let confirmBeforeTrash = "FocusCull.settings.confirmBeforeTrash"
        static let useMetal = "FocusCull.settings.useMetal"
        static let enableSubjectAI = "FocusCull.settings.enableSubjectAI"
        static let showFocusBox = "FocusCull.settings.showFocusBox"
        static let analysisQuality = "FocusCull.settings.analysisQuality"
        static let hoverMagnification = "FocusCull.settings.hoverMagnification"
        static let thumbnailSize = "FocusCull.settings.thumbnailSize"
        static let showEXIF = "FocusCull.settings.showEXIF"
        static let appearance = "FocusCull.settings.appearance"
        static let theme = "FocusCull.settings.theme"
    }

    private let defaults: UserDefaults

    @Published var scanSubfolders: Bool {
        didSet { defaults.set(scanSubfolders, forKey: Key.scanSubfolders) }
    }
    @Published var autoSelectBlurry: Bool {
        didSet { defaults.set(autoSelectBlurry, forKey: Key.autoSelectBlurry) }
    }
    @Published var confirmBeforeTrash: Bool {
        didSet { defaults.set(confirmBeforeTrash, forKey: Key.confirmBeforeTrash) }
    }
    @Published var useMetal: Bool {
        didSet { defaults.set(useMetal, forKey: Key.useMetal) }
    }
    @Published var enableSubjectAI: Bool {
        didSet { defaults.set(enableSubjectAI, forKey: Key.enableSubjectAI) }
    }
    @Published var showFocusBox: Bool {
        didSet { defaults.set(showFocusBox, forKey: Key.showFocusBox) }
    }
    @Published var analysisQuality: AnalysisQuality {
        didSet { defaults.set(analysisQuality.rawValue, forKey: Key.analysisQuality) }
    }
    @Published var hoverMagnification: Double {
        didSet { defaults.set(hoverMagnification, forKey: Key.hoverMagnification) }
    }
    @Published var thumbnailSize: Double {
        didSet { defaults.set(thumbnailSize, forKey: Key.thumbnailSize) }
    }
    @Published var showEXIF: Bool {
        didSet { defaults.set(showEXIF, forKey: Key.showEXIF) }
    }
    @Published var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }
    @Published var theme: AppTheme {
        didSet {
            defaults.set(theme.rawValue, forKey: Key.theme)
            Theme.currentTheme = theme
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.scanSubfolders = Self.bool(defaults, Key.scanSubfolders, fallback: false)
        self.autoSelectBlurry = Self.bool(defaults, Key.autoSelectBlurry, fallback: false)
        self.confirmBeforeTrash = Self.bool(defaults, Key.confirmBeforeTrash, fallback: true)
        self.useMetal = Self.bool(defaults, Key.useMetal, fallback: true)
        self.enableSubjectAI = Self.bool(defaults, Key.enableSubjectAI, fallback: true)
        self.showFocusBox = Self.bool(defaults, Key.showFocusBox, fallback: false)
        self.analysisQuality = AnalysisQuality(
            rawValue: defaults.string(forKey: Key.analysisQuality) ?? ""
        ) ?? .standard
        self.hoverMagnification = Self.clamp(
            Self.double(defaults, Key.hoverMagnification, fallback: 1.06),
            min: 1.0,
            max: 1.2
        )
        self.thumbnailSize = Self.clamp(
            Self.double(defaults, Key.thumbnailSize, fallback: 224),
            min: 180,
            max: 300
        )
        self.showEXIF = Self.bool(defaults, Key.showEXIF, fallback: true)
        self.appearance = AppAppearance(
            rawValue: defaults.string(forKey: Key.appearance) ?? ""
        ) ?? .system
        self.theme = AppTheme(
            rawValue: defaults.string(forKey: Key.theme) ?? ""
        ) ?? .focusCull
        Theme.currentTheme = self.theme
    }

    func reset() {
        scanSubfolders = false
        autoSelectBlurry = false
        confirmBeforeTrash = true
        useMetal = true
        enableSubjectAI = true
        showFocusBox = false
        analysisQuality = .standard
        hoverMagnification = 1.06
        thumbnailSize = 224
        showEXIF = true
        appearance = .system
        theme = .focusCull
    }

    var hoverMagnificationText: String {
        String(format: "%.2f×", hoverMagnification)
    }

    private static func bool(_ defaults: UserDefaults, _ key: String, fallback: Bool) -> Bool {
        (defaults.object(forKey: key) as? Bool) ?? fallback
    }

    private static func double(_ defaults: UserDefaults, _ key: String, fallback: Double) -> Double {
        (defaults.object(forKey: key) as? Double) ?? fallback
    }

    private static func clamp(_ value: Double, min lower: Double, max upper: Double) -> Double {
        Swift.min(upper, Swift.max(lower, value))
    }
}
