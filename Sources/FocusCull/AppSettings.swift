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

enum CullingSensitivity: String, CaseIterable, Identifiable {
    case relaxed
    case balanced
    case strict

    var id: String { rawValue }

    var title: String {
        switch self {
        case .relaxed: return "宽松"
        case .balanced: return "标准"
        case .strict: return "严格"
        }
    }

    var bias: Double {
        switch self {
        case .relaxed: return -8
        case .balanced: return 0
        case .strict: return 8
        }
    }

    var subtitle: String {
        switch self {
        case .relaxed: return "保留更多照片，适合先粗筛再人工确认"
        case .balanced: return "自动阈值，适合大多数连拍"
        case .strict: return "更早把边界照片放进疑似失焦"
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
        static let sensitivity = "FocusCull.settings.sensitivity"
        static let subjectFocusWeight = "FocusCull.settings.subjectFocusWeight"
        static let directionalWeight = "FocusCull.settings.directionalWeight"
        static let peakFraction = "FocusCull.settings.peakFraction"
        static let edgeTrim = "FocusCull.settings.edgeTrim"
        static let analysisConcurrency = "FocusCull.settings.analysisConcurrency"
        static let maxBlurFraction = "FocusCull.settings.maxBlurFraction"
        static let showScore = "FocusCull.settings.showScore"
        static let showSubject = "FocusCull.settings.showSubject"
        static let showFileDetails = "FocusCull.settings.showFileDetails"
        static let restoreLastFolder = "FocusCull.settings.restoreLastFolder"
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
    @Published var sensitivity: CullingSensitivity {
        didSet { defaults.set(sensitivity.rawValue, forKey: Key.sensitivity) }
    }
    @Published var subjectFocusWeight: Double {
        didSet { defaults.set(subjectFocusWeight, forKey: Key.subjectFocusWeight) }
    }
    @Published var directionalWeight: Double {
        didSet { defaults.set(directionalWeight, forKey: Key.directionalWeight) }
    }
    @Published var peakFraction: Double {
        didSet { defaults.set(peakFraction, forKey: Key.peakFraction) }
    }
    @Published var edgeTrim: Double {
        didSet { defaults.set(edgeTrim, forKey: Key.edgeTrim) }
    }
    @Published var analysisConcurrency: Int {
        didSet { defaults.set(analysisConcurrency, forKey: Key.analysisConcurrency) }
    }
    @Published var maxBlurFraction: Double {
        didSet { defaults.set(maxBlurFraction, forKey: Key.maxBlurFraction) }
    }
    @Published var showScore: Bool {
        didSet { defaults.set(showScore, forKey: Key.showScore) }
    }
    @Published var showSubject: Bool {
        didSet { defaults.set(showSubject, forKey: Key.showSubject) }
    }
    @Published var showFileDetails: Bool {
        didSet { defaults.set(showFileDetails, forKey: Key.showFileDetails) }
    }
    @Published var restoreLastFolder: Bool {
        didSet { defaults.set(restoreLastFolder, forKey: Key.restoreLastFolder) }
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
        self.sensitivity = CullingSensitivity(
            rawValue: defaults.string(forKey: Key.sensitivity) ?? ""
        ) ?? .balanced
        self.subjectFocusWeight = Self.clamp(
            Self.double(defaults, Key.subjectFocusWeight, fallback: 0.65),
            min: 0,
            max: 1
        )
        self.directionalWeight = Self.clamp(
            Self.double(defaults, Key.directionalWeight, fallback: 0.45),
            min: 0,
            max: 1
        )
        self.peakFraction = Self.clamp(
            Self.double(defaults, Key.peakFraction, fallback: 0.02),
            min: 0.01,
            max: 0.08
        )
        self.edgeTrim = Self.clamp(
            Self.double(defaults, Key.edgeTrim, fallback: 0),
            min: 0,
            max: 0.15
        )
        self.analysisConcurrency = min(8, max(2, defaults.object(forKey: Key.analysisConcurrency) as? Int ?? 6))
        self.maxBlurFraction = Self.clamp(
            Self.double(defaults, Key.maxBlurFraction, fallback: 0.45),
            min: 0.1,
            max: 0.7
        )
        self.showScore = Self.bool(defaults, Key.showScore, fallback: true)
        self.showSubject = Self.bool(defaults, Key.showSubject, fallback: true)
        self.showFileDetails = Self.bool(defaults, Key.showFileDetails, fallback: true)
        self.restoreLastFolder = Self.bool(defaults, Key.restoreLastFolder, fallback: false)
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
        sensitivity = .balanced
        subjectFocusWeight = 0.65
        directionalWeight = 0.45
        peakFraction = 0.02
        edgeTrim = 0
        analysisConcurrency = 6
        maxBlurFraction = 0.45
        showScore = true
        showSubject = true
        showFileDetails = true
        restoreLastFolder = false
    }

    func resetAnalysisOptions() {
        useMetal = true
        enableSubjectAI = true
        analysisQuality = .standard
        sensitivity = .balanced
        subjectFocusWeight = 0.65
        directionalWeight = 0.45
        peakFraction = 0.02
        edgeTrim = 0
        analysisConcurrency = 6
        maxBlurFraction = 0.45
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
