import Foundation
import FocusCullCore

let arguments = CommandLine.arguments.dropFirst()
guard let folderArgument = arguments.first(where: { !$0.hasPrefix("--") }) else {
    fputs("usage: focuscull-tool <folder> [--recursive] [--json] [--cpu] [--subjects]\n", stderr)
    exit(2)
}

let recursive = arguments.contains("--recursive")
let jsonOutput = arguments.contains("--json")
let useCPU = arguments.contains("--cpu")
let classifySubjects = arguments.contains("--subjects")
let options = FocusAnalyzerOptions(useMetal: !useCPU)
let folder = URL(fileURLWithPath: folderArgument, isDirectory: true)

do {
    let scan = try PhotoScanner.scan(folder: folder, recursive: recursive)
    guard !scan.urls.isEmpty else {
        fputs("No supported images found in \(folder.path)\n", stderr)
        exit(1)
    }

    var analyses: [PhotoAnalysis] = []
    analyses.reserveCapacity(scan.urls.count)
    let started = Date()
    for (index, url) in scan.urls.enumerated() {
        var result = FocusAnalyzer.analyze(url: url, options: options)
        if classifySubjects, !result.hasError {
            let subject = SubjectClassifier.analyze(
                url: url,
                existingFocusRect: result.focusRect
            )
            result.subject = subject?.prediction
            if let focusRect = subject?.focusRect {
                result.focusRect = focusRect
            }
        }
        analyses.append(result)
        if !jsonOutput {
            fputs("\rAnalyzing \(index + 1)/\(scan.urls.count)", stderr)
        }
    }
    if !jsonOutput { fputs("\n", stderr) }

    let batch = SharpnessScoring.makeBatch(rawScores: analyses.map(\.rawScore))
    let pairs = zip(analyses, batch.scores).map { analysis, score in
        (
            analysis: analysis,
            score: score,
            sharp: score >= batch.autoThreshold && analysis.errorMessage == nil
        )
    }.sorted { $0.score > $1.score }

    if jsonOutput {
        let payload: [[String: Any]] = pairs.map { pair in
            [
                "file": pair.analysis.fileName,
                "path": pair.analysis.url.path,
                "raw": pair.analysis.rawScore,
                "isotropic": pair.analysis.isotropicScore,
                "directional": pair.analysis.directionalScore,
                "score": pair.score,
                "sharp": pair.sharp,
                "backend": pair.analysis.backend.rawValue,
                "subject": pair.analysis.subject?.subject.rawValue as Any,
                "subjectConfidence": pair.analysis.subject?.confidence as Any,
                "focusRect": pair.analysis.focusRect.map { ["x": $0.x, "y": $0.y, "width": $0.width, "height": $0.height] } as Any,
                "error": pair.analysis.errorMessage as Any
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        print(String(data: data, encoding: .utf8) ?? "[]")
    } else {
        print("folder: \(folder.path)")
        print("images: \(scan.urls.count)   auto threshold: \(Int(batch.autoThreshold))   p90 raw: \(String(format: "%.1f", batch.referenceRawScore))   max raw: \(String(format: "%.1f", batch.maximumRawScore))   all-soft: \(batch.allSoftWarning)")
        for pair in pairs {
            let status = pair.sharp ? "SHARP" : "BLUR "
            print(String(
                format: "%@  %6.1f  raw %7.1f  iso %7.1f  dir %7.1f  %@  subject=%@  rect=%@  %@",
                status,
                pair.score,
                pair.analysis.rawScore,
                pair.analysis.isotropicScore,
                pair.analysis.directionalScore,
                pair.analysis.backend.rawValue,
                pair.analysis.subject?.subject.rawValue ?? "-",
                pair.analysis.focusRect.map { String(format: "%.2f,%.2f,%.2f,%.2f", $0.x, $0.y, $0.width, $0.height) } ?? "-",
                pair.analysis.fileName
            ))
        }
    }
    fputs(String(format: "elapsed: %.2fs\n", Date().timeIntervalSince(started)), stderr)
} catch {
    fputs("error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
