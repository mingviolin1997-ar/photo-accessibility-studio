import Foundation

struct StateStore {
    private let baseDirectory: URL?

    init(baseDirectory: URL? = nil) {
        self.baseDirectory = baseDirectory
    }

    private var storeDirectory: URL? {
        if let baseDirectory { return baseDirectory }
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        return root.appendingPathComponent("PhotoAccessibilityStudio", isDirectory: true)
    }

    private var stateURL: URL? {
        storeDirectory?.appendingPathComponent("queue.json")
    }

    private var historyURL: URL? {
        storeDirectory?.appendingPathComponent("history.json")
    }

    func load() -> [PhotoJob] {
        guard let url = stateURL,
              let data = try? Data(contentsOf: url),
              let jobs = try? JSONDecoder().decode([PhotoJob].self, from: data) else { return [] }
        return jobs.filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }

    func save(_ jobs: [PhotoJob]) {
        guard let url = stateURL,
              let data = try? JSONEncoder().encode(jobs) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            AppLogger.shared.log("保存队列失败：\(error.localizedDescription)")
        }
    }

    func loadHistory(retentionDays: Int = 30,
                     now: Date = Date()) -> [HistoryBatch] {
        guard let url = historyURL,
              let data = try? Data(contentsOf: url),
              let batches = try? JSONDecoder().decode([HistoryBatch].self,
                                                       from: data) else { return [] }
        return HistoryBatch.retaining(batches, days: retentionDays, now: now)
    }

    func saveHistory(_ batches: [HistoryBatch]) {
        guard let url = historyURL,
              let data = try? JSONEncoder().encode(batches) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            AppLogger.shared.log("保存历史失败：\(error.localizedDescription)")
        }
    }
}
