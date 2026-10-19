import AppKit
import Combine
import FocusCullCore
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum PhotoFilter: String, CaseIterable, Identifiable {
    case all
    case blurry
    case sharp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .blurry: return "疑似失焦"
        case .sharp: return "合焦"
        }
    }
}

enum SubjectFilter: String, CaseIterable, Identifiable {
    case all
    case airplane
    case bird
    case animal
    case person
    case car
    case bicycle
    case motorcycle
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .airplane: return "飞机"
        case .bird: return "鸟类"
        case .animal: return "动物"
        case .person: return "人物"
        case .car: return "汽车"
        case .bicycle: return "自行车"
        case .motorcycle: return "摩托车"
        case .other: return "其他"
        }
    }

    var symbolName: String {
        switch self {
        case .all: return "sparkles"
        case .airplane: return "airplane"
        case .bird: return "bird"
        case .animal: return "pawprint"
        case .person: return "person"
        case .car: return "car"
        case .bicycle: return "bicycle"
        case .motorcycle: return "motorcycle"
        case .other: return "square.grid.2x2"
        }
    }

    var subject: PhotoSubject? {
        switch self {
        case .all: return nil
        case .airplane: return .airplane
        case .bird: return .bird
        case .animal: return .animal
        case .person: return .person
        case .car: return .car
        case .bicycle: return .bicycle
        case .motorcycle: return .motorcycle
        case .other: return .other
        }
    }
}

struct AppendProgress: Equatable {
    let done: Int
    let total: Int
}

enum PhotoSortOrder: String, CaseIterable, Identifiable {
    case fileName
    case captureDate
    case scoreHigh
    case scoreLow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fileName: return "文件名"
        case .captureDate: return "拍摄时间"
        case .scoreHigh: return "清晰度：高到低"
        case .scoreLow: return "清晰度：低到高"
        }
    }
}

enum ImportPhase: Equatable {
    case empty
    case scanning(done: Int, total: Int)
    case ready

    var isScanning: Bool {
        if case .scanning = self { return true }
        return false
    }
}

enum DeleteMode: Sendable {
    case trash
    case permanent
}

enum AppAlert: Identifiable {
    case noPhotos(String)
    case error(title: String, message: String)
    case deleteTrash(count: Int)
    case deletePermanent(count: Int)

    var id: String {
        switch self {
        case let .noPhotos(folder): return "no-photos-\(folder)"
        case let .error(title, message): return "error-\(title)-\(message)"
        case let .deleteTrash(count): return "trash-\(count)"
        case let .deletePermanent(count): return "permanent-\(count)"
        }
    }
}

enum ToastKind: Equatable {
    case success
    case info
    case warning
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let systemImage: String
    let kind: ToastKind
}

struct PhotoItem: Identifiable, Hashable {
    let analysis: PhotoAnalysis
    var score: Double
    var isSharp: Bool

    var id: URL { analysis.url }
    var fileName: String { analysis.fileName }
    var isFailed: Bool { analysis.hasError }

    var scoreText: String {
        isFailed ? "—" : SharpnessScoring.formattedScore(score)
    }
}

struct PhotoSection: Identifiable {
    enum Kind: String {
        case blurry
        case sharp
        case failed
    }

    let kind: Kind
    let title: String
    let photos: [PhotoItem]

    var id: Kind { kind }
}

private struct DeletionOutcome: Sendable {
    let deleted: [URL]
    let failures: [String]
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var photos: [PhotoItem] = []
    @Published private(set) var folderURL: URL?
    @Published private(set) var phase: ImportPhase = .empty
    @Published var filter: PhotoFilter = .all
    @Published var subjectFilter: SubjectFilter = .all
    @Published var sortOrder: PhotoSortOrder = .fileName
    @Published private(set) var threshold: Double = 50
    @Published private(set) var autoThreshold: Double = 50
    private var autoThresholdBase: Double = 50
    @Published private(set) var isAutoThreshold = true
    @Published private(set) var allSoftWarning = false
    @Published var includeSubfolders = false
    @Published private(set) var selectedURLs: Set<URL> = []
    @Published var previewURL: URL?
    @Published var activeAlert: AppAlert?
    @Published var toast: ToastMessage?
    @Published private(set) var lastSkippedCount = 0
    @Published private(set) var analyzedDuration: TimeInterval = 0
    @Published private(set) var metalAnalyzedCount = 0
    @Published private(set) var cpuAnalyzedCount = 0
    @Published private(set) var appendProgress: AppendProgress?

