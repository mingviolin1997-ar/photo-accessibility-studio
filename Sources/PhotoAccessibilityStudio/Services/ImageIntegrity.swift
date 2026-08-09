import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

struct ImageIntegritySnapshot: Equatable {
    let fileName: String
    let pixelWidth: Int
    let pixelHeight: Int
    let pixelDigest: String
}

enum ImageIntegrityError: LocalizedError {
    case cannotRead
    case cannotDecode

    var errorDescription: String? {
        switch self {
        case .cannotRead: return "无法读取图像尺寸"
        case .cannotDecode: return "无法解码图像像素"
        }
    }
}

struct ImageIntegrity {
    func snapshot(of url: URL) throws -> ImageIntegritySnapshot {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw ImageIntegrityError.cannotRead
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImageIntegrityError.cannotDecode
        }
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ImageIntegrityError.cannotDecode }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let digest = SHA256.hash(data: Data(pixels)).map { String(format: "%02x", $0) }.joined()
        return ImageIntegritySnapshot(
            fileName: url.lastPathComponent,
            pixelWidth: width,
            pixelHeight: height,
            pixelDigest: digest
        )
    }
}
