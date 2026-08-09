import AppKit
import XCTest
@testable import PhotoAccessibilityStudio

final class MetadataIntegrationTests: XCTestCase {
    func testWritesExactPreviewFieldWithoutChangingPixels() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pas-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("测试照片.png")
        try makeFixture().write(to: url)

        let writer = MetadataWriter()
        let description = "一幅两像素见方的测试图，左上方为红色，其余区域为蓝色，用于验证无障碍描述写入。"
        let before = try ImageIntegrity().snapshot(of: url)
        let result = try writer.write(description, to: url)
        let after = try ImageIntegrity().snapshot(of: url)

        XCTAssertEqual(try writer.readDescription(from: url), description)
        XCTAssertEqual(result.verifiedDescription, description)
        XCTAssertTrue(result.rawPacketVerified)
        let rawXMP = String(data: try writer.rawXMP(from: url), encoding: .utf8) ?? ""
        XCTAssertTrue(rawXMP.contains(
            "<Iptc4xmpExt:ArtworkContentDescription>\(description)</Iptc4xmpExt:ArtworkContentDescription>"
        ))
        XCTAssertTrue(rawXMP.contains(
            "xmlns:Iptc4xmpExt=\"http://iptc.org/std/Iptc4xmpExt/2008-02-29/\""
        ))
        XCTAssertFalse(rawXMP.contains("<Iptc4xmpExt:AOContentDescription"))
        XCTAssertEqual(before, after)
        XCTAssertEqual(url.lastPathComponent, "测试照片.png")
    }

    func testPacketBuilderRemovesNestedFieldAndEscapesText() throws {
        let existing = Data("""
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description rdf:about="" xmlns:Iptc4xmpExt="http://iptc.org/std/Iptc4xmpExt/2008-02-29/">
              <Iptc4xmpExt:ArtworkOrObject><rdf:Bag><rdf:li>
                <Iptc4xmpExt:AOContentDescription>错误旧值</Iptc4xmpExt:AOContentDescription>
              </rdf:li></rdf:Bag></Iptc4xmpExt:ArtworkOrObject>
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        """.utf8)
        let data = try XMPPacketBuilder().build(existing: existing,
                                                description: "猫 & 狗 <窗边>")
        let xml = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(xml.contains("猫 &amp; 狗 &lt;窗边&gt;"))
        XCTAssertTrue(xml.contains("<Iptc4xmpExt:ArtworkContentDescription>"))
        XCTAssertFalse(xml.contains("<Iptc4xmpExt:AOContentDescription"))
    }

    func testFlatPacketRoundTripAcrossCommonFormats() throws {
        let formats: [(NSBitmapImageRep.FileType, String)] = [
            (.png, "png"), (.jpeg, "jpg"), (.tiff, "tiff")
        ]
        for (type, ext) in formats {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("pas-format-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("格式测试.\(ext)")
            try makeFixture(type: type).write(to: url)
            let before = try ImageIntegrity().snapshot(of: url)
            let description = "\(ext.uppercased()) 测试图的直接扁平无障碍描述。"
            let result = try MetadataWriter().write(description, to: url)
            let raw = String(data: try MetadataWriter().rawXMP(from: url), encoding: .utf8) ?? ""

            XCTAssertEqual(result.verifiedDescription, description)
            XCTAssertEqual(try MetadataWriter().readDescription(from: url), description)
            XCTAssertTrue(raw.contains("<Iptc4xmpExt:ArtworkContentDescription>"))
            XCTAssertFalse(raw.contains("<Iptc4xmpExt:AOContentDescription"))
            XCTAssertEqual(try ImageIntegrity().snapshot(of: url), before)
        }
    }

    private func makeFixture() throws -> Data {
        try makeFixture(type: .png)
    }

    private func makeFixture(type: NSBitmapImageRep.FileType) throws -> Data {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        NSColor.red.setFill()
        NSRect(x: 0, y: 1, width: 1, height: 1).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: type, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return png
    }
}
