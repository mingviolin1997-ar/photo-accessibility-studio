import XCTest
@testable import PhotoAccessibilityStudio

final class RuntimeReliabilityTests: XCTestCase {
    func testProbeReadsTotalFromPartialContentRange() {
        XCTAssertEqual(RuntimeRemoteProber.totalBytes(statusCode: 206,
                                                      contentRange: "bytes 0-0/145435565",
                                                      contentLength: "1"),
                       145_435_565)
        XCTAssertEqual(RuntimeRemoteProber.totalBytes(statusCode: 200,
                                                      contentRange: nil,
                                                      contentLength: "20728170"),
                       20_728_170)
        XCTAssertNil(RuntimeRemoteProber.totalBytes(statusCode: 206,
                                                    contentRange: "bytes 0-0/*",
                                                    contentLength: "1"))
    }

    func testDownloadDiagnosticsExplainCommonFailures() {
        XCTAssertTrue(RuntimeDownloadDiagnostics.message(for: URLError(.timedOut))
            .contains("超时"))
        XCTAssertTrue(RuntimeDownloadDiagnostics.message(for: URLError(.notConnectedToInternet))
            .contains("没有可用网络"))
        XCTAssertTrue(RuntimeDownloadDiagnostics.message(for: URLError(.cannotFindHost))
            .contains("DNS"))
        XCTAssertTrue(RuntimeDownloadDiagnostics.message(for: URLError(.secureConnectionFailed))
            .contains("安全连接"))
    }

    func testFailureRecordOnlyReturnsForMatchingEngineAndModel() {
        let suite = "RuntimeFailureStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let date = Date(timeIntervalSince1970: 123)

        RuntimeFailureStore.save(engine: .mlx,
                                 model: .gemma4E4B,
                                 reason: "连接超时",
                                 defaults: defaults,
                                 date: date)

        XCTAssertEqual(RuntimeFailureStore.matching(engine: .mlx,
                                                    model: .gemma4E4B,
                                                    defaults: defaults),
                       RuntimeFailureRecord(engine: "mlx",
                                            model: "gemma4E4B",
                                            reason: "连接超时",
                                            date: date))
        XCTAssertNil(RuntimeFailureStore.matching(engine: .ollama,
                                                  model: .gemma4E4B,
                                                  defaults: defaults))
        RuntimeFailureStore.clear(engine: .mlx, model: .gemma4E4B, defaults: defaults)
        XCTAssertNil(RuntimeFailureStore.matching(engine: .mlx,
                                                  model: .gemma4E4B,
                                                  defaults: defaults))
    }

    func testMLXManifestRequiresEveryFileAtExactSize() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mlx-manifest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("{}".utf8).write(to: directory.appendingPathComponent("config.json"))
        try Data(repeating: 7, count: 12).write(to: directory.appendingPathComponent("model.safetensors"))
        let manifest = #"{"revision":"fixed","files":[{"path":"config.json","size":2},{"path":"model.safetensors","size":12}]}"#
        try Data(manifest.utf8).write(to: directory.appendingPathComponent(".pas-files.json"))

        XCTAssertTrue(MLXRuntimeSetupService.validateModelManifest(at: directory,
                                                                   expectedRevision: "fixed"))
        XCTAssertFalse(MLXRuntimeSetupService.validateModelManifest(at: directory,
                                                                    expectedRevision: "other"))
        try Data(repeating: 7, count: 11).write(to: directory.appendingPathComponent("model.safetensors"))
        XCTAssertFalse(MLXRuntimeSetupService.validateModelManifest(at: directory,
                                                                    expectedRevision: "fixed"))
    }

    func testEmbeddedMLXDownloaderScriptHasValidPythonSyntax() throws {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", "import sys; compile(sys.stdin.read(), '<mlx-downloader>', 'exec')"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output
        try process.run()
        input.fileHandleForWriting.write(Data(MLXRuntimeSetupService.modelDownloaderScript.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        let message = String(data: output.fileHandleForReading.readDataToEndOfFile(),
                             encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, message)
    }
}
