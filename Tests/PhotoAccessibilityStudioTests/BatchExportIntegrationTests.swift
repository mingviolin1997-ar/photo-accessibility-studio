import AppKit
import XCTest
@testable import PhotoAccessibilityStudio

final class BatchExportIntegrationTests: XCTestCase {
    func testExportWritesAndIndependentlyVerifiesCopyWithoutMutatingSource() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pas-export-\(UUID().uuidString)", isDirectory: true)
        let sourceFolder = root.appendingPathComponent("原始素材", isDirectory: true)
        let outputFolder = root.appendingPathComponent("导出结果", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder,
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outputFolder,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = sourceFolder.appendingPathComponent("测试照片.png")
        try makeFixture().write(to: source)
        let before = try ImageIntegrity().snapshot(of: source)
        let description = "一幅蓝底测试图，中央有一个黄色圆形，用于验证批量导出的无障碍描述。"

        let exported = try BatchExportService().export(
            description: description,
            from: source,
            to: outputFolder
        )

        XCTAssertEqual(exported.outputURL.lastPathComponent, source.lastPathComponent)
        XCTAssertNil(try MetadataWriter().readDescription(from: source))
        XCTAssertEqual(try ImageIntegrity().snapshot(of: source), before)
        XCTAssertEqual(try MetadataWriter().readDescription(from: exported.outputURL),
                       description)
        let raw = String(data: try MetadataWriter().rawXMP(from: exported.outputURL),
                         encoding: .utf8) ?? ""
        XCTAssertTrue(raw.contains(
            "<Iptc4xmpExt:ArtworkContentDescription>\(description)</Iptc4xmpExt:ArtworkContentDescription>"
        ))
        XCTAssertFalse(raw.contains("<Iptc4xmpExt:AOContentDescription"))

        let exportedAgain = try BatchExportService().export(
            description: description,
            from: source,
            to: outputFolder
        )
        XCTAssertNotEqual(exportedAgain.outputURL, exported.outputURL)
        XCTAssertTrue(exportedAgain.outputURL.lastPathComponent.contains("无障碍描述"))
    }

    private func makeFixture() throws -> Data {
        let image = NSImage(size: NSSize(width: 120, height: 80))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 120, height: 80).fill()
        NSColor.systemYellow.setFill()
        NSBezierPath(ovalIn: NSRect(x: 40, y: 20, width: 40, height: 40)).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }
}