    private let settings: AppSettings
    private let history: OperationHistory
    private var cancellables = Set<AnyCancellable>()
    private var scanTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var scanGeneration = UUID()
    private var pendingDeleteURLs: [URL] = []
    private var pendingDeleteMode: DeleteMode = .trash

    private let lastFolderKey = "FocusCull.lastFolderPath"

    init(settings: AppSettings, history: OperationHistory) {
        self.settings = settings
        self.history = history
        self.includeSubfolders = settings.scanSubfolders
        settings.$scanSubfolders
            .dropFirst()
            .sink { [weak self] value in
                guard let self, self.includeSubfolders != value else { return }
                self.includeSubfolders = value
            }
            .store(in: &cancellables)
    }

    // MARK: - Derived state

    var totalCount: Int { photos.count }
    var subjectFilteredPhotos: [PhotoItem] {
        guard let subject = subjectFilter.subject else { return photos }
        return photos.filter { $0.analysis.subject?.subject == subject }
    }
    var filteredTotalCount: Int { subjectFilteredPhotos.count }
    var blurryCount: Int { subjectFilteredPhotos.lazy.filter { !$0.isSharp && !$0.isFailed }.count }
    var sharpCount: Int { subjectFilteredPhotos.lazy.filter(\.isSharp).count }
    var failedCount: Int { subjectFilteredPhotos.lazy.filter(\.isFailed).count }
    var selectedCount: Int { selectedURLs.count }

    func subjectCount(for filter: SubjectFilter) -> Int {
        guard let subject = filter.subject else { return photos.count }
        return photos.lazy.filter { $0.analysis.subject?.subject == subject }.count
    }

    var subjectFilterTitle: String { subjectFilter.title }

    var selectedFileSize: Int64 {
        photos.reduce(into: Int64(0)) { total, photo in
            if selectedURLs.contains(photo.id) { total += photo.analysis.fileSize }
        }
    }

    var selectedPhotos: [PhotoItem] {
        photos.filter { selectedURLs.contains($0.id) }
    }

    var analysisEngineSummary: String {
        let neural = settings.enableSubjectAI ? " + Neural Engine" : ""
        if metalAnalyzedCount > 0, cpuAnalyzedCount == 0 {
            return "Metal GPU\(neural)"
        }
        if metalAnalyzedCount > 0 {
            return "Metal GPU\(neural) · \(cpuAnalyzedCount) 张 CPU 回退"
        }
        if cpuAnalyzedCount > 0 {
            return "CPU\(neural)"
        }
        return "—"
    }

