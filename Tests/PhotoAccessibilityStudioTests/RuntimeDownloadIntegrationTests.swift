import XCTest
@testable import PhotoAccessibilityStudio

final class RuntimeDownloadIntegrationTests: XCTestCase {
    private let exifURL = URL(string:
        "https://sourceforge.net/projects/exiftool/files/Image-ExifTool-13.59.tar.gz/download")!
    private let exifBytes: Int64 = 7_916_358
    private let exifSHA = "668ea3acececb7235fbd0f4900e72d5f12c9b07e5c778fd36cb1e9b5828fd65a"

    func testOfficialExifToolDownloadReportsProgressAndMatchesChecksum() async throws {
        guard ProcessInfo.processInfo.environment["RUN_RUNTIME_DOWNLOAD_INTEGRATION"] == "1" else {
            throw XCTSkip("仅在显式启用网络下载集成测试时运行")
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("runtime-download-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var prefixRequest = URLRequest(url: exifURL)
        prefixRequest.setValue("bytes=0-65535", forHTTPHeaderField: "Range")
        prefixRequest.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let (prefix, prefixResponse) = try await URLSession.shared.data(for: prefixRequest)
        XCTAssertEqual((prefixResponse as? HTTPURLResponse)?.statusCode, 206)
        XCTAssertEqual(prefix.count, 65_536)
        let partial = directory.appendingPathComponent("\(exifSHA).part")
        try prefix.write(to: partial, options: .atomic)

        var updates: [RuntimeProgress] = []
        let file = try await RuntimeFileDownloader(downloadDirectory: directory).download(
            from: exifURL,
            step: "下载测试",
            expectedBytes: exifBytes,
            expectedSHA256: exifSHA
        ) { updates.append($0) }
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber,
                       NSNumber(value: exifBytes))
        XCTAssertFalse(updates.isEmpty)
        XCTAssertTrue(updates.contains { $0.downloaded > 0 })
        XCTAssertTrue(updates.contains { $0.step.contains("断点续传") })
        XCTAssertTrue(updates.contains { $0.step.contains("服务器连接正常") })
        XCTAssertTrue(updates.contains { $0.step.contains("校验完成") })
    }

    func testOfficialRuntimeEndpointsSupportSafeProbe() async throws {
        guard ProcessInfo.processInfo.environment["RUN_RUNTIME_NETWORK_PROBE"] == "1" else {
            throw XCTSkip("仅在显式启用运行环境网络探测时运行")
        }
        let targets: [(URL, Int64?)] = [
            (URL(string: "https://github.com/ollama/ollama/releases/download/v0.32.6/ollama-darwin.tgz")!,
             145_435_565),
            (exifURL, exifBytes),
            (URL(string: "https://github.com/astral-sh/uv/releases/download/0.11.10/uv-aarch64-apple-darwin.tar.gz")!,
             20_728_170)
        ]
        for (url, expectedBytes) in targets {
            let probe = try await RuntimeRemoteProber().probe(url)
            XCTAssertTrue([200, 206].contains(probe.statusCode), probe.finalURL.absoluteString)
            XCTAssertEqual(probe.finalURL.scheme, "https")
            XCTAssertTrue(probe.supportsRanges, probe.finalURL.absoluteString)
            XCTAssertEqual(probe.totalBytes, expectedBytes, probe.finalURL.absoluteString)
        }
    }
}
