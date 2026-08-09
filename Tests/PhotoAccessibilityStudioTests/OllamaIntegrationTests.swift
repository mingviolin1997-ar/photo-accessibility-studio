import AppKit
import XCTest
@testable import PhotoAccessibilityStudio

final class OllamaIntegrationTests: XCTestCase {
    func testLocalQwenDoesNotInventPhotographyAdviceForFlatGraphic() async throws {
        guard ProcessInfo.processInfo.environment["RUN_OLLAMA_INTEGRATION"] == "1" else {
            throw XCTSkip("仅在显式启用本机 Ollama 集成测试时运行")
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pas-qwen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("彩色测试卡.png")
        try makeFixture().write(to: url)

        let preferences = DescriptionPreferences(style: .photographer,
                                                 includeCaptureAdvice: true)
        let client = OllamaClient()
        try await client.checkHealth()
        let description = try await client.describe(url, preferences: preferences)
        print("QWEN_DESCRIPTION=\(description)")

        XCTAssertGreaterThan(description.count, 20)
        XCTAssertFalse(description.contains("```"))
        XCTAssertFalse(description.contains("下次拍摄建议："))
        XCTAssertTrue(description.contains("插画") || description.contains("图形"))
        let result = try MetadataWriter().write(description, to: url)
        XCTAssertEqual(result.verifiedDescription, description)
        XCTAssertEqual(try MetadataWriter().readDescription(from: url), description)
    }

    func testLocalQwenDescribesRealPhotoWithOptionalCaptureAdvice() async throws {
        guard ProcessInfo.processInfo.environment["RUN_OLLAMA_INTEGRATION"] == "1" else {
            throw XCTSkip("仅在显式启用本机 Ollama 集成测试时运行")
        }
        let source = URL(fileURLWithPath:
            "/System/Library/Templates/Data/Library/User Pictures/Animals/Owl.heic")
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw XCTSkip("系统照片夹具不存在")
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pas-photo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("猫头鹰照片.heic")
        try FileManager.default.copyItem(at: source, to: url)

        let preferences = DescriptionPreferences(style: .medium,
                                                 includeCaptureAdvice: true)
        let description = try await OllamaClient().describe(url, preferences: preferences)
        print("QWEN_PHOTO_DESCRIPTION=\(description)")

        XCTAssertGreaterThan(description.count, 20)
        XCTAssertTrue(description.contains("下次拍摄建议："))
        let result = try MetadataWriter().write(description, to: url)
        XCTAssertEqual(result.verifiedDescription, description)
    }

    private func makeFixture() throws -> Data {
        let size = NSSize(width: 640, height: 420)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(calibratedRed: 0.08, green: 0.18, blue: 0.42, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor(calibratedRed: 0.95, green: 0.72, blue: 0.12, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 235, y: 125, width: 170, height: 170)).fill()
        let text = "视觉测试"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 44),
            .foregroundColor: NSColor.white
        ]
        text.draw(at: NSPoint(x: 220, y: 42), withAttributes: attributes)
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return png
    }
}
