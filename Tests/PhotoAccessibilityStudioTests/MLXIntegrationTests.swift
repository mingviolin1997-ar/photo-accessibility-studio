import XCTest
@testable import PhotoAccessibilityStudio

final class MLXIntegrationTests: XCTestCase {
    func testManagedMLXRuntimeDescribesPhotoAndKeepsVerifiedXMPWorkflow() async throws {
        guard ProcessInfo.processInfo.environment["RUN_MLX_INTEGRATION"] == "1" else {
            throw XCTSkip("仅在显式启用本机 MLX 集成测试时下载并运行模型")
        }
        let service = MLXRuntimeSetupService()
        try await service.install(model: .qwen35_4B) { progress in
            print("MLX_PROGRESS=\(progress.step)|\(progress.detail)")
        }
        let missing = await service.inspect(model: .qwen35_4B)
        XCTAssertNil(missing)
        XCTAssertTrue(service.installedModelNames().contains(VisionModel.qwen35_4B.mlxName))

        let source = URL(fileURLWithPath:
            "/System/Library/Templates/Data/Library/User Pictures/Animals/Owl.heic")
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw XCTSkip("系统照片夹具不存在")
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pas-mlx-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let photo = directory.appendingPathComponent("MLX测试.heic")
        try FileManager.default.copyItem(at: source, to: photo)

        let description = try await MLXVLMClient(model: .qwen35_4B).describe(
            photo,
            preferences: .init(style: .low, includeCaptureAdvice: false)
        )
        XCTAssertGreaterThan(description.count, 20)
        let before = try ImageIntegrity().snapshot(of: photo)
        let write = try MetadataWriter().write(description, to: photo)
        XCTAssertEqual(write.verifiedDescription, description)
        XCTAssertEqual(try ImageIntegrity().snapshot(of: photo), before)
    }
}
