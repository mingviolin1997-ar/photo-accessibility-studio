import Foundation
import ImageIO

struct PhotoFileMetadata: Equatable {
    var existingDescription: String?
    var captureDate: Date?
    var format: String?
    var pixelWidth: Int?
    var pixelHeight: Int?
}

struct PhotoMetadataReader {
    private let runner = ProcessRunner()

    func read(_ urls: [URL]) throws -> [URL: PhotoFileMetadata] {
        guard !urls.isEmpty else { return [:] }
        guard let tool = RuntimeToolLocator.exifTool() else {
            return Dictionary(uniqueKeysWithValues: urls.map { ($0.standardizedFileURL, imageIOFallback($0)) })
        }
        let arguments = tool.prefixArguments + [
            "-config", "", "-charset", "filename=UTF8", "-json", "-s",
            "-XMP-iptcExt:ArtworkContentDescription",
            "-DateTimeOriginal", "-CreateDate", "-FileType", "-ImageWidth", "-ImageHeight",
            "--"
        ] + urls.map(\.path)
        let output = try runner.run(executable: tool.executable, arguments: arguments)
        guard output.status == 0,
              let data = output.standardOutput.data(using: .utf8),
              let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return Dictionary(uniqueKeysWithValues: urls.map { ($0.standardizedFileURL, imageIOFallback($0)) })
        }
        var result: [URL: PhotoFileMetadata] = [:]
        for row in rows {
            guard let path = row["SourceFile"] as? String else { continue }
            let url = URL(fileURLWithPath: path).standardizedFileURL
            let fallback = imageIOFallback(url)
            result[url] = PhotoFileMetadata(
                existingDescription: row["ArtworkContentDescription"] as? String,
                captureDate: parseDate(row["DateTimeOriginal"] as? String)
                    ?? parseDate(row["CreateDate"] as? String)
                    ?? fallback.captureDate,
                format: row["FileType"] as? String ?? fallback.format,
                pixelWidth: integer(row["ImageWidth"]) ?? fallback.pixelWidth,
                pixelHeight: integer(row["ImageHeight"]) ?? fallback.pixelHeight
            )
        }
        for url in urls where result[url.standardizedFileURL] == nil {
            result[url.standardizedFileURL] = imageIOFallback(url)
        }
        return result
    }

    private func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let formats = [
            "yyyy:MM:dd HH:mm:ss.SSSXXX",
            "yyyy:MM:dd HH:mm:ssXXX",
            "yyyy:MM:dd HH:mm:ss.SSS",
            "yyyy:MM:dd HH:mm:ss"
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = .current
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private func imageIOFallback(_ url: URL) -> PhotoFileMetadata {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return PhotoFileMetadata()
        }
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let capture = parseDate(exif?[kCGImagePropertyExifDateTimeOriginal] as? String)
        return PhotoFileMetadata(
            captureDate: capture,
            format: CGImageSourceGetType(source) as String?,
            pixelWidth: properties[kCGImagePropertyPixelWidth] as? Int,
            pixelHeight: properties[kCGImagePropertyPixelHeight] as? Int
        )
    }
}
