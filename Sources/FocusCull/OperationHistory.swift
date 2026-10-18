import Combine
import Foundation
import SwiftUI

enum OperationCategory: String, Codable, CaseIterable {
    case analysis
    case append
    case deletion
    case settings
    case export

    var title: String {
        switch self {
        case .analysis: return "分析"
        case .append: return "追加"
        case .deletion: return "删除"
        case .settings: return "设置"
        case .export: return "导出"
        }
    }

    var systemImage: String {
        switch self {
        case .analysis: return "scope"
        case .append: return "plus.circle"
        case .deletion: return "trash"
        case .settings: return "gearshape"
        case .export: return "square.and.arrow.up"
        }
    }

    var tint: Color {
        switch self {
        case .analysis: return Theme.accent
        case .append: return Theme.sharp
        case .deletion: return Theme.danger
        case .settings: return .secondary
        case .export: return Theme.blur
        }
    }
}

struct OperationEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let date: Date
    let category: OperationCategory
    let title: String
    let detail: String

    init(id: UUID = UUID(), date: Date = Date(), category: OperationCategory, title: String, detail: String) {
        self.id = id
        self.date = date
        self.category = category
        self.title = title
        self.detail = detail
    }
}

@MainActor
final class OperationHistory: ObservableObject {
    @Published private(set) var entries: [OperationEntry] = []

    private let defaults: UserDefaults
    private let storageKey: String
    private let limit = 800

    init(defaults: UserDefaults = .standard, storageKey: String = "FocusCull.operationHistory.v1") {
        self.defaults = defaults
        self.storageKey = storageKey
        load()
    }

    func log(_ category: OperationCategory, _ title: String, _ detail: String) {
        let entry = OperationEntry(category: category, title: title, detail: detail)
        entries.insert(entry, at: 0)
        if entries.count > limit {
            entries.removeLast(entries.count - limit)
        }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    var csvData: Data {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current

        var lines = ["时间,类型,操作,详情"]
        for entry in entries {
            lines.append([
                formatter.string(from: entry.date),
                entry.category.title,
                entry.title,
                entry.detail
            ].map(csvEscape).joined(separator: ","))
        }
        return Data(("\u{FEFF}" + lines.joined(separator: "\r\n")).utf8)
    }

    var plainText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return entries.map {
            "[\(formatter.string(from: $0.date))] \($0.category.title) · \($0.title)：\($0.detail)"
        }.joined(separator: "\n")
    }

    private func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([OperationEntry].self, from: data) {
            entries = Array(decoded.prefix(limit))
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entries) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
