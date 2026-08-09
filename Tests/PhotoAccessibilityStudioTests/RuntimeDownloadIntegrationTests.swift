import XCTest
@testable import PhotoAccessibilityStudio

final class RuntimeDownloadIntegrationTests: XCTestCase {
    func testOfficialExifToolDownloadReportsProgressAndMatchesChecksum() async throws {
        guard ProcessInfo.processInfo.environment["RUN_RUNTIME_DOWNLOAD_INTEGRATION"] == "1" else {
            throw XCTSkip("仅在显式启用网络下载集成测试时运行")
        }
        var updates: [RuntimeProgress] = []
        let file = try await RuntimeFileDownloader().download(
            from: URL(string: "https://sourceforge.net/projects/exiftool/files/Image-ExifTool-13.59.tar.gz/download")!,
            step: "下载测试",
            expectedBytes: 7_916_358,
            expectedSHA256: "668ea3acececb7235fbd0f4900e72d5f12c9b07e5c778fd36cb1e9b5828fd65a"
        ) { updates.append($0) }
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber,
                       NSNumber(value: 7_916_358))
        XCTAssertFalse(updates.isEmpty)
        XCTAssertTrue(updates.contains { $0.downloaded > 0 })
    }
}