    var recentFolderURL: URL? {
        guard let path = UserDefaults.standard.string(forKey: lastFolderKey) else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    var displayFolderName: String {
        folderURL?.lastPathComponent ?? "FocusCull"
    }

    var blurryPhotos: [PhotoItem] {
        sort(subjectFilteredPhotos.filter { !$0.isSharp && !$0.isFailed })
    }

    var sharpPhotos: [PhotoItem] {
        sort(subjectFilteredPhotos.filter(\.isSharp))
    }

    var failedPhotos: [PhotoItem] {
        sort(subjectFilteredPhotos.filter(\.isFailed))
    }

    var sections: [PhotoSection] {
        switch filter {
        case .blurry:
            return [PhotoSection(kind: .blurry, title: "疑似失焦", photos: blurryPhotos)]
        case .sharp:
            return [PhotoSection(kind: .sharp, title: "合焦", photos: sharpPhotos)]
        case .all:
            var result: [PhotoSection] = []
            if !blurryPhotos.isEmpty {
                result.append(PhotoSection(kind: .blurry, title: "疑似失焦", photos: blurryPhotos))
            }
            if !sharpPhotos.isEmpty {
                result.append(PhotoSection(kind: .sharp, title: "合焦", photos: sharpPhotos))
            }
            if !failedPhotos.isEmpty {
                result.append(PhotoSection(kind: .failed, title: "无法分析", photos: failedPhotos))
            }
            return result
        }
    }

    var visiblePhotos: [PhotoItem] {
        sections.flatMap(\.photos)
    }

    var previewPhoto: PhotoItem? {
        guard let previewURL else { return nil }
        return photos.first { $0.id == previewURL }
    }

    var previewNavigationPhotos: [PhotoItem] {
        let visible = visiblePhotos
        if let previewURL, visible.contains(where: { $0.id == previewURL }) {
            return visible
        }
        return photos
    }

    var thresholdText: String { String(Int(threshold.rounded())) }

    var autoThresholdText: String { String(Int(adjustedThreshold(autoThreshold).rounded())) }

    var currentFolderDisplayPath: String {
        guard let folderURL else { return "" }
        return folderURL.path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
    }

    // MARK: - Folder loading

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择照片文件夹"
        panel.message = "FocusCull 会分析文件夹中的照片，并找出疑似失焦的画面。"
        panel.prompt = "载入照片"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        if let folderURL {
            panel.directoryURL = folderURL
        }
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            openFolder(url)
        }
    }

    func openFolder(_ url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            activeAlert = .error(title: "不是文件夹", message: "请拖入或选择一个包含照片的文件夹。")
            return
        }

        scanTask?.cancel()
        let generation = UUID()
        scanGeneration = generation
        scanTask = Task { [weak self] in
            await self?.load(folder: url, generation: generation)
        }
    }

    func rescan() {
        guard let folderURL else { return }
        openFolder(folderURL)
    }

    func cancelScan() {
        scanGeneration = UUID()
        scanTask?.cancel()
        scanTask = nil
        phase = .empty
        folderURL = nil
        photos = []
        selectedURLs = []
        previewURL = nil
        appendProgress = nil
    }

    func chooseAppend() {
        guard phase == .ready else { return }
        let panel = NSOpenPanel()
        panel.title = "追加照片或文件夹"
        panel.message = "可以一次选择多张照片，或者一个 / 多个文件夹。"
        panel.prompt = "追加"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        if let folderURL {
            panel.directoryURL = folderURL
        }
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK {
            append(urls: panel.urls)
        }
    }

    func append(urls: [URL]) {
        guard phase == .ready else {
            showToast("请等待当前分析完成", systemImage: "hourglass", kind: .info)
            return
        }
        guard !urls.isEmpty else { return }
        scanTask?.cancel()
        let generation = UUID()
        scanGeneration = generation
        scanTask = Task { [weak self] in
            await self?.performAppend(urls: urls, generation: generation)
        }
    }

    // MARK: - Menu bar imports

    func chooseImagesForMenu() {
        guard !phase.isScanning else {
            showToast("请等待当前分析完成", systemImage: "hourglass", kind: .info)
            return
        }
        let panel = NSOpenPanel()
        panel.title = "添加图片"
        panel.message = "选择要加入当前批次的图片；如果当前没有批次，会新建一个批次。"
        panel.prompt = "添加"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        if let folderURL {
            panel.directoryURL = folderURL
        }
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK {
            ingestFromMenu(urls: panel.urls)
        }
    }

    func chooseFoldersForMenu() {
        guard !phase.isScanning else {
            showToast("请等待当前分析完成", systemImage: "hourglass", kind: .info)
            return
        }
        let panel = NSOpenPanel()
        panel.title = "添加文件夹"
        panel.message = "可以一次选择多个文件夹；当前已有照片时会追加到同一批次。"
        panel.prompt = "添加"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        if let folderURL {
            panel.directoryURL = folderURL
        }
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK {
            ingestFromMenu(urls: panel.urls)
        }
    }

    /// Entry point for the menu bar panel and for Finder drops.
    /// With no current batch it starts a new one; otherwise it appends.
    func ingestFromMenu(urls: [URL]) {
        let valid = urls.filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
        guard !valid.isEmpty else {
            showToast("没有可导入的文件或文件夹", systemImage: "exclamationmark.circle", kind: .warning)
            return
        }
        guard !phase.isScanning else {
            showToast("请等待当前分析完成", systemImage: "hourglass", kind: .info)
            return
        }
        if photos.isEmpty || phase == .empty {
            openMixed(urls: valid)
        } else {
            append(urls: valid)
        }
    }

    /// Starts a batch from a mix of folders and individual image files.
    func openMixed(urls: [URL]) {
        guard !urls.isEmpty else { return }
        scanTask?.cancel()
        let generation = UUID()
        scanGeneration = generation
        scanTask = Task { [weak self] in
            await self?.loadMixed(urls: urls, generation: generation)
        }
    }

    private func loadMixed(urls: [URL], generation: UUID) async {
        var candidates: [URL] = []
        var skipped = 0
        var displayBase: URL?

        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                skipped += 1
                continue
            }
            if isDirectory.boolValue {
                displayBase = displayBase ?? url
                do {
                    let scan = try PhotoScanner.scan(folder: url, recursive: includeSubfolders)
                    candidates.append(contentsOf: scan.urls)
                    skipped += scan.skippedCount
                } catch {
                    skipped += 1
                }
            } else if PhotoFileType.isSupported(url) {
                displayBase = displayBase ?? url.deletingLastPathComponent()
                candidates.append(url)
            } else {
                skipped += 1
            }
        }

        var seen = Set<URL>()
        let unique = candidates
            .map(\.standardizedFileURL)
            .filter { seen.insert($0).inserted }

        guard generation == scanGeneration else { return }

        folderURL = displayBase ?? urls.first
        photos = []
        selectedURLs = []
        previewURL = nil
        filter = .all
        subjectFilter = .all
        allSoftWarning = false
        lastSkippedCount = skipped
        appendProgress = nil

        guard !unique.isEmpty else {
            phase = .empty
            folderURL = nil
            activeAlert = .noPhotos(displayBase?.lastPathComponent ?? "所选内容")
            return
        }

        phase = .scanning(done: 0, total: unique.count)
        let started = Date()
        let analyses = await analyze(urls: unique) { done, total in
            self.phase = .scanning(done: done, total: total)
        }
        guard generation == scanGeneration else { return }
        install(analyses: analyses, folder: displayBase ?? urls[0], started: started)
    }

    private func performAppend(urls: [URL], generation: UUID) async {
        var candidates: [URL] = []
        var skipped = 0
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                skipped += 1
                continue
            }
            if isDirectory.boolValue {
                do {
                    let scan = try PhotoScanner.scan(folder: url, recursive: includeSubfolders)
                    candidates.append(contentsOf: scan.urls)
                    skipped += scan.skippedCount
                } catch {
                    skipped += 1
                }
            } else if PhotoFileType.isSupported(url) {
                candidates.append(url)
            } else {
                skipped += 1
            }
        }

        guard generation == scanGeneration else { return }
        var seen = Set(photos.map(\.id))
        var newURLs: [URL] = []
        for url in candidates {
            let canonical = url.standardizedFileURL
            guard !seen.contains(canonical) else { continue }
            seen.insert(canonical)
            newURLs.append(canonical)
        }

        guard !newURLs.isEmpty else {
            appendProgress = nil
            showToast(
                skipped > 0 ? "没有找到新的可读取照片" : "没有找到新的照片",
                systemImage: "exclamationmark.circle",
                kind: .info
            )
            return
        }

        previewURL = nil
        appendProgress = AppendProgress(done: 0, total: newURLs.count)
        let analyses = await analyze(urls: newURLs) { [weak self] done, total in
            self?.appendProgress = AppendProgress(done: done, total: total)
        }
        guard !Task.isCancelled, generation == scanGeneration else {
            appendProgress = nil
            return
        }

        let merged = photos.map(\.analysis) + analyses
        let ordered = merged.sorted {
            $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
        }
        let batch = SharpnessScoring.makeBatch(rawScores: ordered.map(\.rawScore))
        if isAutoThreshold {
            autoThresholdBase = batch.autoThreshold
            autoThreshold = SharpnessScoring.cappedAutoThreshold(
                base: batch.autoThreshold,
                scores: batch.scores,
                maxBlurFraction: settings.maxBlurFraction
            )
            threshold = adjustedThreshold(autoThreshold)
        }
        let targetThreshold = threshold
        allSoftWarning = batch.allSoftWarning
        metalAnalyzedCount = ordered.lazy.filter { $0.backend == .metal }.count
        cpuAnalyzedCount = ordered.lazy.filter { $0.backend == .cpu }.count

        let updated = zip(ordered, batch.scores).map { analysis, score in
            PhotoItem(
                analysis: analysis,
                score: score,
                isSharp: !analysis.hasError && score >= targetThreshold
            )
        }
        let validIDs = Set(updated.map(\.id))
        selectedURLs = selectedURLs.intersection(validIDs)
        photos = updated
        if settings.autoSelectBlurry {
            selectedURLs.formUnion(updated.filter { !$0.isSharp && !$0.isFailed }.map(\.id))
        }
        appendProgress = nil
        lastSkippedCount += skipped
        if let folderURL {
            UserDefaults.standard.set(folderURL.path, forKey: lastFolderKey)
        }
        history.log(
            .append,
            "追加照片",
            "+\(analyses.count) 张 · 当前共 \(photos.count) 张"
        )
        showToast(
            "已追加 \(analyses.count) 张照片",
            systemImage: "plus.circle.fill",
            kind: .success
        )
    }

    func setIncludeSubfolders(_ value: Bool) {
        guard includeSubfolders != value else { return }
        includeSubfolders = value
        settings.scanSubfolders = value
        if phase == .ready {
            showToast(
                value ? "下次扫描将包含子文件夹" : "下次扫描只读取当前文件夹",
                systemImage: "folder.badge.gearshape",
                kind: .info
            )
        }
    }

    private func load(folder: URL, generation: UUID) async {
        let accessed = folder.startAccessingSecurityScopedResource()
        defer { if accessed { folder.stopAccessingSecurityScopedResource() } }

        folderURL = folder
        photos = []
        selectedURLs = []
        previewURL = nil
        filter = .all
        subjectFilter = .all
        allSoftWarning = false
        lastSkippedCount = 0
        appendProgress = nil
        phase = .scanning(done: 0, total: 0)

        let started = Date()
        do {
            let scan = try PhotoScanner.scan(folder: folder, recursive: includeSubfolders)
            try Task.checkCancellation()
            guard generation == scanGeneration else { return }

            lastSkippedCount = scan.skippedCount
            guard !scan.urls.isEmpty else {
                phase = .empty
                folderURL = nil
                activeAlert = .noPhotos(folder.lastPathComponent)
                return
            }

            phase = .scanning(done: 0, total: scan.urls.count)
            let analyses = await analyze(urls: scan.urls) { done, total in
                self.phase = .scanning(done: done, total: total)
            }
            try Task.checkCancellation()
            guard generation == scanGeneration else { return }

            install(analyses: analyses, folder: folder, started: started)
        } catch is CancellationError {
            guard generation == scanGeneration else { return }
            phase = .empty
            folderURL = nil
        } catch {
            guard generation == scanGeneration else { return }
            phase = .empty
            folderURL = nil
            activeAlert = .error(title: "无法读取文件夹", message: error.localizedDescription)
        }
    }

    private func analyze(
        urls: [URL],
        progress: @escaping (Int, Int) -> Void
    ) async -> [PhotoAnalysis] {
        var results: [PhotoAnalysis] = []
        results.reserveCapacity(urls.count)

        let options = FocusAnalyzerOptions(
            analysisMaxPixel: settings.analysisQuality.maxPixel,
            topFraction: settings.peakFraction,
            directionalWeight: settings.directionalWeight,
            edgeTrim: settings.edgeTrim,
            useMetal: settings.useMetal
        )
        let classifySubjects = settings.enableSubjectAI
        let subjectWeight = settings.subjectFocusWeight
        let topFraction = settings.peakFraction
        let directionalWeight = settings.directionalWeight
        let concurrency = min(
            settings.analysisConcurrency,
            max(2, ProcessInfo.processInfo.activeProcessorCount - 2)
        )

        let analyzeOne: @Sendable (URL) -> PhotoAnalysis = { url in
            var analysis = FocusAnalyzer.analyze(url: url, options: options)
            if classifySubjects, !analysis.hasError {
                let subject = SubjectClassifier.analyze(
                    url: url,
                    existingFocusRect: analysis.focusRect
                )
                analysis.subject = subject?.prediction

                if let subjectRect = subject?.focusRect {
                    // Attention boxes can cover a large sky area. Tighten them
                    // around the sharpest local blocks before scoring/display.
                    var focusRect = subjectRect
                    if subjectRect.width * subjectRect.height > 0.30,
                       let refined = FocusAnalyzer.refinedFocusRect(
                           blocks: analysis.focusBlocks,
                           within: subjectRect
                       ) {
                        focusRect = refined
                    }
                    analysis.focusRect = focusRect

                    // The global score can be dominated by a sharp background.
                    // Re-score the AI subject/face region and blend it in.
                    if subjectWeight > 0,
                       let region = FocusAnalyzer.regionScore(
                           blocks: analysis.focusBlocks,
                           rect: focusRect,
                           topFraction: topFraction,
                           directionalWeight: directionalWeight
                       ) {
                        let weight = min(1, max(0, subjectWeight))
                        analysis.rawScore = analysis.rawScore * (1 - weight) + region.combined * weight
                        analysis.isotropicScore = analysis.isotropicScore * (1 - weight) + region.isotropic * weight
                        analysis.directionalScore = analysis.directionalScore * (1 - weight) + region.directional * weight
                    }
                }
            }
            return analysis
        }

        await withTaskGroup(of: PhotoAnalysis.self) { group in
            var iterator = urls.makeIterator()
            for _ in 0..<min(concurrency, urls.count) {
                guard let url = iterator.next() else { break }
                group.addTask(priority: .userInitiated) {
                    analyzeOne(url)
                }
            }

            var done = 0
            while let result = await group.next() {
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                results.append(result)
                done += 1
                progress(done, urls.count)
                if let url = iterator.next() {
                    group.addTask(priority: .userInitiated) {
                        analyzeOne(url)
                    }
                }
            }
        }
        return results
    }

    private func install(analyses: [PhotoAnalysis], folder: URL, started: Date) {
        let ordered = analyses.sorted {
            $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
        }
        let batch = SharpnessScoring.makeBatch(rawScores: ordered.map(\.rawScore))

        autoThresholdBase = batch.autoThreshold
        autoThreshold = SharpnessScoring.cappedAutoThreshold(
            base: batch.autoThreshold,
            scores: batch.scores,
            maxBlurFraction: settings.maxBlurFraction
        )
        threshold = adjustedThreshold(autoThreshold)
        isAutoThreshold = true
        allSoftWarning = batch.allSoftWarning

        metalAnalyzedCount = ordered.lazy.filter { $0.backend == .metal }.count
        cpuAnalyzedCount = ordered.lazy.filter { $0.backend == .cpu }.count

        photos = zip(ordered, batch.scores).map { analysis, score in
            PhotoItem(
                analysis: analysis,
                score: score,
                isSharp: !analysis.hasError && score >= threshold
            )
        }
        if settings.autoSelectBlurry {
            selectedURLs = Set(photos.filter { !$0.isSharp && !$0.isFailed }.map(\.id))
        }
        analyzedDuration = Date().timeIntervalSince(started)
        phase = .ready
        UserDefaults.standard.set(folder.path, forKey: lastFolderKey)
        history.log(
            .analysis,
            "完成分析",
            "\(folder.lastPathComponent) · \(photos.count) 张 · \(analysisEngineSummary) · \(String(format: "%.1f", analyzedDuration)) 秒"
        )

        if lastSkippedCount > 0 {
            showToast(
                "已跳过 \(lastSkippedCount) 个无法读取的文件",
                systemImage: "exclamationmark.triangle",
                kind: .warning
            )
        }
    }

    // MARK: - Threshold

    func setManualThreshold(_ value: Double) {
        isAutoThreshold = false
        applyThreshold(value)
    }

    func resetToAutoThreshold() {
        isAutoThreshold = true
        applyThreshold(adjustedThreshold(autoThreshold))
    }

    /// Called when the culling sensitivity changes in Settings. Manual
    /// threshold tweaks are left untouched.
    func reapplySensitivity() {
        guard phase == .ready, isAutoThreshold else { return }
        applyThreshold(adjustedThreshold(autoThreshold))
    }

    func reapplyAutoThreshold() {
        guard phase == .ready, isAutoThreshold, !photos.isEmpty else { return }
        let scores = photos.map(\.score)
        autoThreshold = SharpnessScoring.cappedAutoThreshold(
            base: autoThresholdBase,
            scores: scores,
            maxBlurFraction: settings.maxBlurFraction
        )
        applyThreshold(adjustedThreshold(autoThreshold))
    }

    private func adjustedThreshold(_ base: Double) -> Double {
        min(100, max(0, (base + settings.sensitivity.bias).rounded()))
    }

    func markAllAsBlurry() {
        isAutoThreshold = false
        threshold = 100
        var updated = photos
        for index in updated.indices {
            updated[index].isSharp = false
        }
        photos = updated
    }

    private func applyThreshold(_ value: Double) {
        threshold = min(100, max(0, value.rounded()))
        var updated = photos
        for index in updated.indices {
            updated[index].isSharp = !updated[index].isFailed && updated[index].score >= threshold
        }
        photos = updated
    }

    // MARK: - Selection

    func isSelected(_ photo: PhotoItem) -> Bool {
        selectedURLs.contains(photo.id)
    }

    func toggleSelection(_ photo: PhotoItem) {
        if selectedURLs.contains(photo.id) {
            selectedURLs.remove(photo.id)
        } else {
            selectedURLs.insert(photo.id)
        }
    }

    func toggleSelection(url: URL) {
        if selectedURLs.contains(url) {
            selectedURLs.remove(url)
        } else {
            selectedURLs.insert(url)
        }
    }

    func selectAllBlurred() {
        let urls = blurryPhotos.map(\.id)
        guard !urls.isEmpty else {
            showToast("没有发现疑似失焦的照片", systemImage: "checkmark.circle", kind: .info)
            return
        }
        selectedURLs.formUnion(urls)
        showToast("已选中 \(urls.count) 张疑似失焦照片", systemImage: "checkmark.circle.fill", kind: .info)
    }

    func selectAllVisible() {
        selectedURLs.formUnion(visiblePhotos.map(\.id))
    }

    func areAllSelected(_ photos: [PhotoItem]) -> Bool {
        !photos.isEmpty && photos.allSatisfy { selectedURLs.contains($0.id) }
    }

    func toggleSelection(for photos: [PhotoItem]) {
        guard !photos.isEmpty else { return }
        if areAllSelected(photos) {
            photos.forEach { selectedURLs.remove($0.id) }
        } else {
            photos.forEach { selectedURLs.insert($0.id) }
        }
    }

    func clearSelection() {
        selectedURLs.removeAll()
    }

    // MARK: - Preview

    func openPreview(_ photo: PhotoItem) {
        previewURL = photo.id
    }

    func closePreview() {
        previewURL = nil
    }

    func showPreviousPreview() {
        navigatePreview(step: -1)
    }

    func showNextPreview() {
        navigatePreview(step: 1)
    }

    private func navigatePreview(step: Int) {
        let list = previewNavigationPhotos
        guard !list.isEmpty else { return }
        guard let previewURL,
              let index = list.firstIndex(where: { $0.id == previewURL }) else {
            self.previewURL = list.first?.id
            return
        }
        let next = (index + step + list.count) % list.count
        self.previewURL = list[next].id
    }

    // MARK: - Deletion

    func requestDeleteSelected(mode: DeleteMode) {
        let urls = Array(selectedURLs)
        guard !urls.isEmpty else {
            showToast("请先勾选要删除的照片", systemImage: "checkmark.circle", kind: .info)
            return
        }
        pendingDeleteURLs = urls
        pendingDeleteMode = mode
        if mode == .trash, !settings.confirmBeforeTrash {
            confirmPendingDeletion()
            return
        }
        activeAlert = mode == .trash
            ? .deleteTrash(count: urls.count)
            : .deletePermanent(count: urls.count)
    }

    func requestDelete(url: URL, mode: DeleteMode) {
        pendingDeleteURLs = [url]
        pendingDeleteMode = mode
        if mode == .trash, !settings.confirmBeforeTrash {
            confirmPendingDeletion()
            return
        }
        activeAlert = mode == .trash
            ? .deleteTrash(count: 1)
            : .deletePermanent(count: 1)
    }

    func confirmPendingDeletion() {
        let urls = pendingDeleteURLs
        let mode = pendingDeleteMode
        pendingDeleteURLs = []
        guard !urls.isEmpty else { return }

        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> DeletionOutcome in
                var deleted: [URL] = []
                var failures: [String] = []
                let manager = FileManager.default
                for url in urls {
                    do {
                        if mode == .trash {
                            try manager.trashItem(at: url, resultingItemURL: nil)
                        } else {
                            try manager.removeItem(at: url)
                        }
                        deleted.append(url)
                    } catch {
                        failures.append("\(url.lastPathComponent)：\(error.localizedDescription)")
                    }
                }
                return DeletionOutcome(deleted: deleted, failures: failures)
            }.value

            self.finishDeletion(outcome: outcome, mode: mode)
        }
    }

    private func finishDeletion(outcome: DeletionOutcome, mode: DeleteMode) {
        let deleted = Set(outcome.deleted)
        guard !deleted.isEmpty || !outcome.failures.isEmpty else { return }

        if !deleted.isEmpty {
            withAnimation(.snappy(duration: 0.25)) {
                photos.removeAll { deleted.contains($0.id) }
            }
            selectedURLs.subtract(deleted)
            if let previewURL, deleted.contains(previewURL) {
                let remaining = visiblePhotos
                self.previewURL = remaining.first?.id
            }
            let verb = mode == .trash ? "已移到废纸篓" : "已永久删除"
            history.log(
                .deletion,
                mode == .trash ? "移到废纸篓" : "永久删除",
                "\(deleted.count) 张照片"
            )
            showToast(
                "\(verb) \(deleted.count) 张照片\(mode == .trash ? "，可从废纸篓恢复" : "")",
                systemImage: mode == .trash ? "trash.fill" : "trash.slash.fill",
                kind: .success
            )
        }

        if !outcome.failures.isEmpty {
            let details = outcome.failures.prefix(4).joined(separator: "\n")
            let more = outcome.failures.count > 4 ? "\n…以及另外 \(outcome.failures.count - 4) 项" : ""
            activeAlert = .error(title: "部分照片未能删除", message: details + more)
        }
    }

    // MARK: - Analysis report / Finder / toast / formatting

    func exportAnalysisReport() {
        guard !photos.isEmpty else {
            showToast("请先载入并分析照片", systemImage: "doc.text.magnifyingglass", kind: .info)
            return
        }

        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmm"
        let panel = NSSavePanel()
        panel.title = "导出分析报告"
        panel.message = "包含每张照片的清晰度、主体、合焦框和分析状态。"
        panel.nameFieldStringValue = "FocusCull-分析报告-\(stamp.string(from: Date())).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try analysisReportCSV().write(to: url, options: .atomic)
            history.log(.export, "导出分析报告", "\(photos.count) 张 · \(url.lastPathComponent)")
            showToast("分析报告已导出", systemImage: "square.and.arrow.up", kind: .success)
        } catch {
            activeAlert = .error(title: "导出失败", message: error.localizedDescription)
        }
    }

    private func analysisReportCSV() -> Data {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = .current

        var rows = [[
            "文件名", "路径", "清晰度", "原始分数", "各向同性", "方向平衡",
            "状态", "AI 主体", "主体置信度", "合焦框", "像素宽", "像素高",
            "文件大小", "拍摄时间", "分析引擎", "错误"
        ]]

        for photo in photos {
            let a = photo.analysis
            let status: String
            if a.hasError {
                status = "分析失败"
            } else {
                status = photo.isSharp ? "合焦" : "疑似失焦"
            }
            let rect = a.focusRect.map {
                String(format: "%.3f,%.3f,%.3f,%.3f", $0.x, $0.y, $0.width, $0.height)
            } ?? ""
            rows.append([
                a.fileName,
                a.url.path,
                String(format: "%.1f", photo.score),
                String(format: "%.3f", a.rawScore),
                String(format: "%.3f", a.isotropicScore),
                String(format: "%.3f", a.directionalScore),
                status,
                a.subject?.subject.title ?? "",
                a.subject?.confidenceText ?? "",
                rect,
                String(a.pixelWidth),
                String(a.pixelHeight),
                String(a.fileSize),
                a.captureDate.map { dateFormatter.string(from: $0) } ?? "",
                a.backend.displayName,
                a.errorMessage ?? ""
            ])
        }

        let text = rows.map { row in
            row.map(csvEscape).joined(separator: ",")
        }.joined(separator: "\r\n")
        return Data(("\u{FEFF}" + text).utf8)
    }

    private func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    func revealFolderInFinder() {
        guard let folderURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([folderURL])
    }

    func revealSelectionInFinder() {
        let urls = selectedURLs.isEmpty ? photos.map(\.id) : Array(selectedURLs)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func revealInFinder(_ photo: PhotoItem) {
        NSWorkspace.shared.activateFileViewerSelecting([photo.id])
    }

    func showToast(_ text: String, systemImage: String = "checkmark.circle.fill", kind: ToastKind = .success) {
        toastTask?.cancel()
        let message = ToastMessage(text: text, systemImage: systemImage, kind: kind)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            toast = message
        }
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_600_000_000)
            guard !Task.isCancelled, let self else { return }
            if self.toast?.id == message.id {
                withAnimation(.easeOut(duration: 0.2)) {
                    self.toast = nil
                }
            }
        }
    }

    private func sort(_ items: [PhotoItem]) -> [PhotoItem] {
        switch sortOrder {
        case .fileName:
            return items.sorted(by: { (lhs: PhotoItem, rhs: PhotoItem) in
                lhs.fileName.localizedStandardCompare(rhs.fileName) == .orderedAscending
            })
        case .captureDate:
            return items.sorted(by: { (lhs: PhotoItem, rhs: PhotoItem) in
                (lhs.analysis.captureDate ?? .distantPast) < (rhs.analysis.captureDate ?? .distantPast)
            })
        case .scoreHigh:
            return items.sorted(by: { (lhs: PhotoItem, rhs: PhotoItem) in lhs.score > rhs.score })
        case .scoreLow:
            return items.sorted(by: { (lhs: PhotoItem, rhs: PhotoItem) in lhs.score < rhs.score })
        }
    }

    static func formattedFileSize(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    static func formattedDimensions(_ width: Int, _ height: Int) -> String {
        guard width > 0, height > 0 else { return "—" }
        return "\(width) × \(height)"
    }

    static func formattedDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
