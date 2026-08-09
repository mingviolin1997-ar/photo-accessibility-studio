import Foundation

struct HistoryBatch: Identifiable, Codable, Equatable {
    let id: UUID
    let createdAt: Date
    var name: String
    var jobs: [PhotoJob]

    init(id: UUID = UUID(),
         createdAt: Date = Date(),
         name: String? = nil,
         jobs: [PhotoJob]) {
        self.id = id
        self.createdAt = createdAt
        self.name = name ?? Self.defaultName(for: createdAt)
        self.jobs = jobs.filter { !$0.description.isEmpty }
    }

    static func defaultName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy年MM月dd日 HH时mm分ss秒"
        return formatter.string(from: date)
    }

    static func retaining(_ batches: [HistoryBatch],
                          days: Int,
                          now: Date = Date()) -> [HistoryBatch] {
        let safeDays = min(max(days, 1), 365)
        let cutoff = now.addingTimeInterval(-Double(safeDays) * 24 * 60 * 60)
        return batches
            .filter { $0.createdAt >= cutoff && !$0.jobs.isEmpty }
            .sorted { $0.createdAt > $1.createdAt }
    }
}
