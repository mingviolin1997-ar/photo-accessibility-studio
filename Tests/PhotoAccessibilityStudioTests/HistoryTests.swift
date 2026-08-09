import XCTest
@testable import PhotoAccessibilityStudio

final class HistoryTests: XCTestCase {
    func testHistoryUsesSecondPrecisionNameAndKeepsOnlyDescribedPhotos() {
        var described = PhotoJob(url: URL(fileURLWithPath: "/tmp/described.jpg"))
        described.description = "一张已有描述的测试照片。"
        let waiting = PhotoJob(url: URL(fileURLWithPath: "/tmp/waiting.jpg"))
        let batch = HistoryBatch(createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                                 jobs: [described, waiting])

        XCTAssertEqual(batch.jobs.map(\.id), [described.id])
        XCTAssertNotNil(batch.name.range(
            of: #"^\d{4}年\d{2}月\d{2}日 \d{2}时\d{2}分\d{2}秒$"#,
            options: .regularExpression
        ))
    }

    func testThirtyDayRetentionRemovesOnlyExpiredHistory() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        var job = PhotoJob(url: URL(fileURLWithPath: "/tmp/photo.jpg"))
        job.description = "保留测试描述。"
        let recent = HistoryBatch(createdAt: now.addingTimeInterval(-29 * 24 * 60 * 60),
                                  jobs: [job])
        let expired = HistoryBatch(createdAt: now.addingTimeInterval(-31 * 24 * 60 * 60),
                                   jobs: [job])

        let retained = HistoryBatch.retaining([expired, recent], days: 30, now: now)

        XCTAssertEqual(retained.map(\.id), [recent.id])
    }

    func testHistoryStoreRoundTripsAndPurgesAtLoad() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pas-history-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        var job = PhotoJob(url: URL(fileURLWithPath: "/tmp/photo.jpg"))
        job.description = "历史存储测试描述。"
        let recent = HistoryBatch(createdAt: now.addingTimeInterval(-10), jobs: [job])
        let expired = HistoryBatch(createdAt: now.addingTimeInterval(-40 * 24 * 60 * 60),
                                   jobs: [job])
        let store = StateStore(baseDirectory: root)

        store.saveHistory([expired, recent])
        let loaded = store.loadHistory(retentionDays: 30, now: now)

        XCTAssertEqual(loaded, [recent])
    }
}
