import Foundation

struct StateStore {
    private var stateURL: URL? {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        return root.appendingPathComponent("PhotoAccessibilityStudio", isDirectory: true)
            .appendingPathComponent("queue.json")
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
}
