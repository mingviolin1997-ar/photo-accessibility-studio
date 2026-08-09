import XCTest
@testable import PhotoAccessibilityStudio

final class PhotoCompatibilityTests: XCTestCase {
    private var sampleFolder: URL? {
        ProcessInfo.processInfo.environment["PAS_SAMPLE_PHOTO_FOLDER"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    func testProvidedSampleFolderAllPhotosEncodeAndExposeMetadata() throws {
        guard let folder = sampleFolder else {
            throw XCTSkip("设置 PAS_SAMPLE_PHOTO_FOLDER 后运行用户照片兼容性测试")
        }
        let photos = try supportedPhotos(in: folder)
        XCTAssertFalse(photos.isEmpty)
        let metadata = try PhotoMetadataReader().read(photos)
        XCTAssertEqual(metadata.count, photos.count)

        for photo in photos {
            let encoded = try ImageEncoder().encode(for: photo, maximumDimension: 1280)
            XCTAssertGreaterThan(encoded.byteCount, 0, photo.lastPathComponent)
            XCTAssertLessThanOrEqual(max(encoded.pixelWidth, encoded.pixelHeight), 1280,
                                     photo.lastPathComponent)
            XCTAssertNotNil(metadata[photo.standardizedFileURL]?.format,
                            photo.lastPathComponent)
        }
    }

    func testProvidedSampleFolderAllPhotosAcceptDirectFlatMetadata() throws {
        guard let folder = sampleFolder else {
            throw XCTSkip("设置 PAS_SAMPLE_PHOTO_FOLDER 后运行用户照片兼容性测试")
        }
        let photos = try supportedPhotos(in: folder)
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("pas-user-samples-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        for (offset, source) in photos.enumerated() {
            let copy = temporary.appendingPathComponent("\(offset + 1).\(source.pathExtension)")
            try FileManager.default.copyItem(at: source, to: copy)
            let before = try ImageIntegrity().snapshot(of: copy)
            let description = "第 \(offset + 1) 张用户兼容性测试照片。"
            let result = try MetadataWriter().write(description, to: copy)
            XCTAssertEqual(result.verifiedDescription, description, source.lastPathComponent)
            XCTAssertEqual(try ImageIntegrity().snapshot(of: copy), before,
                           source.lastPathComponent)
        }
    }

    func testProvidedSampleFolderAllPhotosGenerateDescriptions() async throws {
        guard ProcessInfo.processInfo.environment["RUN_SAMPLE_MODEL_INTEGRATION"] == "1",
              let folder = sampleFolder else {
            throw XCTSkip("显式启用 RUN_SAMPLE_MODEL_INTEGRATION 后运行十张照片模型回归")
        }
        let photos = try supportedPhotos(in: folder)
        let engine: InferenceEngine = ProcessInfo.processInfo.environment["PAS_INFERENCE_ENGINE"] == "mlx"
            ? .mlx : .ollama
        var retainedMLXService: MLXRuntimeSetupService?
        if engine == .mlx {
            let service = MLXRuntimeSetupService()
            let missing = await service.inspect(model: .qwen35_4B)
            XCTAssertNil(missing)
            retainedMLXService = service
        } else {
            try await OllamaClient(configuration: AppConfiguration(modelName: "qwen3.5:4b"))
                .checkHealth()
        }
        let client = LocalVisionClient(engine: engine, model: .qwen35_4B)
        for (offset, photo) in photos.enumerated() {
            let started = Date()
            do {
                let description = try await client.describe(
                    photo,
                    preferences: .init(style: .low, includeCaptureAdvice: false)
                )
                XCTAssertGreaterThan(description.count, 20, photo.lastPathComponent)
                print("SAMPLE_\(offset + 1)_SECONDS=\(Date().timeIntervalSince(started))")
            } catch {
                XCTFail("\(photo.lastPathComponent)：\(error.localizedDescription)")
            }
        }
        _ = retainedMLXService
    }

    private func supportedPhotos(in folder: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter {
            AppConfiguration.supportedExtensions.contains($0.pathExtension.lowercased())
        }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
